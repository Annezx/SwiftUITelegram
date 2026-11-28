import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// Single decoded frame of an animated WebM video sticker.
struct WebMStickerFrame: Sendable {
    let image: CGImage
    let duration: TimeInterval
}

/// Decoded frame sequence for a WebM video sticker, ready for `CALayer`-backed looping playback.
final class WebMStickerSequence: @unchecked Sendable {
    let frames: [WebMStickerFrame]
    let width: Int
    let height: Int
    let estimatedByteCost: Int

    init(frames: [WebMStickerFrame], width: Int, height: Int) {
        self.frames = frames
        self.width = width
        self.height = height
        let bytesPerFrame = max(width, 1) * max(height, 1) * 4
        self.estimatedByteCost = bytesPerFrame * max(frames.count, 1)
    }
}

/// Decodes Telegram `.webm` video stickers (VP9 + Matroska `BlockAdditional` alpha plane)
/// into premultiplied alpha `CGImage` frames using native macOS `VideoToolbox`.
enum WebMStickerDecoder {
    private static let registerVP9Once: Void = {
        VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_VP9)
    }()

    /// Hard cap on decoded frames per sticker (Telegram WebM stickers are ≤ 3s @ 30fps = 90 frames).
    private static let maxDecodedFrames = 180

    static func decodeSequence(
        fromFilePath path: String,
        maxPixelSize: Int = 256,
        firstFrameOnly: Bool = false
    ) -> WebMStickerSequence? {
        _ = registerVP9Once

        let url = URL(fileURLWithPath: path)
        guard let fileData = try? Data(contentsOf: url, options: .mappedIfSafe),
              let clip = WebMDemuxer.demux(data: fileData)
        else {
            return nil
        }

        // Apple VideoToolbox supplemental decoder supports VP9 (standard for all Telegram video stickers).
        guard clip.track.codecID.uppercased().contains("VP9") else {
            return nil
        }

        guard let firstColorPacket = clip.packets.first else {
            return nil
        }

        let colorConfig = VP9BitstreamHelper.parseConfig(
            fromKeyframe: firstColorPacket.data,
            fallbackWidth: clip.track.pixelWidth,
            fallbackHeight: clip.track.pixelHeight,
            containerColor: clip.track.color
        )

        guard let colorSession = VP9DecoderSession(
            config: colorConfig,
            pixelFormat: kCVPixelFormatType_32BGRA
        ) else {
            return nil
        }
        defer { colorSession.invalidate() }

        let hasAlpha = clip.hasAlphaStream
        var alphaSession: VP9DecoderSession?
        if hasAlpha, let firstAlphaData = clip.packets.first(where: { $0.alphaData != nil })?.alphaData {
            let alphaConfig = VP9BitstreamHelper.parseConfig(
                fromKeyframe: firstAlphaData,
                fallbackWidth: colorConfig.width,
                fallbackHeight: colorConfig.height,
                containerColor: nil
            )
            // Decode alpha into planar YUV (plane 0 = raw 8-bit luma alpha [0..255]) with BGRA fallback.
            alphaSession = VP9DecoderSession(
                config: alphaConfig,
                pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ) ?? VP9DecoderSession(
                config: alphaConfig,
                pixelFormat: kCVPixelFormatType_32BGRA
            )
        }
        defer { alphaSession?.invalidate() }

        var frames: [WebMStickerFrame] = []
        frames.reserveCapacity(firstFrameOnly ? 1 : min(clip.packets.count, maxDecodedFrames))

        var pendingColorInvisible: [Data] = []
        var pendingAlphaInvisible: [Data] = []

        for packet in clip.packets {
            if frames.count >= maxDecodedFrames {
                break
            }

            // Pack any unpacked invisible VP9 alt-ref frames into a superframe so Intel VideoToolbox
            // never stalls waiting for a visible display frame.
            let colorPayload: Data
            if VP9BitstreamHelper.isInvisibleSingleFrame(packet.data) {
                pendingColorInvisible.append(packet.data)
                if let alphaChunk = packet.alphaData, VP9BitstreamHelper.isInvisibleSingleFrame(alphaChunk) {
                    pendingAlphaInvisible.append(alphaChunk)
                }
                continue
            } else if !pendingColorInvisible.isEmpty {
                pendingColorInvisible.append(packet.data)
                colorPayload = VP9BitstreamHelper.packSuperframe(frames: pendingColorInvisible)
                pendingColorInvisible.removeAll(keepingCapacity: true)
            } else {
                colorPayload = packet.data
            }

            let alphaPayload: Data?
            if let alphaChunk = packet.alphaData {
                if VP9BitstreamHelper.isInvisibleSingleFrame(alphaChunk) {
                    pendingAlphaInvisible.append(alphaChunk)
                    alphaPayload = nil
                } else if !pendingAlphaInvisible.isEmpty {
                    pendingAlphaInvisible.append(alphaChunk)
                    alphaPayload = VP9BitstreamHelper.packSuperframe(frames: pendingAlphaInvisible)
                    pendingAlphaInvisible.removeAll(keepingCapacity: true)
                } else {
                    alphaPayload = alphaChunk
                }
            } else {
                alphaPayload = nil
            }

            let frameImage: CGImage? = autoreleasepool {
                guard let colorPixelBuffer = colorSession.decode(
                    packetData: colorPayload,
                    pts: packet.ptsSeconds,
                    duration: packet.durationSeconds
                ) else {
                    return nil
                }

                let alphaPixelBuffer: CVPixelBuffer?
                if let alphaSession, let alphaPayload {
                    alphaPixelBuffer = alphaSession.decode(
                        packetData: alphaPayload,
                        pts: packet.ptsSeconds,
                        duration: packet.durationSeconds
                    )
                } else {
                    alphaPixelBuffer = nil
                }

                return makeCompositedCGImage(
                    colorBuffer: colorPixelBuffer,
                    alphaBuffer: alphaPixelBuffer,
                    maxPixelSize: maxPixelSize
                )
            }

            if let cgImage = frameImage {
                let clampedDuration = min(max(packet.durationSeconds, 1.0 / 60.0), 0.5)
                frames.append(WebMStickerFrame(image: cgImage, duration: clampedDuration))
                if firstFrameOnly {
                    break
                }
            }
        }

        guard let firstImage = frames.first?.image else {
            return nil
        }

        return WebMStickerSequence(
            frames: frames,
            width: firstImage.width,
            height: firstImage.height
        )
    }

    // MARK: - VideoToolbox VP9 Session Wrapper

    private final class VP9DecoderSession {
        private let formatDescription: CMVideoFormatDescription
        private var session: VTDecompressionSession?

        init?(config: VP9StreamConfig, pixelFormat: OSType) {
            let cfTrue: CFBoolean = kCFBooleanTrue
            let cfFalse: CFBoolean = kCFBooleanFalse

            let vpccData = config.makeVPCCData()
            let atoms: [CFString: Any] = ["vpcC" as CFString: vpccData as CFData]
            let extensions: [CFString: Any] = [
                kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms: atoms as CFDictionary,
                kCMFormatDescriptionExtension_FullRangeVideo: config.fullRange ? cfTrue : cfFalse
            ]

            var desc: CMVideoFormatDescription?
            let descStatus = CMVideoFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                codecType: kCMVideoCodecType_VP9,
                width: Int32(max(config.width, 1)),
                height: Int32(max(config.height, 1)),
                extensions: extensions as CFDictionary,
                formatDescriptionOut: &desc
            )
            guard descStatus == noErr, let validDesc = desc else {
                return nil
            }
            self.formatDescription = validDesc

            let pixelAttrs: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: NSNumber(value: pixelFormat),
                kCVPixelBufferCGImageCompatibilityKey: cfTrue,
                kCVPixelBufferCGBitmapContextCompatibilityKey: cfTrue
            ]

            let hwDecoderSpec: [CFString: Any] = [
                kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: cfTrue
            ]

            var createdSession: VTDecompressionSession?
            var status = VTDecompressionSessionCreate(
                allocator: kCFAllocatorDefault,
                formatDescription: validDesc,
                decoderSpecification: hwDecoderSpec as CFDictionary,
                imageBufferAttributes: pixelAttrs as CFDictionary,
                outputCallback: nil,
                decompressionSessionOut: &createdSession
            )

            // Retry with default specification if explicit HW preference was declined.
            if status != noErr || createdSession == nil {
                status = VTDecompressionSessionCreate(
                    allocator: kCFAllocatorDefault,
                    formatDescription: validDesc,
                    decoderSpecification: nil,
                    imageBufferAttributes: pixelAttrs as CFDictionary,
                    outputCallback: nil,
                    decompressionSessionOut: &createdSession
                )
            }

            guard status == noErr, let validSession = createdSession else {
                return nil
            }
            self.session = validSession
        }

        func decode(packetData: Data, pts: TimeInterval, duration: TimeInterval) -> CVPixelBuffer? {
            guard let session, !packetData.isEmpty else { return nil }

            var blockBuffer: CMBlockBuffer?
            let blockStatus = CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: packetData.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: packetData.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
            guard blockStatus == kCMBlockBufferNoErr, let validBlock = blockBuffer else {
                return nil
            }

            let copyStatus: OSStatus = packetData.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return -1 }
                return CMBlockBufferReplaceDataBytes(
                    with: baseAddress,
                    blockBuffer: validBlock,
                    offsetIntoDestination: 0,
                    dataLength: packetData.count
                )
            }
            guard copyStatus == kCMBlockBufferNoErr else {
                return nil
            }

            var timing = CMSampleTimingInfo(
                duration: CMTime(seconds: max(duration, 1.0 / 60.0), preferredTimescale: 600),
                presentationTimeStamp: CMTime(seconds: max(pts, 0), preferredTimescale: 600),
                decodeTimeStamp: .invalid
            )
            var sampleSize = packetData.count
            var sampleBuffer: CMSampleBuffer?
            let sampleStatus = CMSampleBufferCreateReady(
                allocator: kCFAllocatorDefault,
                dataBuffer: validBlock,
                formatDescription: formatDescription,
                sampleCount: 1,
                sampleTimingEntryCount: 1,
                sampleTimingArray: &timing,
                sampleSizeEntryCount: 1,
                sampleSizeArray: &sampleSize,
                sampleBufferOut: &sampleBuffer
            )
            guard sampleStatus == noErr, let validSample = sampleBuffer else {
                return nil
            }

            var decodedPixelBuffer: CVPixelBuffer?
            var infoFlags = VTDecodeInfoFlags()
            let decodeStatus = VTDecompressionSessionDecodeFrame(
                session,
                sampleBuffer: validSample,
                flags: [],
                infoFlagsOut: &infoFlags,
                outputHandler: { status, _, imageBuffer, _, _ in
                    if status == noErr, let imageBuffer {
                        decodedPixelBuffer = imageBuffer
                    }
                }
            )

            guard decodeStatus == noErr else { return nil }
            return decodedPixelBuffer
        }

        func invalidate() {
            if let session {
                VTDecompressionSessionInvalidate(session)
                self.session = nil
            }
        }

        deinit {
            invalidate()
        }
    }

    // MARK: - BGRA + Alpha Compositing & Downscaling

    private static let srgbColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    private static func makeCompositedCGImage(
        colorBuffer: CVPixelBuffer,
        alphaBuffer: CVPixelBuffer?,
        maxPixelSize: Int
    ) -> CGImage? {
        CVPixelBufferLockBaseAddress(colorBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(colorBuffer, .readOnly) }

        if let alphaBuffer {
            CVPixelBufferLockBaseAddress(alphaBuffer, .readOnly)
        }
        defer {
            if let alphaBuffer {
                CVPixelBufferUnlockBaseAddress(alphaBuffer, .readOnly)
            }
        }

        let width = CVPixelBufferGetWidth(colorBuffer)
        let height = CVPixelBufferGetHeight(colorBuffer)
        guard width > 0, height > 0,
              let colorBaseRaw = CVPixelBufferGetBaseAddress(colorBuffer)
        else {
            return nil
        }

        let colorBytesPerRow = CVPixelBufferGetBytesPerRow(colorBuffer)
        let colorBytes = colorBaseRaw.assumingMemoryBound(to: UInt8.self)

        let outBytesPerRow = width * 4
        var outputData = Data(count: outBytesPerRow * height)

        let alphaIsUsable: Bool
        var alphaIsPlanar = false
        var alphaBytes: UnsafePointer<UInt8>?
        var alphaBytesPerRow = 0

        if let alphaBuffer,
           CVPixelBufferGetWidth(alphaBuffer) == width,
           CVPixelBufferGetHeight(alphaBuffer) == height
        {
            if CVPixelBufferIsPlanar(alphaBuffer),
               let plane0 = CVPixelBufferGetBaseAddressOfPlane(alphaBuffer, 0)
            {
                alphaIsPlanar = true
                alphaBytes = UnsafePointer(plane0.assumingMemoryBound(to: UInt8.self))
                alphaBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(alphaBuffer, 0)
                alphaIsUsable = true
            } else if let base = CVPixelBufferGetBaseAddress(alphaBuffer) {
                alphaIsPlanar = false
                alphaBytes = UnsafePointer(base.assumingMemoryBound(to: UInt8.self))
                alphaBytesPerRow = CVPixelBufferGetBytesPerRow(alphaBuffer)
                alphaIsUsable = true
            } else {
                alphaIsUsable = false
            }
        } else {
            alphaIsUsable = false
        }

        outputData.withUnsafeMutableBytes { outRaw in
            guard let outBase = outRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }

            if !alphaIsUsable {
                for y in 0..<height {
                    let srcRow = colorBytes + y * colorBytesPerRow
                    let dstRow = outBase + y * outBytesPerRow
                    dstRow.update(from: srcRow, count: outBytesPerRow)
                }
                return
            }

            guard let aBase = alphaBytes else { return }

            for y in 0..<height {
                let srcRow = colorBytes + y * colorBytesPerRow
                let dstRow = outBase + y * outBytesPerRow
                let alphaRow = aBase + y * alphaBytesPerRow

                for x in 0..<width {
                    let px = x * 4
                    let alpha: UInt8 = alphaIsPlanar ? alphaRow[x] : alphaRow[px + 1]

                    if alpha == 0 {
                        dstRow[px] = 0
                        dstRow[px + 1] = 0
                        dstRow[px + 2] = 0
                        dstRow[px + 3] = 0
                    } else if alpha == 255 {
                        dstRow[px] = srcRow[px]
                        dstRow[px + 1] = srcRow[px + 1]
                        dstRow[px + 2] = srcRow[px + 2]
                        dstRow[px + 3] = 255
                    } else {
                        let a16 = UInt16(alpha)
                        dstRow[px] = UInt8((UInt16(srcRow[px]) * a16 + 127) / 255)
                        dstRow[px + 1] = UInt8((UInt16(srcRow[px + 1]) * a16 + 127) / 255)
                        dstRow[px + 2] = UInt8((UInt16(srcRow[px + 2]) * a16 + 127) / 255)
                        dstRow[px + 3] = alpha
                    }
                }
            }
        }

        let bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        guard let provider = CGDataProvider(data: outputData as CFData),
              let fullImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: outBytesPerRow,
                space: srgbColorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              )
        else {
            return nil
        }

        let longest = max(width, height)
        guard maxPixelSize > 0, longest > maxPixelSize else {
            return fullImage
        }

        let scale = Double(maxPixelSize) / Double(longest)
        let targetW = max(1, Int((Double(width) * scale).rounded()))
        let targetH = max(1, Int((Double(height) * scale).rounded()))

        guard let ctx = CGContext(
            data: nil,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: targetW * 4,
            space: srgbColorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return fullImage
        }

        ctx.interpolationQuality = .high
        ctx.draw(fullImage, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        return ctx.makeImage() ?? fullImage
    }
}

