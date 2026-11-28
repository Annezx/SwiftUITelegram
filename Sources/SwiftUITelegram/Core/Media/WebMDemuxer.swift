import Foundation

/// Parsed container-level color metadata from Matroska `Tracks -> TrackEntry -> Video -> Colour`.
struct WebMColorMetadata: Sendable {
    var matrixCoefficients: UInt8?
    var bitsPerChannel: UInt8?
    var chromaSubsamplingHorz: UInt8?
    var chromaSubsamplingVert: UInt8?
    var range: UInt8? // 1 = video/broadcast, 2 = full
    var transferCharacteristics: UInt8?
    var primaries: UInt8?
}

/// Metadata describing the primary video track of a WebM sticker file.
struct WebMVideoTrackInfo: Sendable {
    let trackNumber: UInt64
    let codecID: String
    let pixelWidth: Int
    let pixelHeight: Int
    let displayWidth: Int
    let displayHeight: Int
    let hasAlphaMode: Bool
    let defaultDurationSeconds: TimeInterval?
    let color: WebMColorMetadata
}

/// A single demuxed video packet from a WebM container, optionally paired with its
/// Matroska `BlockAdditional` (BlockAddID = 1) alpha-channel frame.
struct WebMVideoPacket: Sendable {
    let ptsSeconds: TimeInterval
    var durationSeconds: TimeInterval
    let isKeyframe: Bool
    let data: Data
    let alphaData: Data?
}

/// Complete demuxed representation of a WebM video sticker.
struct WebMDemuxedClip: Sendable {
    let track: WebMVideoTrackInfo
    let durationSeconds: TimeInterval
    let packets: [WebMVideoPacket]

    var hasAlphaStream: Bool {
        track.hasAlphaMode || packets.contains(where: { $0.alphaData != nil })
    }
}

/// Zero-dependency pure-Swift EBML/Matroska demuxer focused on Telegram WebM video stickers
/// (VP9/VP8 video tracks with optional Matroska `BlockAdditions` alpha channel).
enum WebMDemuxer {
    private enum ElementID {
        static let ebml: UInt32 = 0x1A45DFA3
        static let segment: UInt32 = 0x18538067
        static let seekHead: UInt32 = 0x114D9B74
        static let info: UInt32 = 0x1549A966
        static let timestampScale: UInt32 = 0x2AD7B1
        static let duration: UInt32 = 0x4489
        static let tracks: UInt32 = 0x1654AE6B
        static let trackEntry: UInt32 = 0xAE
        static let trackNumber: UInt32 = 0xD7
        static let trackType: UInt32 = 0x83
        static let codecID: UInt32 = 0x86
        static let defaultDuration: UInt32 = 0x23E383
        static let video: UInt32 = 0xE0
        static let pixelWidth: UInt32 = 0xB0
        static let pixelHeight: UInt32 = 0xBA
        static let displayWidth: UInt32 = 0x54B0
        static let displayHeight: UInt32 = 0x54BA
        static let alphaMode: UInt32 = 0x53C0
        static let colour: UInt32 = 0x55B0
        static let matrixCoefficients: UInt32 = 0x55B1
        static let bitsPerChannel: UInt32 = 0x55B2
        static let chromaSubsamplingHorz: UInt32 = 0x55B3
        static let chromaSubsamplingVert: UInt32 = 0x55B4
        static let colourRange: UInt32 = 0x55B9
        static let transferCharacteristics: UInt32 = 0x55BA
        static let primaries: UInt32 = 0x55BB
        static let cluster: UInt32 = 0x1F43B675
        static let clusterTimestamp: UInt32 = 0xE7
        static let simpleBlock: UInt32 = 0xA3
        static let blockGroup: UInt32 = 0xA0
        static let block: UInt32 = 0xA1
        static let blockDuration: UInt32 = 0x9B
        static let blockAdditions: UInt32 = 0x75A1
        static let blockMore: UInt32 = 0xA6
        static let blockAddID: UInt32 = 0xEE
        static let blockAdditional: UInt32 = 0xA5
        static let cues: UInt32 = 0x1C53BB6B
        static let tags: UInt32 = 0x1254C367
        static let chapters: UInt32 = 0x1043A770
        static let attachments: UInt32 = 0x1941A469

        static func isTopLevelSegmentChild(_ id: UInt32) -> Bool {
            switch id {
            case ebml, segment, seekHead, info, tracks, cluster, cues, tags, chapters, attachments:
                return true
            default:
                return false
            }
        }
    }

