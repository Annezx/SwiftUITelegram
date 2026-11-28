import Compression
import Foundation
import Lottie

/// Decompresses Telegram `.tgs` files (RFC 1952 gzip-compressed Lottie JSON) into raw UTF-8 JSON data
/// using Apple's native `Compression` framework (`COMPRESSION_ZLIB` raw DEFLATE stream decoder).
/// Also gracefully handles RFC 1950 zlib-wrapped payloads and already-uncompressed JSON payloads.
enum TGSDecompressor {
    /// Hard ceiling (16 MB) to guard against malformed or adversarial compressed payloads.
    private static let maxDecompressedBytes = 16 * 1024 * 1024
    private static let chunkSize = 32 * 1024

    static func decompress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }

        // Pass through uncompressed Lottie JSON directly if already plain JSON.
        if let firstNonWhitespace = data.first(where: { $0 != 0x20 && $0 != 0x09 && $0 != 0x0A && $0 != 0x0D }),
           firstNonWhitespace == 0x7B /* '{' */
        {
            return data
        }

        let bytes = [UInt8](data)
        guard let payloadRange = rawDeflatePayloadRange(in: bytes), !payloadRange.isEmpty else {
            return nil
        }

        return inflateRawDeflate(bytes: bytes, range: payloadRange)
    }

    /// Parses an RFC 1952 gzip header (or RFC 1950 zlib header) and returns the byte range
    /// of the underlying RFC 1951 raw DEFLATE stream expected by `COMPRESSION_ZLIB`.
    private static func rawDeflatePayloadRange(in bytes: [UInt8]) -> Range<Int>? {
        // RFC 1952 GZIP format (standard for all Telegram `.tgs` stickers).
        if bytes.count >= 18, bytes[0] == 0x1F, bytes[1] == 0x8B {
            guard bytes[2] == 0x08 else { return nil } // Must be DEFLATE compression method
            let flags = bytes[3]
            var offset = 10 // Fixed 10-byte gzip header

            // FEXTRA (bit 2)
            if (flags & 0x04) != 0 {
                guard offset + 2 <= bytes.count else { return nil }
                let extraLen = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
                offset += 2 + extraLen
                guard offset <= bytes.count else { return nil }
            }

            // FNAME (bit 3) — zero-terminated original filename
            if (flags & 0x08) != 0 {
                while offset < bytes.count && bytes[offset] != 0 {
                    offset += 1
                }
                guard offset < bytes.count else { return nil }
                offset += 1 // Skip null terminator
            }

            // FCOMMENT (bit 4) — zero-terminated file comment
            if (flags & 0x10) != 0 {
                while offset < bytes.count && bytes[offset] != 0 {
                    offset += 1
                }
                guard offset < bytes.count else { return nil }
                offset += 1 // Skip null terminator
            }

            // FHCRC (bit 1) — 2-byte header CRC16
            if (flags & 0x02) != 0 {
                offset += 2
                guard offset <= bytes.count else { return nil }
            }

            // Gzip ends with an 8-byte trailer (CRC32 + ISIZE).
            let end = bytes.count - 8
            guard offset < end else { return nil }
            return offset..<end
        }

        // RFC 1950 ZLIB wrapper fallback (2-byte CMF/FLG header + 4-byte Adler-32 trailer).
        if bytes.count >= 6 {
            let cmf = bytes[0]
            let flg = bytes[1]
            let isDeflate = (cmf & 0x0F) == 8 && (cmf >> 4) <= 7
            let headerCheckValid = ((Int(cmf) << 8) | Int(flg)) % 31 == 0
            if isDeflate && headerCheckValid {
                let hasPresetDict = (flg & 0x20) != 0
                let start = hasPresetDict ? 6 : 2
                let end = bytes.count - 4
                guard start < end else { return nil }
                return start..<end
            }
        }

        // Fallback: treat input as raw DEFLATE (RFC 1951).
        return 0..<bytes.count
    }

    private static func inflateRawDeflate(bytes: [UInt8], range: Range<Int>) -> Data? {
        let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPtr.deallocate() }

        let initStatus = compression_stream_init(streamPtr, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard initStatus != COMPRESSION_STATUS_ERROR else {
            return nil
        }
        defer { compression_stream_destroy(streamPtr) }

        let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { dstBuffer.deallocate() }

        var output = Data()
        output.reserveCapacity(min(range.count * 4, 256 * 1024))

        var succeeded = false
        let finalizeFlag = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)

        bytes.withUnsafeBufferPointer { srcBuf in
            guard let basePtr = srcBuf.baseAddress else { return }
            streamPtr.pointee.src_ptr = basePtr.advanced(by: range.lowerBound)
            streamPtr.pointee.src_size = range.count

            while true {
                streamPtr.pointee.dst_ptr = dstBuffer
                streamPtr.pointee.dst_size = chunkSize

                let status = compression_stream_process(streamPtr, finalizeFlag)
                let produced = chunkSize - streamPtr.pointee.dst_size
                if produced > 0 {
                    if output.count + produced > maxDecompressedBytes {
                        return
                    }
                    output.append(dstBuffer, count: produced)
                }

                switch status {
                case COMPRESSION_STATUS_END:
                    succeeded = true
                    return
                case COMPRESSION_STATUS_OK:
                    if produced == 0 && streamPtr.pointee.src_size == 0 {
                        return
                    }
                default:
                    return
                }
            }
        }

        guard succeeded, !output.isEmpty else { return nil }
        return output
    }

    static func decodeAnimation(fromFilePath path: String) -> LottieAnimation? {
        let url = URL(fileURLWithPath: path)
        guard let rawData = try? Data(contentsOf: url, options: .mappedIfSafe),
              let jsonData = decompress(rawData)
        else {
            return nil
        }

        if let animation = try? LottieAnimation.from(data: jsonData, strategy: .dictionaryBased) {
            return animation
        }
        return try? LottieAnimation.from(data: jsonData, strategy: .legacyCodable)
    }
}

/// Process-wide cache and background loader for decoded TGS `LottieAnimation` instances.
/// Deduplicates concurrent decode requests for the same local file path.
@MainActor
final class TGSStickerCache {
    static let shared = TGSStickerCache()

    private let cache = NSCache<NSString, LottieAnimation>()
    private var inFlightTasks: [String: Task<LottieAnimation?, Never>] = [:]

    private init() {
        cache.countLimit = 140
    }

    func cachedAnimation(for path: String) -> LottieAnimation? {
        cache.object(forKey: path as NSString)
    }

    func loadAnimation(from path: String) async -> LottieAnimation? {
        guard !path.isEmpty else { return nil }

        if let cached = cache.object(forKey: path as NSString) {
            return cached
        }

        if let existing = inFlightTasks[path] {
            return await existing.value
        }

        let task = Task.detached(priority: .userInitiated) { () -> LottieAnimation? in
            TGSDecompressor.decodeAnimation(fromFilePath: path)
        }
        inFlightTasks[path] = task

        let decoded = await task.value
        inFlightTasks.removeValue(forKey: path)

        if let decoded {
            cache.setObject(decoded, forKey: path as NSString)
        }
        return decoded
    }

    func clear() {
        cache.removeAllObjects()
    }
}
