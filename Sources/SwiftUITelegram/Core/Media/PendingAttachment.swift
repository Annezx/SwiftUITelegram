import AppKit
import AVFoundation
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PendingAttachmentKind: Equatable, Hashable, Sendable {
    case photo
    case video
    case animation
    case audio
    case document

    var label: String {
        switch self {
        case .photo: return "图片"
        case .video: return "视频"
        case .animation: return "GIF"
        case .audio: return "音频"
        case .document: return "文件"
        }
    }

    var systemImage: String {
        switch self {
        case .photo: return "photo"
        case .video: return "film"
        case .animation: return "sparkles.tv"
        case .audio: return "music.note"
        case .document: return "doc.fill"
        }
    }
}

/// Represents a local media file staged inside the app's sandbox container, ready for upload to TDLib.
struct PendingAttachment: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let stagingDirectory: URL
    let kind: PendingAttachmentKind
    let fileName: String
    let fileSize: Int64
    let stagedOriginalURL: URL
    let preparedPhotoURL: URL?
    let thumbnailURL: URL?
    let thumbnailWidth: Int
    let thumbnailHeight: Int
    let width: Int
    let height: Int
    let duration: Int
    let audioTitle: String
    let audioPerformer: String

    var previewImageURL: URL? {
        thumbnailURL ?? preparedPhotoURL ?? (kind == .photo || kind == .animation ? stagedOriginalURL : nil)
    }

    /// True if toggling "send as original document" is meaningful for this attachment.
    var supportsOriginalFileToggle: Bool {
        kind == .photo || kind == .video
    }

    /// True if this attachment supports Telegram spoiler blur when sent as media.
    var supportsSpoiler: Bool {
        kind == .photo || kind == .video || kind == .animation
    }
}

/// Prepares local files, dropped URLs, and pasted images asynchronously on a background task:
/// copies files into the sandbox-owned staging directory, extracts media dimensions/durations/metadata,
/// generates JPEG thumbnails, and normalizes oversized/HEIC photos for Telegram `InputPhoto`.
enum MediaAttachmentPreparer {
    private static let maxPhotoDimension: CGFloat = 2560
    private static let maxPhotoFileSizeBytes: Int64 = 9_500_000
    private static let maxThumbnailDimension: CGFloat = 320

    static func prepare(urls: [URL], forceDocument: Bool = false) async -> [PendingAttachment] {
        var prepared: [PendingAttachment] = []
        for url in urls {
            if let attachment = await prepareSingle(url: url, forceDocument: forceDocument) {
                prepared.append(attachment)
            }
        }
        return prepared
    }