    static func demux(data: Data) -> WebMDemuxedClip? {
        guard data.count >= 16 else { return nil }

        let bytes = [UInt8](data)
        var reader = ByteReader(bytes: bytes, end: bytes.count)

        // Locate Segment (skipping EBML header or any leading Void elements).
        var segmentEnd = bytes.count
        var foundSegment = false

        while reader.offset < bytes.count {
            guard let header = reader.readElementHeader() else { break }
            if header.id == ElementID.segment {
                foundSegment = true
                if let size = header.size {
                    segmentEnd = min(bytes.count, reader.offset + size)
                } else {
                    segmentEnd = bytes.count
                }
                break
            } else if let size = header.size {
                reader.skip(size)
            } else {
                break
            }
        }

        guard foundSegment else { return nil }

        var timestampScaleNs: UInt64 = 1_000_000 // Matroska default: 1ms per tick
        var rawDurationTicks: Double?
        var videoTrack: WebMVideoTrackInfo?
        var rawPackets: [RawClusterPacket] = []

        while reader.offset < segmentEnd {
            let elemStart = reader.offset
            guard let header = reader.readElementHeader() else { break }
            let bodyStart = reader.offset
            let bodyEnd: Int
            if let size = header.size {
                bodyEnd = min(segmentEnd, bodyStart + size)
            } else {
                bodyEnd = segmentEnd
            }

            switch header.id {
            case ElementID.info:
                parseInfo(bytes: bytes, start: bodyStart, end: bodyEnd, timestampScaleNs: &timestampScaleNs, durationTicks: &rawDurationTicks)
                reader.offset = bodyEnd

            case ElementID.tracks:
                if let parsed = parseTracks(bytes: bytes, start: bodyStart, end: bodyEnd) {
                    videoTrack = parsed
                }
                reader.offset = bodyEnd

            case ElementID.cluster:
                let nextOffset = parseCluster(
                    bytes: bytes,
                    start: bodyStart,
                    end: bodyEnd,
                    isUnknownSize: header.size == nil,
                    videoTrackNumber: videoTrack?.trackNumber,
                    packets: &rawPackets
                )
                reader.offset = max(nextOffset, elemStart + 1)

            default:
                if header.size != nil {
                    reader.offset = bodyEnd
                } else {
                    // Unknown-size non-master element cannot be skipped safely.
                    reader.offset = segmentEnd
                }
            }
        }

        guard let track = videoTrack, !rawPackets.isEmpty else {
            return nil
        }

        // Filter packets to the resolved video track in case Cluster appeared before Tracks.
        let filtered = rawPackets.filter { $0.trackNumber == track.trackNumber }
        guard !filtered.isEmpty else { return nil }

        let tickSeconds = Double(timestampScaleNs) / 1_000_000_000.0
        let fallbackFrameDuration = track.defaultDurationSeconds ?? (1.0 / 30.0)

        var packets: [WebMVideoPacket] = []
        packets.reserveCapacity(filtered.count)

        for raw in filtered {
            let pts = max(0, Double(raw.timestampTicks) * tickSeconds)
            let explicitDur = raw.durationTicks.map { Double($0) * tickSeconds }
            packets.append(
                WebMVideoPacket(
                    ptsSeconds: pts,
                    durationSeconds: explicitDur ?? 0,
                    isKeyframe: raw.isKeyframe,
                    data: raw.data,
                    alphaData: raw.alphaData
                )
            )
        }

        // Fill in per-frame durations from adjacent PTS deltas when BlockDuration was omitted.
        for index in packets.indices {
            if packets[index].durationSeconds <= 0.001 {
                if index + 1 < packets.count {
                    let delta = packets[index + 1].ptsSeconds - packets[index].ptsSeconds
                    if delta > 0.004 && delta < 2.0 {
                        packets[index].durationSeconds = delta
                    } else {
                        packets[index].durationSeconds = fallbackFrameDuration
                    }
                } else {
                    let prevDur = index > 0 ? packets[index - 1].durationSeconds : fallbackFrameDuration
                    packets[index].durationSeconds = prevDur > 0.004 ? prevDur : fallbackFrameDuration
                }
            }
        }

        let totalDuration: TimeInterval
        if let rawDurationTicks, rawDurationTicks > 0 {
            totalDuration = rawDurationTicks * tickSeconds
        } else if let last = packets.last {
            totalDuration = last.ptsSeconds + last.durationSeconds
        } else {
            totalDuration = fallbackFrameDuration
        }

        return WebMDemuxedClip(
            track: track,
            durationSeconds: max(totalDuration, fallbackFrameDuration),
            packets: packets
        )
    }

    // MARK: - Section Parsers

    private struct RawClusterPacket {
        let trackNumber: UInt64
        let timestampTicks: Int64
        let durationTicks: UInt64?
        let isKeyframe: Bool
        let data: Data
        let alphaData: Data?
    }

