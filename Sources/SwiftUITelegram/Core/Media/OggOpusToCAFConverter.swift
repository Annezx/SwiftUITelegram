import Foundation

/// Zero-dependency remuxer that repackages Telegram OGG/Opus voice messages (`.oga` / `.ogg`)
/// into Apple Core Audio Format (`.caf`) without transcoding, enabling native playback via
/// macOS `AVAudioPlayer` / CoreAudio's built-in `kAudioFormatOpus` decoder.
enum OggOpusToCAFConverter {
    enum ConversionError: LocalizedError {
        case invalidOggStream
        case missingOpusHeader
        case unsupportedChannelCount(UInt8)
        case emptyAudioStream

        var errorDescription: String? {
            switch self {
            case .invalidOggStream:
                return "无效的 OGG 音频封装格式。"
            case .missingOpusHeader:
                return "缺少 OpusHead 音频头信息。"
            case .unsupportedChannelCount(let count):
                return "暂不支持 \(count) 声道 Opus 音频。"
            case .emptyAudioStream:
                return "音频文件不包含有效的 Opus 数据包。"
            }
        }
    }

    private struct OpusHead {
        let channels: UInt8
        let preSkip: UInt16
    }

    private struct OpusPacket {
        let data: Data
        let frameCount48k: Int
    }

    /// Returns true if the file starts with the OGG capture pattern (`OggS`).
    static func isOggContainer(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let prefix = (try? handle.read(upToCount: 4)) ?? nil, prefix.count == 4 else { return false }
        return prefix[0] == 0x4F && prefix[1] == 0x67 && prefix[2] == 0x67 && prefix[3] == 0x53
    }

    /// Returns a cached `.caf` URL for the given OGG/Opus source file, converting on demand.
    static func playableCAFURL(for sourceURL: URL) throws -> URL {
        let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = (attrs?[.modificationDate] as? Foundation.Date)?.timeIntervalSince1970 ?? 0
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let cacheKey = "\(baseName)_\(size)_\(Int(mtime)).caf"
        let destinationURL = AppConfiguration.audioTranscodeCacheDirectory.appendingPathComponent(cacheKey)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }

        let oggData = try Data(contentsOf: sourceURL)
        let cafData = try convertOggOpusDataToCAF(oggData)
        try cafData.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    static func convertOggOpusDataToCAF(_ oggData: Data) throws -> Data {
        let (head, packets, finalGranule) = try parseOggOpus(oggData)
        return buildCAF(head: head, packets: packets, finalGranule: finalGranule)
    }

    // MARK: - OGG Demuxer (RFC 3533 + RFC 7845)

    private static func parseOggOpus(_ data: Data) throws -> (OpusHead, [OpusPacket], UInt64) {
        let bytes = [UInt8](data)
        let totalCount = bytes.count
        guard totalCount >= 27,
              bytes[0] == 0x4F, bytes[1] == 0x67, bytes[2] == 0x67, bytes[3] == 0x53
        else {
            throw ConversionError.invalidOggStream
        }

        var offset = 0
        var opusHead: OpusHead?
        var skippedTags = false
        var packets: [OpusPacket] = []
        var currentPacket = Data()
        var lastValidGranule: UInt64 = 0

        while offset + 27 <= totalCount {
            // Resync if needed; valid OGG pages always begin with "OggS".
            guard bytes[offset] == 0x4F,
                  bytes[offset + 1] == 0x67,
                  bytes[offset + 2] == 0x67,
                  bytes[offset + 3] == 0x53
            else {
                break
            }

            let headerType = bytes[offset + 5]
            let isContinuation = (headerType & 0x01) != 0
            let granule = readUInt64LE(bytes, at: offset + 6)
            if granule != UInt64.max {
                lastValidGranule = granule
            }

            let segmentCount = Int(bytes[offset + 26])
            let segmentTableStart = offset + 27
            let payloadStart = segmentTableStart + segmentCount
            guard payloadStart <= totalCount else { break }

            if !isContinuation && !currentPacket.isEmpty {
                currentPacket.removeAll(keepingCapacity: true)
            }

            var cursor = payloadStart
            var truncated = false

            for segIdx in 0..<segmentCount {
                let segLen = Int(bytes[segmentTableStart + segIdx])
                guard cursor + segLen <= totalCount else {
                    truncated = true
                    break
                }
                if segLen > 0 {
                    currentPacket.append(contentsOf: bytes[cursor..<(cursor + segLen)])
                    cursor += segLen
                }

                // A lacing value < 255 terminates the current logical packet.
                if segLen < 255 {
                    let completed = currentPacket
                    currentPacket = Data()

                    if opusHead == nil {
                        opusHead = try parseOpusHead(completed)
                    } else if !skippedTags && hasPrefixASCII(completed, "OpusTags") {
                        skippedTags = true
                    } else if !completed.isEmpty {
                        let frames = opusPacketFrameCount48k(completed)
                        packets.append(OpusPacket(data: completed, frameCount48k: frames))
                    }
                }
            }

            if truncated { break }
            offset = cursor
        }

        guard let head = opusHead else {
            throw ConversionError.missingOpusHeader
        }
        guard !packets.isEmpty else {
            throw ConversionError.emptyAudioStream
        }

        return (head, packets, lastValidGranule)
    }