    @MainActor
    static func preparePastedImage(_ image: NSImage) async -> PendingAttachment? {
        guard let tiffData = image.tiffRepresentation else { return nil }
        return await Task.detached(priority: .userInitiated) {
            let id = UUID()
            let stagingDir = AppConfiguration.outgoingStagingDirectory
                .appendingPathComponent(id.uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let fileName = "Image_\(formatter.string(from: Foundation.Date())).png"
            let pngURL = stagingDir.appendingPathComponent(fileName)

            guard let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:])
            else {
                try? FileManager.default.removeItem(at: stagingDir)
                return nil
            }

            do {
                try pngData.write(to: pngURL, options: .atomic)
            } catch {
                try? FileManager.default.removeItem(at: stagingDir)
                return nil
            }

            return await buildPhotoAttachment(
                id: id,
                stagingDir: stagingDir,
                stagedOriginalURL: pngURL,
                fileName: fileName,
                fileSize: Int64(pngData.count)
            )
        }.value
    }

    static func cleanup(_ attachment: PendingAttachment) {
        try? FileManager.default.removeItem(at: attachment.stagingDirectory)
    }

    // MARK: - Single File Staging

    private static func prepareSingle(url: URL, forceDocument: Bool) async -> PendingAttachment? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        guard !isDirectory, FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let id = UUID()
        let stagingDir = AppConfiguration.outgoingStagingDirectory
            .appendingPathComponent(id.uuidString, isDirectory: true)
        let originalFileName = url.lastPathComponent.isEmpty ? "file" : url.lastPathComponent
        let stagedURL = stagingDir.appendingPathComponent(originalFileName)

        do {
            try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            // On macOS APFS volumes, `copyItem` uses fast copy-on-write cloning.
            try FileManager.default.copyItem(at: url, to: stagedURL)
        } catch {
            try? FileManager.default.removeItem(at: stagingDir)
            return nil
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: stagedURL.path)
        let fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let kind: PendingAttachmentKind = forceDocument ? .document : classify(url: stagedURL)

        switch kind {
        case .photo:
            return await buildPhotoAttachment(
                id: id,
                stagingDir: stagingDir,
                stagedOriginalURL: stagedURL,
                fileName: originalFileName,
                fileSize: fileSize
            )
        case .video:
            return await buildVideoAttachment(
                id: id,
                stagingDir: stagingDir,
                stagedOriginalURL: stagedURL,
                fileName: originalFileName,
                fileSize: fileSize
            )
        case .animation:
            return await buildAnimationAttachment(
                id: id,
                stagingDir: stagingDir,
                stagedOriginalURL: stagedURL,
                fileName: originalFileName,
                fileSize: fileSize
            )
        case .audio:
            return await buildAudioAttachment(
                id: id,
                stagingDir: stagingDir,
                stagedOriginalURL: stagedURL,
                fileName: originalFileName,
                fileSize: fileSize
            )
        case .document:
            return PendingAttachment(
                id: id,
                stagingDirectory: stagingDir,
                kind: .document,
                fileName: originalFileName,
                fileSize: fileSize,
                stagedOriginalURL: stagedURL,
                preparedPhotoURL: nil,
                thumbnailURL: nil,
                thumbnailWidth: 0,
                thumbnailHeight: 0,
                width: 0,
                height: 0,
                duration: 0,
                audioTitle: "",
                audioPerformer: ""
            )
        }
    }

    private static func classify(url: URL) -> PendingAttachmentKind {
        let ext = url.pathExtension.lowercased()
        guard let utType = UTType(filenameExtension: ext) else {
            return .document
        }
        if utType.conforms(to: .gif) {
            return .animation
        }
        if utType.conforms(to: .image) {
            // SVG / ICO / PSD are better delivered as documents than compressed photos.
            if ["svg", "ico", "icns", "psd", "ai", "eps", "raw", "dng", "cr2", "nef"].contains(ext) {
                return .document
            }
            return .photo
        }
        if utType.conforms(to: .movie) || utType.conforms(to: .video) {
            return .video
        }
        if utType.conforms(to: .audio) {
            return .audio
        }
        return .document
    }

    // MARK: - Type-Specific Metadata & Thumbnails

    private static func buildPhotoAttachment(
        id: UUID,
        stagingDir: URL,
        stagedOriginalURL: URL,
        fileName: String,
        fileSize: Int64
    ) async -> PendingAttachment {
        await Task.detached(priority: .userInitiated) {
            let source = CGImageSourceCreateWithURL(stagedOriginalURL as CFURL, nil)
            let orientedSize = source.flatMap(orientedPixelSize(from:)) ?? CGSize(width: 1024, height: 1024)
            let ext = stagedOriginalURL.pathExtension.lowercased()

            let needsJPEGRender =
                !(ext == "jpg" || ext == "jpeg")
                || fileSize > maxPhotoFileSizeBytes
                || max(orientedSize.width, orientedSize.height) > maxPhotoDimension

            var photoURL = stagedOriginalURL
            var finalWidth = Int(orientedSize.width.rounded())
            var finalHeight = Int(orientedSize.height.rounded())

            if needsJPEGRender, let source {
                let targetMax = Int(min(maxPhotoDimension, max(orientedSize.width, orientedSize.height)))
                if let cgImage = createThumbnailCGImage(from: source, maxPixelSize: max(targetMax, 64)) {
                    let jpegURL = stagingDir.appendingPathComponent("prepared_photo.jpg")
                    if writeJPEG(cgImage, to: jpegURL, quality: 0.86) {
                        photoURL = jpegURL
                        finalWidth = cgImage.width
                        finalHeight = cgImage.height
                    }
                }
            }

            var thumbURL: URL?
            var thumbW = 0
            var thumbH = 0
            if let source, let thumbCG = createThumbnailCGImage(from: source, maxPixelSize: Int(maxThumbnailDimension)) {
                let candidateThumb = stagingDir.appendingPathComponent("thumb.jpg")
                if writeJPEG(thumbCG, to: candidateThumb, quality: 0.72) {
                    thumbURL = candidateThumb
                    thumbW = thumbCG.width
                    thumbH = thumbCG.height
                }
            }

            return PendingAttachment(
                id: id,
                stagingDirectory: stagingDir,
                kind: .photo,
                fileName: fileName,
                fileSize: fileSize,
                stagedOriginalURL: stagedOriginalURL,
                preparedPhotoURL: photoURL,
                thumbnailURL: thumbURL,
                thumbnailWidth: thumbW,
                thumbnailHeight: thumbH,
                width: max(finalWidth, 1),
                height: max(finalHeight, 1),
                duration: 0,
                audioTitle: "",
                audioPerformer: ""
            )
        }.value
    }

    private static func buildVideoAttachment(
        id: UUID,
        stagingDir: URL,
        stagedOriginalURL: URL,
        fileName: String,
        fileSize: Int64
    ) async -> PendingAttachment {
        let asset = AVURLAsset(url: stagedOriginalURL)
        var durationSeconds = 0
        var width = 0
        var height = 0

        if let duration = try? await asset.load(.duration) {
            let secs = CMTimeGetSeconds(duration)
            if secs.isFinite && secs > 0 {
                durationSeconds = Int(secs.rounded())
            }
        }

        if let videoTrack = (try? await asset.loadTracks(withMediaType: .video))?.first {
            let natural = (try? await videoTrack.load(.naturalSize)) ?? .zero
            let transform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
            let transformed = natural.applying(transform)
            width = Int(abs(transformed.width).rounded())
            height = Int(abs(transformed.height).rounded())
        }

        var thumbURL: URL?
        var thumbW = 0
        var thumbH = 0
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxThumbnailDimension, height: maxThumbnailDimension)
        if let cgImage = try? await generator.image(at: .zero).image {
            let candidate = stagingDir.appendingPathComponent("video_thumb.jpg")
            if writeJPEG(cgImage, to: candidate, quality: 0.75) {
                thumbURL = candidate
                thumbW = cgImage.width
                thumbH = cgImage.height
                if width == 0 || height == 0 {
                    width = cgImage.width
                    height = cgImage.height
                }
            }
        }

        return PendingAttachment(
            id: id,
            stagingDirectory: stagingDir,
            kind: .video,
            fileName: fileName,
            fileSize: fileSize,
            stagedOriginalURL: stagedOriginalURL,
            preparedPhotoURL: nil,
            thumbnailURL: thumbURL,
            thumbnailWidth: thumbW,
            thumbnailHeight: thumbH,
            width: width,
            height: height,
            duration: durationSeconds,
            audioTitle: "",
            audioPerformer: ""
        )
    }

    private static func buildAnimationAttachment(
        id: UUID,
        stagingDir: URL,
        stagedOriginalURL: URL,
        fileName: String,
        fileSize: Int64
    ) async -> PendingAttachment {
        await Task.detached(priority: .userInitiated) {
            let source = CGImageSourceCreateWithURL(stagedOriginalURL as CFURL, nil)
            let size = source.flatMap(orientedPixelSize(from:)) ?? CGSize(width: 320, height: 240)
            var durationSecs: Double = 0
            if let source {
                let frameCount = CGImageSourceGetCount(source)
                for idx in 0..<frameCount {
                    if let props = CGImageSourceCopyPropertiesAtIndex(source, idx, nil) as? [CFString: Any],
                       let gifDict = props[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                    {
                        let delay = (gifDict[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                            ?? (gifDict[kCGImagePropertyGIFDelayTime] as? Double)
                            ?? 0.1
                        durationSecs += max(delay, 0.02)
                    }
                }
            }

            var thumbURL: URL?
            var thumbW = 0
            var thumbH = 0
            if let source, let thumbCG = createThumbnailCGImage(from: source, maxPixelSize: Int(maxThumbnailDimension)) {
                let candidate = stagingDir.appendingPathComponent("gif_thumb.jpg")
                if writeJPEG(thumbCG, to: candidate, quality: 0.75) {
                    thumbURL = candidate
                    thumbW = thumbCG.width
                    thumbH = thumbCG.height
                }
            }

            return PendingAttachment(
                id: id,
                stagingDirectory: stagingDir,
                kind: .animation,
                fileName: fileName,
                fileSize: fileSize,
                stagedOriginalURL: stagedOriginalURL,
                preparedPhotoURL: nil,
                thumbnailURL: thumbURL,
                thumbnailWidth: thumbW,
                thumbnailHeight: thumbH,
                width: Int(size.width.rounded()),
                height: Int(size.height.rounded()),
                duration: max(1, Int(durationSecs.rounded())),
                audioTitle: "",
                audioPerformer: ""
            )
        }.value
    }

    private static func buildAudioAttachment(
        id: UUID,
        stagingDir: URL,
        stagedOriginalURL: URL,
        fileName: String,
        fileSize: Int64
    ) async -> PendingAttachment {
        let asset = AVURLAsset(url: stagedOriginalURL)
        var durationSeconds = 0
        var title = ""
        var performer = ""
        var thumbURL: URL?
        var thumbW = 0
        var thumbH = 0

        if let duration = try? await asset.load(.duration) {
            let secs = CMTimeGetSeconds(duration)
            if secs.isFinite && secs > 0 {
                durationSeconds = Int(secs.rounded())
            }
        }

        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if title.isEmpty, let value = (try? await item.load(.stringValue)) ?? nil {
                        title = String(value.prefix(64))
                    }
                case .commonKeyArtist:
                    if performer.isEmpty, let value = (try? await item.load(.stringValue)) ?? nil {
                        performer = String(value.prefix(64))
                    }
                case .commonKeyArtwork:
                    if thumbURL == nil,
                       let data = (try? await item.load(.dataValue)) ?? nil,
                       let source = CGImageSourceCreateWithData(data as CFData, nil),
                       let cgImage = createThumbnailCGImage(from: source, maxPixelSize: Int(maxThumbnailDimension))
                    {
                        let candidate = stagingDir.appendingPathComponent("cover.jpg")
                        if writeJPEG(cgImage, to: candidate, quality: 0.78) {
                            thumbURL = candidate
                            thumbW = cgImage.width
                            thumbH = cgImage.height
                        }
                    }
                default:
                    break
                }
            }
        }

        return PendingAttachment(
            id: id,
            stagingDirectory: stagingDir,
            kind: .audio,
            fileName: fileName,
            fileSize: fileSize,
            stagedOriginalURL: stagedOriginalURL,
            preparedPhotoURL: nil,
            thumbnailURL: thumbURL,
            thumbnailWidth: thumbW,
            thumbnailHeight: thumbH,
            width: 0,
            height: 0,
            duration: durationSeconds,
            audioTitle: title,
            audioPerformer: performer
        )
    }

    // MARK: - ImageIO Helpers

    private static func orientedPixelSize(from source: CGImageSource) -> CGSize? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat
        else {
            return nil
        }
        let orientation = (props[kCGImagePropertyOrientation] as? UInt32) ?? 1
        // EXIF orientations 5...8 transpose width and height.
        if (5...8).contains(orientation) {
            return CGSize(width: h, height: w)
        }
        return CGSize(width: w, height: h)
    }

    private static func createThumbnailCGImage(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func writeJPEG(_ cgImage: CGImage, to url: URL, quality: CGFloat) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return false
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }
}