    private static func parseInfo(
        bytes: [UInt8],
        start: Int,
        end: Int,
        timestampScaleNs: inout UInt64,
        durationTicks: inout Double?
    ) {
        var reader = ByteReader(bytes: bytes, end: end, offset: start)
        while reader.offset < end {
            guard let header = reader.readElementHeader(), let size = header.size else { break }
            let elemEnd = min(end, reader.offset + size)
            switch header.id {
            case ElementID.timestampScale:
                let val = reader.readUInt(length: elemEnd - reader.offset)
                if val > 0 { timestampScaleNs = val }
            case ElementID.duration:
                durationTicks = reader.readFloat(length: elemEnd - reader.offset)
            default:
                break
            }
            reader.offset = elemEnd
        }
    }

    private static func parseTracks(bytes: [UInt8], start: Int, end: Int) -> WebMVideoTrackInfo? {
        var reader = ByteReader(bytes: bytes, end: end, offset: start)
        while reader.offset < end {
            guard let header = reader.readElementHeader(), let size = header.size else { break }
            let elemEnd = min(end, reader.offset + size)
            if header.id == ElementID.trackEntry {
                if let videoTrack = parseTrackEntry(bytes: bytes, start: reader.offset, end: elemEnd) {
                    return videoTrack
                }
            }
            reader.offset = elemEnd
        }
        return nil
    }

    private static func parseTrackEntry(bytes: [UInt8], start: Int, end: Int) -> WebMVideoTrackInfo? {
        var reader = ByteReader(bytes: bytes, end: end, offset: start)
        var trackNumber: UInt64 = 0
        var trackType: UInt64 = 0
        var codecID = ""
        var defaultDurationNs: UInt64?
        var pixelWidth = 0
        var pixelHeight = 0
        var displayWidth = 0
        var displayHeight = 0
        var alphaMode: UInt64 = 0
        var color = WebMColorMetadata()

        while reader.offset < end {
            guard let header = reader.readElementHeader(), let size = header.size else { break }
            let elemEnd = min(end, reader.offset + size)
            let len = elemEnd - reader.offset

            switch header.id {
            case ElementID.trackNumber:
                trackNumber = reader.readUInt(length: len)
            case ElementID.trackType:
                trackType = reader.readUInt(length: len)
            case ElementID.codecID:
                codecID = reader.readUTF8String(length: len)
            case ElementID.defaultDuration:
                defaultDurationNs = reader.readUInt(length: len)
            case ElementID.video:
                parseVideoTrackSettings(
                    bytes: bytes,
                    start: reader.offset,
                    end: elemEnd,
                    pixelWidth: &pixelWidth,
                    pixelHeight: &pixelHeight,
                    displayWidth: &displayWidth,
                    displayHeight: &displayHeight,
                    alphaMode: &alphaMode,
                    color: &color
                )
            default:
                break
            }
            reader.offset = elemEnd
        }

        // TrackType 1 = video.
        guard trackType == 1, trackNumber > 0 else { return nil }
        return WebMVideoTrackInfo(
            trackNumber: trackNumber,
            codecID: codecID,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            displayWidth: displayWidth > 0 ? displayWidth : pixelWidth,
            displayHeight: displayHeight > 0 ? displayHeight : pixelHeight,
            hasAlphaMode: alphaMode == 1,
            defaultDurationSeconds: defaultDurationNs.flatMap { $0 > 0 ? Double($0) / 1_000_000_000.0 : nil },
            color: color
        )
    }

    private static func parseVideoTrackSettings(
        bytes: [UInt8],
        start: Int,
        end: Int,
        pixelWidth: inout Int,
        pixelHeight: inout Int,
        displayWidth: inout Int,
        displayHeight: inout Int,
        alphaMode: inout UInt64,
        color: inout WebMColorMetadata
    ) {
        var reader = ByteReader(bytes: bytes, end: end, offset: start)
        while reader.offset < end {
            guard let header = reader.readElementHeader(), let size = header.size else { break }
            let elemEnd = min(end, reader.offset + size)
            let len = elemEnd - reader.offset

            switch header.id {
            case ElementID.pixelWidth:
                pixelWidth = Int(reader.readUInt(length: len))
            case ElementID.pixelHeight:
                pixelHeight = Int(reader.readUInt(length: len))
            case ElementID.displayWidth:
                displayWidth = Int(reader.readUInt(length: len))
            case ElementID.displayHeight:
                displayHeight = Int(reader.readUInt(length: len))
            case ElementID.alphaMode:
                alphaMode = reader.readUInt(length: len)
            case ElementID.colour:
                parseColourElement(bytes: bytes, start: reader.offset, end: elemEnd, color: &color)
            default:
                break
            }
            reader.offset = elemEnd
        }
    }