    private static func parseOpusHead(_ packet: Data) throws -> OpusHead {
        guard packet.count >= 19, hasPrefixASCII(packet, "OpusHead") else {
            throw ConversionError.missingOpusHeader
        }
        let base = packet.startIndex
        let channels = packet[base + 9]
        guard channels == 1 || channels == 2 else {
            throw ConversionError.unsupportedChannelCount(channels)
        }
        let preSkip = UInt16(packet[base + 10]) | (UInt16(packet[base + 11]) << 8)
        return OpusHead(channels: channels, preSkip: preSkip)
    }

    /// Computes total 48 kHz samples decoded by a single Opus packet per RFC 6716 Section 3.1.
    private static func opusPacketFrameCount48k(_ packet: Data) -> Int {
        guard !packet.isEmpty else { return 960 }
        let base = packet.startIndex
        let toc = packet[base]
        let config = Int(toc >> 3)

        let samplesPerFrame: Int
        switch config {
        case 0..<12:
            // SILK-only: 10, 20, 40, 60 ms
            let table = [480, 960, 1920, 2880]
            samplesPerFrame = table[config & 3]
        case 12..<16:
            // Hybrid: 10, 20 ms
            samplesPerFrame = (config & 1) == 0 ? 480 : 960
        default:
            // CELT-only: 2.5, 5, 10, 20 ms
            let table = [120, 240, 480, 960]
            samplesPerFrame = table[config & 3]
        }

        let code = Int(toc & 3)
        let frameCount: Int
        switch code {
        case 0:
            frameCount = 1
        case 1, 2:
            frameCount = 2
        default:
            if packet.count >= 2 {
                frameCount = max(1, Int(packet[base + 1] & 0x3F))
            } else {
                frameCount = 1
            }
        }

        return samplesPerFrame * frameCount
    }

    // MARK: - Apple CAF Muxer (Core Audio Format Specification 1.0)

