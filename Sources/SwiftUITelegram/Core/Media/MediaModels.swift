import Foundation
import TDLibKit

/// Immutable snapshot of a TDLib `File` attached to a message or thumbnail.
struct MediaFileDescriptor: Equatable, Hashable, Sendable {
    let fileId: Int
    let expectedSize: Int64
    let initialLocalPath: String?
    let initialDownloadedSize: Int64
    let initialIsDownloading: Bool
    let initialIsUploading: Bool
    let initialUploadedSize: Int64
    let initialIsUploaded: Bool

    init(
        fileId: Int,
        expectedSize: Int64 = 0,
        initialLocalPath: String? = nil,
        initialDownloadedSize: Int64 = 0,
        initialIsDownloading: Bool = false,
        initialIsUploading: Bool = false,
        initialUploadedSize: Int64 = 0,
        initialIsUploaded: Bool = true
    ) {
        self.fileId = fileId
        self.expectedSize = expectedSize
        self.initialLocalPath = initialLocalPath
        self.initialDownloadedSize = initialDownloadedSize
        self.initialIsDownloading = initialIsDownloading
        self.initialIsUploading = initialIsUploading
        self.initialUploadedSize = initialUploadedSize
        self.initialIsUploaded = initialIsUploaded
    }

    init(tdFile: File) {
        self.fileId = tdFile.id
        self.expectedSize = tdFile.size > 0 ? tdFile.size : tdFile.expectedSize
        if tdFile.local.isDownloadingCompleted, !tdFile.local.path.isEmpty {
            self.initialLocalPath = tdFile.local.path
        } else {
            self.initialLocalPath = nil
        }
        self.initialDownloadedSize = tdFile.local.downloadedSize
        self.initialIsDownloading = tdFile.local.isDownloadingActive
        self.initialIsUploading = tdFile.remote.isUploadingActive
        self.initialUploadedSize = tdFile.remote.uploadedSize
        self.initialIsUploaded = tdFile.remote.isUploadingCompleted
    }
}

/// Live reactive transfer status for a TDLib file managed by `FileCacheStore`.
struct FileTransferState: Equatable, Hashable, Sendable {
    let fileId: Int
    let expectedSize: Int64
    let localPath: String?
    let isDownloaded: Bool
    let isDownloading: Bool
    let downloadedSize: Int64
    let isUploading: Bool
    let isUploaded: Bool
    let uploadedSize: Int64

    var downloadProgress: Double {
        if isDownloaded { return 1.0 }
        guard expectedSize > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(downloadedSize) / Double(expectedSize)))
    }

    var uploadProgress: Double {
        if isUploaded { return 1.0 }
        guard expectedSize > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(uploadedSize) / Double(expectedSize)))
    }

    init(descriptor: MediaFileDescriptor) {
        self.fileId = descriptor.fileId
        self.expectedSize = descriptor.expectedSize
        self.localPath = descriptor.initialLocalPath
        self.isDownloaded = descriptor.initialLocalPath != nil
        self.isDownloading = descriptor.initialIsDownloading
        self.downloadedSize = descriptor.initialDownloadedSize
        self.isUploading = descriptor.initialIsUploading
        self.isUploaded = descriptor.initialIsUploaded
        self.uploadedSize = descriptor.initialUploadedSize
    }

    init(tdFile: File) {
        let total = tdFile.size > 0 ? tdFile.size : tdFile.expectedSize
        let completed = tdFile.local.isDownloadingCompleted && !tdFile.local.path.isEmpty
        self.fileId = tdFile.id
        self.expectedSize = total
        self.localPath = completed ? tdFile.local.path : nil
        self.isDownloaded = completed
        self.isDownloading = tdFile.local.isDownloadingActive
        self.downloadedSize = tdFile.local.downloadedSize
        self.isUploading = tdFile.remote.isUploadingActive
        self.isUploaded = tdFile.remote.isUploadingCompleted
        self.uploadedSize = tdFile.remote.uploadedSize
    }
}

enum ThumbnailMediaFormat: Equatable, Hashable, Sendable {
    case jpeg
    case png
    case webp
    case gif
    case mpeg4
    case webm
    case tgs

    /// True if macOS `NSImage` can decode this thumbnail format directly.
    var isStaticImage: Bool {
        switch self {
        case .jpeg, .png, .webp, .gif:
            return true
        case .mpeg4, .webm, .tgs:
            return false
        }
    }

    init(tdFormat: ThumbnailFormat) {
        switch tdFormat {
        case .thumbnailFormatJpeg: self = .jpeg
        case .thumbnailFormatPng: self = .png
        case .thumbnailFormatWebp: self = .webp
        case .thumbnailFormatGif: self = .gif
        case .thumbnailFormatMpeg4: self = .mpeg4
        case .thumbnailFormatWebm: self = .webm
        case .thumbnailFormatTgs: self = .tgs
        }
    }
}