    private static func parseColourElement(
        bytes: [UInt8],
        start: Int,
        end: Int,
        color: inout WebMColorMetadata
    ) {
        var reader = ByteReader(bytes: bytes, end: end, offset: start)
        while reader.offset < end {
            guard let header = reader.readElementHeader(), let size = header.size else { break }
            let elemEnd = min(end, reader.offset + size)
            let val = UInt8(clamping: reader.readUInt(length: elemEnd - reader.offset))

            switch header.id {
            case ElementID.matrixCoefficients:
                color.matrixCoefficients = val
            case ElementID.bitsPerChannel:
                color.bitsPerChannel = val
            case ElementID.chromaSubsamplingHorz:
                color.chromaSubsamplingHorz = val
            case ElementID.chromaSubsamplingVert:
                color.chromaSubsamplingVert = val
            case ElementID.colourRange:
                color.range = val
            case ElementID.transferCharacteristics:
                color.transferCharacteristics = val
            case ElementID.primaries:
                color.primaries = val
            default:
                break
            }
            reader.offset = elemEnd
        }
    }

    private static func parseCluster(
        bytes: [UInt8],
        start: Int,
        end: Int,
        isUnknownSize: Bool,
        videoTrackNumber: UInt64?,
        packets: inout [RawClusterPacket]
    ) -> Int {
        var reader = ByteReader(bytes: bytes, end: end, offset: start)
        var clusterTimestamp: Int64 = 0

        while reader.offset < end {
            let elemStart = reader.offset
            guard let header = reader.readElementHeader() else { break }

            if isUnknownSize && ElementID.isTopLevelSegmentChild(header.id) {
                return elemStart
            }

            guard let size = header.size else { break }
            let elemEnd = min(end, reader.offset + size)

            switch header.id {
            case ElementID.clusterTimestamp:
                clusterTimestamp = Int64(bitPattern: reader.readUInt(length: elemEnd - reader.offset))

            case ElementID.simpleBlock:
                parseBlockPayload(
                    bytes: bytes,
                    start: reader.offset,
                    end: elemEnd,
                    clusterTimestamp: clusterTimestamp,
                    durationTicks: nil,
                    alphaData: nil,
                    isSimpleBlock: true,
                    videoTrackNumber: videoTrackNumber,
                    packets: &packets
                )

            case ElementID.blockGroup:
                parseBlockGroup(
                    bytes: bytes,
                    start: reader.offset,
                    end: elemEnd,
                    clusterTimestamp: clusterTimestamp,
                    videoTrackNumber: videoTrackNumber,
                    packets: &packets
                )

            default:
                break
            }

            reader.offset = elemEnd
        }

        return reader.offset
    }

    private static func parseBlockGroup(
        bytes: [UInt8],
        start: Int,
        end: Int,
        clusterTimestamp: Int64,
        videoTrackNumber: UInt64?,
        packets: inout [RawClusterPacket]
    ) {
        var reader = ByteReader(bytes: bytes, end: end, offset: start)
        var blockRange: Range<Int>?
        var durationTicks: UInt64?
        var alphaData: Data?

        while reader.offset < end {
            guard let header = reader.readElementHeader(), let size = header.size else { break }
            let elemEnd = min(end, reader.offset + size)

            switch header.id {
            case ElementID.block:
                blockRange = reader.offset..<elemEnd
            case ElementID.blockDuration:
                durationTicks = reader.readUInt(length: elemEnd - reader.offset)
            case ElementID.blockAdditions:
                if let extractedAlpha = parseBlockAdditions(bytes: bytes, start: reader.offset, end: elemEnd) {
                    alphaData = extractedAlpha
                }
            default:
                break
            }

            reader.offset = elemEnd
        }

        if let range = blockRange {
            parseBlockPayload(
                bytes: bytes,
                start: range.lowerBound,
                end: range.upperBound,
                clusterTimestamp: clusterTimestamp,
                durationTicks: durationTicks,
                alphaData: alphaData,
                isSimpleBlock: false,
                videoTrackNumber: videoTrackNumber,
                packets: &packets
            )
        }
    }

    private static func parseBlockAdditions(bytes: [UInt8], start: Int, end: Int) -> Data? {
        var reader = ByteReader(bytes: bytes, end: end, offset: start)
        while reader.offset < end {
            guard let header = reader.readElementHeader(), let size = header.size else { break }
            let elemEnd = min(end, reader.offset + size)
            if header.id == ElementID.blockMore {
                if let alpha = parseBlockMore(bytes: bytes, start: reader.offset, end: elemEnd) {
                    return alpha
                }
            }
            reader.offset = elemEnd
        }
        return nil
    }