// MARK: - Bounded Concurrency Limiter & Cache

private actor WebMDecodeConcurrencyGate {
    private let maxConcurrent: Int
    private var activeCount: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    func acquire() async {
        if activeCount < maxConcurrent {
            activeCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            activeCount = max(0, activeCount - 1)
        }
    }
}

/// Process-wide bounded cache for decoded WebM video sticker animations and static first frames.
@MainActor
final class WebMStickerCache {
    static let shared = WebMStickerCache()

    private let sequenceCache = NSCache<NSString, WebMStickerSequence>()
    private let firstFrameCache = NSCache<NSString, NSImage>()
    private var inFlightSequences: [String: Task<WebMStickerSequence?, Never>] = [:]
    private var inFlightFirstFrames: [String: Task<CGImage?, Never>] = [:]
    private var unsupportedPaths: Set<String> = []
    private let decodeGate = WebMDecodeConcurrencyGate(maxConcurrent: 3)

    private init() {
        sequenceCache.totalCostLimit = 96 * 1024 * 1024 // 96 MB memory ceiling
        sequenceCache.countLimit = 28
        firstFrameCache.countLimit = 260
    }

    func cachedSequence(for path: String, maxPixelSize: Int) -> WebMStickerSequence? {
        sequenceCache.object(forKey: sequenceKey(path: path, maxPixelSize: maxPixelSize) as NSString)
    }

