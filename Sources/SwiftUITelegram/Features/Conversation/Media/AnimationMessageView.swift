import AppKit
import SwiftUI

struct AnimationMessageView: View {
    @Environment(AppStore.self) private var appStore

    let messageId: Int64
    let isOutgoing: Bool
    let media: AnimationMedia
    let primaryTextColor: Color
    let onOpenLightbox: () -> Void

    @State private var isSpoilerRevealed: Bool = false

    private static let autoDownloadLimitBytes: Int64 = 15 * 1024 * 1024

    private var transferState: FileTransferState {
        appStore.fileCache.state(for: media.file)
    }

    private var displaySize: CGSize {
        MediaBubbleSizing.fitSize(
            width: media.width > 0 ? media.width : 280,
            height: media.height > 0 ? media.height : 200,
            maxWidth: 320,
            maxHeight: 300
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

            animationSurface

            if !media.showCaptionAboveMedia && !media.caption.isEmpty {
                captionText
            }
        }
    }

    private var animationSurface: some View {
        let state = transferState

        return ZStack {
            if state.isDownloaded,
               let path = state.localPath,
               FileManager.default.fileExists(atPath: path)
            {
                let playbackURL = MediaFileActions.quickLookURL(
                    for: path,
                    preferredFileName: media.fileName.isEmpty
                        ? (media.isGIFImage ? "animation_\(messageId).gif" : "animation_\(messageId).mp4")
                        : media.fileName,
                    mimeType: media.mimeType
                )
                if media.isGIFImage {
                    AnimatedGIFImageView(url: playbackURL)
                } else {
                    LoopingVideoPlayerView(
                        url: playbackURL,
                        isMuted: true,
                        isPlaying: !(media.hasSpoiler && !isSpoilerRevealed)
                    )
                }
            } else if let thumb = thumbnailImage {
                Image(nsImage: thumb)
                    .resizable()
                    .scaledToFill()
            } else {
                MinithumbnailBackdrop(minithumbnailData: media.minithumbnailData)
            }

            if !state.isDownloaded || state.isUploading {
                MediaTransferButton(
                    state: state,
                    size: 44,
                    onStartDownload: {},
                    onCancelDownload: {}
                )
                .allowsHitTesting(false)
            }

            VStack {
                HStack {
                    Text("GIF")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
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
            } else {
                appStore.fileCache.startDownload(fileId: media.file.fileId, priority: 24)
            }
        }
        .task(id: media.file.fileId) {
            if let thumb = media.thumbnail, thumb.format.isStaticImage {
                appStore.fileCache.ensureDownloaded(thumb.file, priority: 18)
            }
            if media.file.expectedSize == 0 || media.file.expectedSize <= Self.autoDownloadLimitBytes {
                appStore.fileCache.ensureDownloaded(media.file, priority: 20)
            }
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