    private static func parseBlockMore(bytes: [UInt8], start: Int, end: Int) -> Data? {
        var reader = ByteReader(bytes: bytes, end: end, offset: start)
        // Per Matroska spec, BlockAddID defaults to 1 (alpha channel) when omitted.
        var blockAddID: UInt64 = 1
        var payloadRange: Range<Int>?

        while reader.offset < end {
            guard let header = reader.readElementHeader(), let size = header.size else { break }
            let elemEnd = min(end, reader.offset + size)
            switch header.id {
            case ElementID.blockAddID:
                blockAddID = reader.readUInt(length: elemEnd - reader.offset)
            case ElementID.blockAdditional:
                payloadRange = reader.offset..<elemEnd
            default:
                break
            }
            reader.offset = elemEnd
        }

        guard blockAddID == 1, let range = payloadRange, !range.isEmpty else {
            return nil
        }
        return Data(bytes[range])
    }

    private static func parseBlockPayload(
        bytes: [UInt8],
        start: Int,
        end: Int,
        clusterTimestamp: Int64,
        durationTicks: UInt64?,
        alphaData: Data?,
        isSimpleBlock: Bool,
        videoTrackNumber: UInt64?,
        packets: inout [RawClusterPacket]
    ) {
        var reader = ByteReader(bytes: bytes, end: end, offset: start)
        guard let trackNum = reader.readVIntValue() else { return }
        if let expected = videoTrackNumber, trackNum != expected {
            return
        }
        guard reader.offset + 3 <= end else { return }

        let relHi = UInt16(bytes[reader.offset])
        let relLo = UInt16(bytes[reader.offset + 1])
        let relativeTimestamp = Int16(bitPattern: (relHi << 8) | relLo)
        let flags = bytes[reader.offset + 2]
        reader.offset += 3

        let lacing = (flags >> 1) & 0x03
        let isKeyframe = isSimpleBlock ? ((flags & 0x80) != 0) : false
        let ptsTicks = clusterTimestamp + Int64(relativeTimestamp)

        guard reader.offset < end else { return }

        if lacing == 0 {
            let frameData = Data(bytes[reader.offset..<end])
            packets.append(
                RawClusterPacket(
                    trackNumber: trackNum,
                    timestampTicks: ptsTicks,
                    durationTicks: durationTicks,
                    isKeyframe: isKeyframe,
                    data: frameData,
                    alphaData: alphaData
                )
            )
            return
        }

        // Handle rare laced blocks (Xiph = 1, Fixed = 2, EBML = 3).
        let frameCount = Int(bytes[reader.offset]) + 1
        reader.offset += 1
        guard frameCount > 0, reader.offset < end else { return }

        var frameSizes: [Int] = []
        switch lacing {
        case 1: // Xiph lacing
            var sum = 0
            for _ in 0..<(frameCount - 1) {
                var size = 0
                while reader.offset < end {
                    let b = Int(bytes[reader.offset])
                    reader.offset += 1
                    size += b
                    if b != 255 { break }
                }
                frameSizes.append(size)
                sum += size
            }
            let remaining = (end - reader.offset) - sum
            guard remaining >= 0 else { return }
            frameSizes.append(remaining)

        case 2: // Fixed-size lacing
            let total = end - reader.offset
            guard total % frameCount == 0 else { return }
            let each = total / frameCount
            frameSizes = Array(repeating: each, count: frameCount)

        case 3: // EBML lacing
            guard let firstSizeU = reader.readVIntValue() else { return }
            var currentSize = Int(firstSizeU)
            frameSizes.append(currentSize)
            var sum = currentSize
            for _ in 1..<(frameCount - 1) {
                guard let delta = reader.readSignedVIntDelta() else { return }
                currentSize += delta
                guard currentSize >= 0 else { return }
                frameSizes.append(currentSize)
                sum += currentSize
            }
            let remaining = (end - reader.offset) - sum
            guard remaining >= 0 else { return }
            frameSizes.append(remaining)

        default:
            return
        }

        for (index, size) in frameSizes.enumerated() {
            guard size > 0, reader.offset + size <= end else { break }
            let frameData = Data(bytes[reader.offset..<(reader.offset + size)])
            reader.offset += size
            packets.append(
                RawClusterPacket(
                    trackNumber: trackNum,
                    timestampTicks: ptsTicks,
                    durationTicks: index == 0 ? durationTicks : nil,
                    isKeyframe: isKeyframe && index == 0,
                    data: frameData,
                    alphaData: index == 0 ? alphaData : nil
                )
            )
        }
    }

    // MARK: - Low-Level EBML Byte Reader