    func cachedFirstFrame(for path: String, maxPixelSize: Int) -> NSImage? {
        firstFrameCache.object(forKey: sequenceKey(path: path, maxPixelSize: maxPixelSize) as NSString)
    }

    func isUnsupported(path: String) -> Bool {
        unsupportedPaths.contains(path)
    }

    func loadSequence(from path: String, maxPixelSize: Int = 256) async -> WebMStickerSequence? {
        guard !path.isEmpty, !unsupportedPaths.contains(path) else { return nil }
        let key = sequenceKey(path: path, maxPixelSize: maxPixelSize)

        if let cached = sequenceCache.object(forKey: key as NSString) {
            return cached
        }

        if let existing = inFlightSequences[key] {
            return await existing.value
        }

        let gate = decodeGate
        let task = Task.detached(priority: .userInitiated) { () -> WebMStickerSequence? in
            await gate.acquire()
            let decoded = WebMStickerDecoder.decodeSequence(
                fromFilePath: path,
                maxPixelSize: maxPixelSize,
                firstFrameOnly: false
            )
            await gate.release()
            return decoded
        }
        inFlightSequences[key] = task

        let sequence = await task.value
        inFlightSequences.removeValue(forKey: key)

        if let sequence {
            sequenceCache.setObject(sequence, forKey: key as NSString, cost: sequence.estimatedByteCost)
            if let first = sequence.frames.first?.image {
                let firstImage = NSImage(cgImage: first, size: NSSize(width: first.width, height: first.height))
                firstFrameCache.setObject(firstImage, forKey: key as NSString)
            }
        } else {
            unsupportedPaths.insert(path)
        }

        return sequence
    }