    private static func buildCAF(head: OpusHead, packets: [OpusPacket], finalGranule: UInt64) -> Data {
        let firstFrameCount = packets[0].frameCount48k
        let hasConstantFrameCount = packets.allSatisfy { $0.frameCount48k == firstFrameCount }
        let totalDecodedFrames = packets.reduce(Int64(0)) { $0 + Int64($1.frameCount48k) }
        let totalAudioBytes = packets.reduce(0) { $0 + $1.data.count }

        let primingFrames: Int64 = min(Int64(head.preSkip), max(0, totalDecodedFrames - 1))
        let remainderFrames: Int64
        if finalGranule > 0,
           let granuleInt64 = Int64(exactly: finalGranule),
           granuleInt64 <= totalDecodedFrames,
           granuleInt64 > primingFrames
        {
            remainderFrames = totalDecodedFrames - granuleInt64
        } else {
            remainderFrames = 0
        }
        let validFrames = max(1, totalDecodedFrames - primingFrames - remainderFrames)

        var caf = Data()
        caf.reserveCapacity(128 + totalAudioBytes + packets.count * 4)

        // 1. CAF File Header ('caff', version 1, flags 0)
        caf.appendASCII("caff")
        caf.appendBigEndian(UInt16(1))
        caf.appendBigEndian(UInt16(0))

        // 2. Audio Description Chunk ('desc', 32 bytes)
        caf.appendASCII("desc")
        caf.appendBigEndian(Int64(32))
        caf.appendBigEndian(Float64(48000.0).bitPattern)          // mSampleRate
        caf.appendASCII("opus")                                   // mFormatID ('opus')
        caf.appendBigEndian(UInt32(0))                            // mFormatFlags
        caf.appendBigEndian(UInt32(0))                            // mBytesPerPacket (VBR)
        caf.appendBigEndian(UInt32(hasConstantFrameCount ? firstFrameCount : 0)) // mFramesPerPacket
        caf.appendBigEndian(UInt32(head.channels))                // mChannelsPerFrame
        caf.appendBigEndian(UInt32(0))                            // mBitsPerChannel

        // 3. Channel Layout Chunk ('chan', 12 bytes)
        let layoutTag: UInt32 = head.channels == 2
            ? ((101 << 16) | 2)  // kAudioChannelLayoutTag_Stereo
            : ((100 << 16) | 1)  // kAudioChannelLayoutTag_Mono
        caf.appendASCII("chan")
        caf.appendBigEndian(Int64(12))
        caf.appendBigEndian(layoutTag)
        caf.appendBigEndian(UInt32(0))
        caf.appendBigEndian(UInt32(0))

        // 4. Audio Data Chunk ('data', 4 + audioBytes)
        caf.appendASCII("data")
        caf.appendBigEndian(Int64(4 + totalAudioBytes))
        caf.appendBigEndian(UInt32(0)) // mEditCount
        for packet in packets {
            caf.append(packet.data)
        }

        // 5. Packet Table Chunk ('pakt', 24 + varint entries)
        var entries = Data()
        entries.reserveCapacity(packets.count * (hasConstantFrameCount ? 2 : 4))
        for packet in packets {
            appendCAFVarInt(UInt64(packet.data.count), to: &entries)
            if !hasConstantFrameCount {
                appendCAFVarInt(UInt64(packet.frameCount48k), to: &entries)
            }
        }

        caf.appendASCII("pakt")
        caf.appendBigEndian(Int64(24 + entries.count))
        caf.appendBigEndian(Int64(packets.count))      // mNumberPackets
        caf.appendBigEndian(validFrames)               // mNumberValidFrames
        caf.appendBigEndian(Int32(primingFrames))      // mPrimingFrames
        caf.appendBigEndian(Int32(remainderFrames))    // mRemainderFrames
        caf.append(entries)

        return caf
    }

    // MARK: - Binary Helpers

    private static func readUInt64LE(_ bytes: [UInt8], at index: Int) -> UInt64 {
        var result: UInt64 = 0
        for i in 0..<8 {
            result |= UInt64(bytes[index + i]) << (UInt64(i) * 8)
        }
        return result
    }

    private static func hasPrefixASCII(_ data: Data, _ ascii: String) -> Bool {
        let prefixBytes = Array(ascii.utf8)
        guard data.count >= prefixBytes.count else { return false }
        for (idx, expected) in prefixBytes.enumerated() {
            if data[data.startIndex + idx] != expected {
                return false
            }
        }
        return true
    }

    private static func appendCAFVarInt(_ value: UInt64, to data: inout Data) {
        var encoded: [UInt8] = [UInt8(value & 0x7F)]
        var remaining = value >> 7
        while remaining > 0 {
            encoded.append(UInt8((remaining & 0x7F) | 0x80))
            remaining >>= 7
        }
        encoded.reverse()
        data.append(contentsOf: encoded)
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        var big = value.bigEndian
        Swift.withUnsafeBytes(of: &big) { buffer in
            append(contentsOf: buffer)
        }
    }
}