    private struct ElementHeader {
        let id: UInt32
        let size: Int? // nil = unknown / streaming size
    }

    private struct ByteReader {
        let bytes: [UInt8]
        let end: Int
        var offset: Int = 0

        mutating func readElementHeader() -> ElementHeader? {
            guard let id = readElementID(), let sizeOpt = readDataSize() else {
                return nil
            }
            return ElementHeader(id: id, size: sizeOpt)
        }

        mutating func readElementID() -> UInt32? {
            guard offset < end else { return nil }
            let first = bytes[offset]
            guard first != 0 else { return nil }
            let lz = first.leadingZeroBitCount
            let length = lz + 1
            guard length <= 4, offset + length <= end else { return nil }
            var value: UInt32 = 0
            for i in 0..<length {
                value = (value << 8) | UInt32(bytes[offset + i])
            }
            offset += length
            return value
        }

        mutating func readDataSize() -> Int?? {
            guard offset < end else { return nil }
            let first = bytes[offset]
            guard first != 0 else { return nil }
            let lz = first.leadingZeroBitCount
            let length = lz + 1
            guard length <= 8, offset + length <= end else { return nil }

            let firstMask: UInt8 = lz >= 7 ? 0 : (0xFF >> (lz + 1))
            var value = UInt64(first & firstMask)
            for i in 1..<length {
                value = (value << 8) | UInt64(bytes[offset + i])
            }
            offset += length

            let allOnes: UInt64 = (UInt64(1) << (7 * length)) - 1
            if value == allOnes {
                return .some(nil) // Unknown size
            }
            guard value <= UInt64(Int.max) else { return nil }
            return .some(Int(value))
        }

        mutating func readVIntValue() -> UInt64? {
            guard offset < end else { return nil }
            let first = bytes[offset]
            guard first != 0 else { return nil }
            let lz = first.leadingZeroBitCount
            let length = lz + 1
            guard length <= 8, offset + length <= end else { return nil }
            let firstMask: UInt8 = lz >= 7 ? 0 : (0xFF >> (lz + 1))
            var value = UInt64(first & firstMask)
            for i in 1..<length {
                value = (value << 8) | UInt64(bytes[offset + i])
            }
            offset += length
            return value
        }

        mutating func readSignedVIntDelta() -> Int? {
            guard offset < end else { return nil }
            let first = bytes[offset]
            guard first != 0 else { return nil }
            let lz = first.leadingZeroBitCount
            let length = lz + 1
            guard length <= 8, offset + length <= end else { return nil }
            let firstMask: UInt8 = lz >= 7 ? 0 : (0xFF >> (lz + 1))
            var raw = Int64(first & firstMask)
            for i in 1..<length {
                raw = (raw << 8) | Int64(bytes[offset + i])
            }
            offset += length
            let bias: Int64 = (Int64(1) << (7 * length - 1)) - 1
            return Int(raw - bias)
        }

        func readUInt(length: Int) -> UInt64 {
            let clamped = min(length, 8)
            var value: UInt64 = 0
            for i in 0..<clamped where offset + i < end {
                value = (value << 8) | UInt64(bytes[offset + i])
            }
            return value
        }

        func readFloat(length: Int) -> Double? {
            if length == 4, offset + 4 <= end {
                let bits = (UInt32(bytes[offset]) << 24)
                    | (UInt32(bytes[offset + 1]) << 16)
                    | (UInt32(bytes[offset + 2]) << 8)
                    | UInt32(bytes[offset + 3])
                return Double(Float(bitPattern: bits))
            }
            if length == 8, offset + 8 <= end {
                var bits: UInt64 = 0
                for i in 0..<8 {
                    bits = (bits << 8) | UInt64(bytes[offset + i])
                }
                return Double(bitPattern: bits)
            }
            return nil
        }

        func readUTF8String(length: Int) -> String {
            guard length > 0, offset + length <= end else { return "" }
            let slice = bytes[offset..<(offset + length)]
            return String(decoding: slice, as: UTF8.self)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        }

        mutating func skip(_ count: Int) {
            offset = min(end, offset + max(0, count))
        }
    }
}

// MARK: - VP9 Bitstream Header Parser & Superframe Packer

/// Minimal VP9 uncompressed header parameters needed to construct an accurate ISO `vpcC` atom
/// for Apple VideoToolbox (`kCMVideoCodecType_VP9`).
struct VP9StreamConfig: Sendable {
    let profile: UInt8
    let bitDepth: UInt8
    let chromaSubsampling: UInt8 // 0 = 4:2:0 vertical, 1 = 4:2:0 colocated, 2 = 4:2:2, 3 = 4:4:4
    let fullRange: Bool
    let colorPrimaries: UInt8
    let transferCharacteristics: UInt8
    let matrixCoefficients: UInt8
    let width: Int
    let height: Int