struct ThumbnailInfo: Equatable, Hashable, Sendable {
    let file: MediaFileDescriptor
    let width: Int
    let height: Int
    let format: ThumbnailMediaFormat

    init(
        file: MediaFileDescriptor,
        width: Int,
        height: Int,
        format: ThumbnailMediaFormat
    ) {
        self.file = file
        self.width = width
        self.height = height
        self.format = format
    }

    init(tdThumbnail: Thumbnail) {
        self.file = MediaFileDescriptor(tdFile: tdThumbnail.file)
        self.width = tdThumbnail.width
        self.height = tdThumbnail.height
        self.format = ThumbnailMediaFormat(tdFormat: tdThumbnail.format)
    }
}

enum StickerMediaFormat: Equatable, Hashable, Sendable {
    case webp
    case tgs
    case webm

    init(tdFormat: StickerFormat) {
        switch tdFormat {
        case .stickerFormatWebp: self = .webp
        case .stickerFormatTgs: self = .tgs
        case .stickerFormatWebm: self = .webm
        }
    }

    var badgeLabel: String? {
        switch self {
        case .webp: return nil
        case .tgs: return "动态贴纸"
        case .webm: return "视频贴纸"
        }
    }
}

struct PhotoMedia: Equatable, Hashable, Sendable {
    let file: MediaFileDescriptor
    let previewFile: MediaFileDescriptor?
    let minithumbnailData: Data?
    let width: Int
    let height: Int
    let formattedCaption: FormattedTextContent
    let hasSpoiler: Bool
    let showCaptionAboveMedia: Bool

    var caption: String { formattedCaption.text }
}

struct VideoMedia: Equatable, Hashable, Sendable {
    let file: MediaFileDescriptor
    let thumbnail: ThumbnailInfo?
    let minithumbnailData: Data?
    let width: Int
    let height: Int
    let duration: Int
    let fileName: String
    let mimeType: String
    let supportsStreaming: Bool
    let formattedCaption: FormattedTextContent
    let hasSpoiler: Bool
    let showCaptionAboveMedia: Bool

    var caption: String { formattedCaption.text }
}

struct VideoNoteMedia: Equatable, Hashable, Sendable {
    let file: MediaFileDescriptor
    let thumbnail: ThumbnailInfo?
    let minithumbnailData: Data?
    let length: Int
    let duration: Int
    var isViewed: Bool
}

struct AnimationMedia: Equatable, Hashable, Sendable {
    let file: MediaFileDescriptor
    let thumbnail: ThumbnailInfo?
    let minithumbnailData: Data?
    let width: Int
    let height: Int
    let duration: Int
    let fileName: String
    let mimeType: String
    let formattedCaption: FormattedTextContent
    let hasSpoiler: Bool
    let showCaptionAboveMedia: Bool

    var caption: String { formattedCaption.text }

    var isGIFImage: Bool {
        mimeType.lowercased().contains("gif") || fileName.lowercased().hasSuffix(".gif")
    }
}

struct DocumentMedia: Equatable, Hashable, Sendable {
    let file: MediaFileDescriptor
    let thumbnail: ThumbnailInfo?
    let minithumbnailData: Data?
    let fileName: String
    let mimeType: String
    let formattedCaption: FormattedTextContent

    var caption: String { formattedCaption.text }

    var displayFileName: String {
        fileName.isEmpty ? "未命名文件" : fileName
    }

    var fileExtension: String {
        URL(fileURLWithPath: fileName).pathExtension.lowercased()
    }
}

struct VoiceNoteMedia: Equatable, Hashable, Sendable {
    let file: MediaFileDescriptor
    let duration: Int
    let mimeType: String
    let waveformLevels: [Float]
    var isListened: Bool
    let formattedCaption: FormattedTextContent

    var caption: String { formattedCaption.text }
}

struct AudioMedia: Equatable, Hashable, Sendable {
    let file: MediaFileDescriptor
    let albumCoverThumbnail: ThumbnailInfo?
    let albumCoverMinithumbnailData: Data?
    let duration: Int
    let title: String
    let performer: String
    let fileName: String
    let mimeType: String
    let formattedCaption: FormattedTextContent

    var caption: String { formattedCaption.text }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if !fileName.isEmpty {
            return URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        }
        return "音频文件"
    }

    var displayPerformer: String {
        performer.isEmpty ? "未知艺术家" : performer
    }
}

struct StickerMedia: Equatable, Hashable, Sendable {
    let file: MediaFileDescriptor
    let thumbnail: ThumbnailInfo?
    let emoji: String
    let width: Int
    let height: Int
    let format: StickerMediaFormat
}

struct LocationMedia: Equatable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
}

struct ContactMedia: Equatable, Hashable, Sendable {
    let firstName: String
    let lastName: String
    let phoneNumber: String

    var displayName: String {
        let joined = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return joined.isEmpty ? phoneNumber : joined
    }
}

enum MediaFormatters {
    static func formatDuration(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        formatDuration(Int(seconds.rounded(.down)))
    }

    static func formatFileSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
