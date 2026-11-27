import AppKit
import SwiftUI

struct PhotoMessageView: View {
    @Environment(AppStore.self) private var appStore

    let messageId: Int64
    let isOutgoing: Bool
    let media: PhotoMedia
    let primaryTextColor: Color
    let onOpenLightbox: () -> Void

    @State private var isSpoilerRevealed: Bool = false

    private var transferState: FileTransferState {
        appStore.fileCache.state(for: media.file)
    }

    private var displaySize: CGSize {
        MediaBubbleSizing.fitSize(width: media.width, height: media.height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if media.showCaptionAboveMedia && !media.caption.isEmpty {
                captionText
            }

            photoCanvas

            if !media.showCaptionAboveMedia && !media.caption.isEmpty {
                captionText
            }
        }
    }

    private var photoCanvas: some View {
        let fullImage = appStore.fileCache.image(for: media.file)
        let previewImage = media.previewFile.flatMap { appStore.fileCache.image(for: $0) }
        let state = transferState

        return ZStack {
            if let image = fullImage ?? previewImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: fullImage == nil ? 2 : 0)
            } else {
                MinithumbnailBackdrop(minithumbnailData: media.minithumbnailData)
            }

            if state.isUploading || (fullImage == nil && state.isDownloading) {
                MediaTransferButton(
                    state: state,
                    size: 42,
                    onStartDownload: {
                        appStore.fileCache.startDownload(fileId: media.file.fileId, priority: 26)
                    },
                    onCancelDownload: {
                        appStore.fileCache.cancelDownload(fileId: media.file.fileId)
                    }
                )
            } else if fullImage == nil && !state.isDownloaded {
                MediaTransferButton(
                    state: state,
                    size: 42,
                    onStartDownload: {
                        appStore.fileCache.startDownload(fileId: media.file.fileId, priority: 26)
                    },
                    onCancelDownload: {
                        appStore.fileCache.cancelDownload(fileId: media.file.fileId)
                    }
                )
            }

            if media.hasSpoiler && !isSpoilerRevealed {
                MediaSpoilerOverlay {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSpoilerRevealed = true
                    }
                }
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            if media.hasSpoiler && !isSpoilerRevealed {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSpoilerRevealed = true
                }
                return
            }
            if !state.isDownloaded && !state.isDownloading {
                appStore.fileCache.startDownload(fileId: media.file.fileId, priority: 28)
            }
            onOpenLightbox()
        }
        .task(id: media.file.fileId) {
            if let preview = media.previewFile {
                appStore.fileCache.ensureDownloaded(preview, priority: 22)
            }
            appStore.fileCache.ensureDownloaded(media.file, priority: 24)
        }
    }

    private var captionText: some View {
        FormattedTextView(
            content: media.formattedCaption,
            isOutgoing: isOutgoing
        )
        .frame(maxWidth: displaySize.width, alignment: .leading)
    }
}
