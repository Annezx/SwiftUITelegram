import AppKit
import SwiftUI

struct VideoMessageView: View {
    @Environment(AppStore.self) private var appStore

    let messageId: Int64
    let isOutgoing: Bool
    let media: VideoMedia
    let primaryTextColor: Color
    let onOpenLightbox: () -> Void

    @State private var isSpoilerRevealed: Bool = false

    private var transferState: FileTransferState {
        appStore.fileCache.state(for: media.file)
    }

    private var displaySize: CGSize {
        MediaBubbleSizing.fitSize(
            width: media.width > 0 ? media.width : 320,
            height: media.height > 0 ? media.height : 200
        )
    }

    private var thumbnailImage: NSImage? {
        guard let thumb = media.thumbnail, thumb.format.isStaticImage else { return nil }
        return appStore.fileCache.image(for: thumb.file)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if media.showCaptionAboveMedia && !media.caption.isEmpty {
                captionText
            }

            videoPreviewCard

            if !media.showCaptionAboveMedia && !media.caption.isEmpty {
                captionText
            }
        }
    }

    private var videoPreviewCard: some View {
        let state = transferState

        return ZStack {
            if let thumb = thumbnailImage {
                Image(nsImage: thumb)
                    .resizable()
                    .scaledToFill()
            } else {
                MinithumbnailBackdrop(minithumbnailData: media.minithumbnailData)
            }

            // Subtle dark scrim so controls & badges stay legible on bright thumbnails.
            Rectangle()
                .fill(.black.opacity(0.18))

            MediaTransferButton(
                state: state,
                readySystemImage: "play.fill",
                size: 50,
                onStartDownload: {},
                onCancelDownload: {}
            )
            .allowsHitTesting(false)

            // Top-left duration & size badge
            VStack {
                HStack {
                    badgePill(state: state)
                    Spacer()
                }
                Spacer()
            }
            .padding(8)

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
            if state.isDownloaded {
                onOpenLightbox()
            } else if state.isDownloading {
                appStore.fileCache.cancelDownload(fileId: media.file.fileId)
            } else if !state.isUploading {
                appStore.fileCache.startDownload(fileId: media.file.fileId, priority: 28)
            }
        }
        .task(id: media.thumbnail?.file.fileId) {
            if let thumb = media.thumbnail, thumb.format.isStaticImage {
                appStore.fileCache.ensureDownloaded(thumb.file, priority: 20)
            }
        }
    }

    private func badgePill(state: FileTransferState) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "video.fill")
                .font(.caption2)
            Text(MediaFormatters.formatDuration(media.duration))
                .monospacedDigit()

            if state.isDownloading && state.expectedSize > 0 {
                Text("· \(MediaFormatters.formatFileSize(state.downloadedSize)) / \(MediaFormatters.formatFileSize(state.expectedSize))")
                    .monospacedDigit()
            } else if state.isUploading && state.expectedSize > 0 {
                Text("· 上传 \(Int((state.uploadProgress * 100).rounded()))%")
                    .monospacedDigit()
            } else if !state.isDownloaded && state.expectedSize > 0 {
                Text("· \(MediaFormatters.formatFileSize(state.expectedSize))")
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.56), in: Capsule())
    }

    private var captionText: some View {
        FormattedTextView(
            content: media.formattedCaption,
            isOutgoing: isOutgoing
        )
        .frame(maxWidth: displaySize.width, alignment: .leading)
    }
}
