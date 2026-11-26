import AppKit
import SwiftUI

struct DocumentMessageView: View {
    @Environment(AppStore.self) private var appStore

    let media: DocumentMedia
    let isOutgoing: Bool
    let primaryTextColor: Color
    let metaColor: Color
    let onPreviewFile: (URL) -> Void

    @State private var openQuickLookOnFinish: Bool = false

    private var transferState: FileTransferState {
        appStore.fileCache.state(for: media.file)
    }

    private var thumbnailImage: NSImage? {
        guard let thumb = media.thumbnail, thumb.format.isStaticImage else { return nil }
        return appStore.fileCache.image(for: thumb.file)
    }

    var body: some View {
        let state = transferState

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 11) {
                leadingBadge(state: state)

                VStack(alignment: .leading, spacing: 3) {
                    Text(media.displayFileName)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(2)
                        .truncationMode(.middle)

                    Text(statusSubtitle(state: state))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(metaColor)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if state.isDownloaded, let localPath = state.localPath {
                    HStack(spacing: 4) {
                        Button {
                            let url = MediaFileActions.quickLookURL(
                                for: localPath,
                                preferredFileName: media.fileName,
                                mimeType: media.mimeType
                            )
                            onPreviewFile(url)
                        } label: {
                            Image(systemName: "eye")
                                .font(.callout)
                                .foregroundStyle(primaryTextColor.opacity(0.9))
                                .frame(width: 26, height: 26)
                                .background(
                                    (isOutgoing ? Color.white.opacity(0.16) : Color.primary.opacity(0.06)),
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                        .help("快速预览 (Quick Look)")

                        Button {
                            MediaFileActions.saveFile(
                                from: localPath,
                                suggestedFileName: media.fileName,
                                mimeType: media.mimeType
                            )
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                                .font(.callout)
                                .foregroundStyle(primaryTextColor.opacity(0.9))
                                .frame(width: 26, height: 26)
                                .background(
                                    (isOutgoing ? Color.white.opacity(0.16) : Color.primary.opacity(0.06)),
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                        .help("另存为…")
                    }
                }
            }
            .frame(minWidth: 230, maxWidth: 350, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                handlePrimaryTap(state: state)
            }

            if !media.caption.isEmpty {
                Text(media.caption)
                    .font(.body)
                    .foregroundStyle(primaryTextColor)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: media.thumbnail?.file.fileId) {
            if let thumb = media.thumbnail, thumb.format.isStaticImage {
                appStore.fileCache.ensureDownloaded(thumb.file, priority: 14)
            }
        }
        .onChange(of: transferState.localPath) { _, newPath in
            if openQuickLookOnFinish, let newPath, !newPath.isEmpty {
                openQuickLookOnFinish = false
                let url = MediaFileActions.quickLookURL(
                    for: newPath,
                    preferredFileName: media.fileName,
                    mimeType: media.mimeType
                )
                onPreviewFile(url)
            }
        }
    }

    private func leadingBadge(state: FileTransferState) -> some View {
        ZStack {
            if let thumb = thumbnailImage {
                Image(nsImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isOutgoing ? Color.white.opacity(0.22) : fileTypeAccentColor.opacity(0.16))
                    .frame(width: 44, height: 44)
            }

            if state.isUploading {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.black.opacity(0.38))
                    CircularProgressRing(progress: state.uploadProgress, lineWidth: 2.5)
                        .frame(width: 30, height: 30)
                    Image(systemName: "arrow.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
            } else if state.isDownloading {
                Button {
                    openQuickLookOnFinish = false
                    appStore.fileCache.cancelDownload(fileId: media.file.fileId)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(.black.opacity(0.45))
                        CircularProgressRing(progress: state.downloadProgress, lineWidth: 2.5)
                            .frame(width: 30, height: 30)
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .help("取消下载")
            } else if !state.isDownloaded {
                ZStack {
                    if thumbnailImage != nil {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(.black.opacity(0.38))
                    }
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(isOutgoing || thumbnailImage != nil ? Color.white : fileTypeAccentColor)
                }
                .frame(width: 44, height: 44)
            } else if thumbnailImage == nil {
                Image(systemName: fileTypeSymbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isOutgoing ? Color.white : fileTypeAccentColor)
            }
        }
    }

    private func handlePrimaryTap(state: FileTransferState) {
        if state.isDownloaded, let localPath = state.localPath {
            let url = MediaFileActions.quickLookURL(
                for: localPath,
                preferredFileName: media.fileName,
                mimeType: media.mimeType
            )
            onPreviewFile(url)
        } else if state.isDownloading {
            openQuickLookOnFinish = false
            appStore.fileCache.cancelDownload(fileId: media.file.fileId)
        } else if !state.isUploading {
            openQuickLookOnFinish = true
            appStore.fileCache.startDownload(fileId: media.file.fileId, priority: 26)
        }
    }

    private func statusSubtitle(state: FileTransferState) -> String {
        let sizeText = MediaFormatters.formatFileSize(state.expectedSize)
        if state.isUploading {
            let pct = Int((state.uploadProgress * 100).rounded())
            return sizeText.isEmpty ? "正在上传 \(pct)%" : "正在上传 \(pct)% · \(sizeText)"
        }
        if state.isDownloading {
            let dl = MediaFormatters.formatFileSize(state.downloadedSize)
            if !sizeText.isEmpty {
                return "\(dl) / \(sizeText)"
            }
            return "正在下载…"
        }
        if state.isDownloaded {
            let extLabel = media.fileExtension.isEmpty ? "" : "\(media.fileExtension.uppercased()) · "
            return sizeText.isEmpty ? "已下载 · 点击预览" : "\(extLabel)\(sizeText) · 点击预览"
        }
        return sizeText.isEmpty ? "点击下载" : "\(sizeText) · 点击下载"
    }

    private var fileTypeSymbol: String {
        switch media.fileExtension {
        case "pdf": return "doc.richtext.fill"
        case "zip", "rar", "7z", "tar", "gz", "dmg", "pkg": return "archivebox.fill"
        case "jpg", "jpeg", "png", "heic", "webp", "gif", "tiff": return "photo.fill"
        case "mp4", "mov", "mkv", "avi", "webm", "m4v": return "film.fill"
        case "mp3", "m4a", "wav", "flac", "aac", "ogg", "oga": return "waveform.circle.fill"
        case "swift", "py", "js", "ts", "json", "xml", "yml", "yaml", "md", "html", "css", "c", "cpp", "rs", "go":
            return "doc.text.fill"
        case "xls", "xlsx", "csv", "numbers": return "tablecells.fill"
        case "ppt", "pptx", "key": return "rectangle.on.rectangle.angled"
        default: return "doc.fill"
        }
    }

    private var fileTypeAccentColor: Color {
        switch media.fileExtension {
        case "pdf": return .red
        case "zip", "rar", "7z", "tar", "gz", "dmg", "pkg": return .orange
        case "jpg", "jpeg", "png", "heic", "webp", "gif", "tiff": return .green
        case "mp4", "mov", "mkv", "avi", "webm", "m4v": return .indigo
        case "mp3", "m4a", "wav", "flac", "aac", "ogg", "oga": return .purple
        case "xls", "xlsx", "csv", "numbers": return .teal
        default: return .accentColor
        }
    }
}