    /// Builds the 12-byte ISO/IEC `vpcC` box payload expected inside
    /// `kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms`.
    func makeVPCCData() -> Data {
        let fullRangeBit: UInt8 = fullRange ? 1 : 0
        let bitDepthAndSubsampling = (bitDepth << 4) | ((chromaSubsampling & 0x07) << 1) | fullRangeBit
        return Data([
            1, // version
            0, 0, 0, // flags
            profile,
            10, // level 1.0 (CoreMedia ignores level for VP9 decoding)
            bitDepthAndSubsampling,
            colorPrimaries,
            transferCharacteristics,
            matrixCoefficients,
            0, 0 // codecInitializationDataSize
        ])
    }
}

enum VP9BitstreamHelper {
    /// Parses the VP9 uncompressed header from a keyframe (or superframe whose first frame is a keyframe).
    static func parseConfig(
        fromKeyframe data: Data,
        fallbackWidth: Int,
        fallbackHeight: Int,
        containerColor: WebMColorMetadata? = nil
    ) -> VP9StreamConfig {
        let bytes = [UInt8](data)
        var reader = BitReader(bytes: bytes)

        var profile: UInt8 = 0
        var bitDepth: UInt8 = 8
        var chromaSubsampling: UInt8 = 1 // 4:2:0 colocated
        var fullRange = false
        var colorPrimaries: UInt8 = 2 // Unspecified
        var transferCharacteristics: UInt8 = 2
        var matrixCoefficients: UInt8 = 2
        var width = max(fallbackWidth, 1)
        var height = max(fallbackHeight, 1)

        if let marker = reader.readBits(2), marker == 0b10,
           let profileLow = reader.readBits(1),
           let profileHigh = reader.readBits(1)
        {
            profile = UInt8((profileHigh << 1) | profileLow)
            if profile == 3 {
                _ = reader.readBits(1) // reserved zero
            }
            let showExisting = reader.readBits(1) ?? 0
            if showExisting == 0,
               let frameType = reader.readBits(1), frameType == 0
            {
                _ = reader.readBits(1) // show_frame
                _ = reader.readBits(1) // error_resilient_mode

                // VP9 keyframe sync code: 0x49 0x83 0x42
                if let s0 = reader.readBits(8), s0 == 0x49,
                   let s1 = reader.readBits(8), s1 == 0x83,
                   let s2 = reader.readBits(8), s2 == 0x42
                {
                    if profile >= 2 {
                        let twelveBit = reader.readBits(1) ?? 0
                        bitDepth = twelveBit == 1 ? 12 : 10
                    } else {
                        bitDepth = 8
                    }

                    let cs = reader.readBits(3) ?? 0
                    switch cs {
                    case 1: // BT.601
                        colorPrimaries = 6; transferCharacteristics = 6; matrixCoefficients = 6
                    case 2: // BT.709
                        colorPrimaries = 1; transferCharacteristics = 1; matrixCoefficients = 1
                    case 3: // SMPTE-170
                        colorPrimaries = 6; transferCharacteristics = 6; matrixCoefficients = 6
                    case 4: // SMPTE-240
                        colorPrimaries = 7; transferCharacteristics = 7; matrixCoefficients = 7
                    case 5: // BT.2020
                        colorPrimaries = 9; transferCharacteristics = 14; matrixCoefficients = 9
                    case 7: // sRGB
                        colorPrimaries = 1; transferCharacteristics = 13; matrixCoefficients = 0
                    default:
                        break
                    }

                    if cs != 7 {
                        fullRange = (reader.readBits(1) ?? 0) == 1
                        if profile == 1 || profile == 3 {
                            let subX = reader.readBits(1) ?? 1
                            let subY = reader.readBits(1) ?? 1
                            _ = reader.readBits(1) // reserved zero
                            if subX == 0 && subY == 0 {
                                chromaSubsampling = 3 // 4:4:4
                            } else if subX == 1 && subY == 0 {
                                chromaSubsampling = 2 // 4:2:2
                            } else {
                                chromaSubsampling = 1 // 4:2:0
                            }
                        } else {
                            chromaSubsampling = 1
                        }
                    } else {
                        fullRange = true
                        chromaSubsampling = 3
                    }

                    if let wMinus1 = reader.readBits(16), let hMinus1 = reader.readBits(16) {
                        width = Int(wMinus1) + 1
                        height = Int(hMinus1) + 1
                    }
                }
            }
        }

        // Apply optional Matroska Colour container overrides (matches WebKit VP9UtilitiesCocoa).
        if let c = containerColor {
            if let bits = c.bitsPerChannel, bits == 8 || bits == 10 || bits == 12 {
                bitDepth = bits
            }
            if let range = c.range, range == 1 || range == 2 {
                fullRange = (range == 2)
            }
            if let p = c.primaries, p > 0 { colorPrimaries = p }
            if let t = c.transferCharacteristics, t > 0 { transferCharacteristics = t }
            if let m = c.matrixCoefficients, m > 0 { matrixCoefficients = m }
        }

        return VP9StreamConfig(
            profile: profile,
            bitDepth: bitDepth,
            chromaSubsampling: chromaSubsampling,
            fullRange: fullRange,
            colorPrimaries: colorPrimaries,
            transferCharacteristics: transferCharacteristics,
            matrixCoefficients: matrixCoefficients,
            width: width,
            height: height
        )
    }