    func loadFirstFrame(from path: String, maxPixelSize: Int = 128) async -> NSImage? {
        guard !path.isEmpty, !unsupportedPaths.contains(path) else { return nil }
        let key = sequenceKey(path: path, maxPixelSize: maxPixelSize)

        if let cached = firstFrameCache.object(forKey: key as NSString) {
            return cached
        }

        if let seq = sequenceCache.object(forKey: key as NSString), let first = seq.frames.first?.image {
            let img = NSImage(cgImage: first, size: NSSize(width: first.width, height: first.height))
            firstFrameCache.setObject(img, forKey: key as NSString)
            return img
        }

        if let existing = inFlightFirstFrames[key] {
            guard let cg = await existing.value else { return nil }
            if let cached = firstFrameCache.object(forKey: key as NSString) {
                return cached
            }
            let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            firstFrameCache.setObject(image, forKey: key as NSString)
            return image
        }

        let gate = decodeGate
        let task = Task.detached(priority: .utility) { () -> CGImage? in
            await gate.acquire()
            let seq = WebMStickerDecoder.decodeSequence(
                fromFilePath: path,
                maxPixelSize: maxPixelSize,
                firstFrameOnly: true
            )
            await gate.release()
            return seq?.frames.first?.image
        }
        inFlightFirstFrames[key] = task

        let cgImage = await task.value
        inFlightFirstFrames.removeValue(forKey: key)

        if let cgImage {
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            firstFrameCache.setObject(image, forKey: key as NSString)
            return image
        } else {
            unsupportedPaths.insert(path)
            return nil
        }
    }

    func clear() {
        sequenceCache.removeAllObjects()
        firstFrameCache.removeAllObjects()
        unsupportedPaths.removeAll()
    }

    private func sequenceKey(path: String, maxPixelSize: Int) -> String {
        "\(path)#\(maxPixelSize)"
    }
}