    /// Returns true if `data` already carries a valid VP9 Annex-B superframe index footer.
    static func isSuperframe(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        let count = bytes.count
        guard count >= 4 else { return false }
        let marker = bytes[count - 1]
        guard (marker & 0xE0) == 0xC0 else { return false }

        let bytesPerSize = Int((marker >> 3) & 0x03) + 1
        let frameCount = Int(marker & 0x07) + 1
        let indexSize = 2 + frameCount * bytesPerSize
        guard count > indexSize else { return false }
        guard bytes[count - indexSize] == marker else { return false }

        var totalPayload = 0
        var pos = count - indexSize + 1
        for _ in 0..<frameCount {
            var size = 0
            for shift in 0..<bytesPerSize {
                size |= Int(bytes[pos + shift]) << (8 * shift)
            }
            pos += bytesPerSize
            totalPayload += size
        }
        return totalPayload == count - indexSize
    }

    /// Returns true if a non-superframe VP9 packet has `show_frame == 0` (invisible alt-ref frame).
    /// Intel macOS VideoToolbox requires invisible VP9 frames to be merged into superframes with
    /// their subsequent visible frame.
    static func isInvisibleSingleFrame(_ data: Data) -> Bool {
        guard !data.isEmpty, !isSuperframe(data) else { return false }
        let bytes = [UInt8](data.prefix(2))
        var reader = BitReader(bytes: bytes)
        guard let marker = reader.readBits(2), marker == 0b10,
              let profileLow = reader.readBits(1),
              let profileHigh = reader.readBits(1)
        else {
            return false
        }
        let profile = (profileHigh << 1) | profileLow
        if profile == 3 {
            _ = reader.readBits(1)
        }
        guard let showExisting = reader.readBits(1), showExisting == 0 else {
            return false
        }
        _ = reader.readBits(1) // frame_type
        guard let showFrame = reader.readBits(1) else {
            return false
        }
        return showFrame == 0
    }

    /// Merges one or more invisible VP9 frames plus a trailing visible frame into a valid
    /// VP9 Annex-B superframe.
    static func packSuperframe(frames: [Data]) -> Data {
        guard frames.count > 1 else { return frames.first ?? Data() }
        let count = min(frames.count, 8)
        let slice = Array(frames.prefix(count))
        let maxFrameSize = slice.map(\.count).max() ?? 0

        let bytesPerSize: Int
        if maxFrameSize <= 0xFF {
            bytesPerSize = 1
        } else if maxFrameSize <= 0xFFFF {
            bytesPerSize = 2
        } else if maxFrameSize <= 0xFF_FFFF {
            bytesPerSize = 3
        } else {
            bytesPerSize = 4
        }

        let marker: UInt8 = 0xC0 | UInt8((bytesPerSize - 1) << 3) | UInt8(count - 1)
        let totalPayload = slice.reduce(0) { $0 + $1.count }

        var result = Data()
        result.reserveCapacity(totalPayload + 2 + count * bytesPerSize)
        for frame in slice {
            result.append(frame)
        }
        result.append(marker)
        for frame in slice {
            var size = UInt32(frame.count)
            for _ in 0..<bytesPerSize {
                result.append(UInt8(size & 0xFF))
                size >>= 8
            }
        }
        result.append(marker)
        return result
    }

    private struct BitReader {
        let bytes: [UInt8]
        var bitOffset: Int = 0

        mutating func readBits(_ count: Int) -> UInt32? {
            guard count > 0, count <= 32, bitOffset + count <= bytes.count * 8 else {
                return nil
            }
            var value: UInt32 = 0
            for _ in 0..<count {
                let byteIndex = bitOffset >> 3
                let bitInByte = 7 - (bitOffset & 7)
                let bit = (bytes[byteIndex] >> bitInByte) & 1
                value = (value << 1) | UInt32(bit)
                bitOffset += 1
            }
            return value
        }
    }
}
