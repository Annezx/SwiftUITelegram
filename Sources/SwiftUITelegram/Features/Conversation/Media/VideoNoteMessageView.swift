import AppKit
import SwiftUI

struct VideoNoteMessageView: View {
    @Environment(AppStore.self) private var appStore

    let messageId: Int64
    let isOutgoing: Bool
    let media: VideoNoteMedia

    @State private var isPlayingWithSound: Bool = false
    @State private var playbackProgress: Double = 0

    private let diameter: CGFloat = 204

    private var transferState: FileTransferState {
        appStore.fileCache.state(for: media.file)
    }

    private var thumbnailImage: NSImage? {
        guard let thumb = media.thumbnail, thumb.format.isStaticImage else { return nil }
        return appStore.fileCache.image(for: thumb.file)
    }

    var body: some View {
        let state = transferState

        VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 5) {
            ZStack {
                if state.isDownloaded, let path = state.localPath {
                    LoopingVideoPlayerView(
                        url: URL(fileURLWithPath: path),
                        isMuted: !isPlayingWithSound,
                        isPlaying: true,
                        onProgress: isPlayingWithSound ? { progress in
                            playbackProgress = progress
                        } : nil
                    )
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
                        size: 46,
                        onStartDownload: {
                            appStore.fileCache.startDownload(fileId: media.file.fileId, priority: 26)
                        },
                        onCancelDownload: {
                            appStore.fileCache.cancelDownload(fileId: media.file.fileId)
                        }
                    )
                }

                if isPlayingWithSound {
                    Circle()
                        .trim(from: 0, to: max(0.02, playbackProgress))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(2)
                } else {
                    Circle()
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                }

                if state.isDownloaded && !isPlayingWithSound {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "speaker.slash.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(.black.opacity(0.55), in: Circle())
                                .padding(12)
                        }
                    }
                }
            }
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
            .contentShape(Circle())
            .onTapGesture {
                if state.isDownloaded {
                    isPlayingWithSound.toggle()
                    if isPlayingWithSound {
                        appStore.audioPlayer.stop()
                        if !isOutgoing && !media.isViewed {
                            appStore.conversation.markMessageContentOpened(messageId: messageId)
                        }
                    }
                } else if state.isDownloading {
                    appStore.fileCache.cancelDownload(fileId: media.file.fileId)
                } else {
                    appStore.fileCache.startDownload(fileId: media.file.fileId, priority: 28)
                }
            }

            HStack(spacing: 5) {
                if !isOutgoing && !media.isViewed {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
                Image(systemName: isPlayingWithSound ? "speaker.wave.2.fill" : "video.circle.fill")
                    .font(.caption2)
                Text(MediaFormatters.formatDuration(media.duration))
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
        }
        .task(id: media.file.fileId) {
            if let thumb = media.thumbnail, thumb.format.isStaticImage {
                appStore.fileCache.ensureDownloaded(thumb.file, priority: 20)
            }
            if media.file.expectedSize == 0 || media.file.expectedSize <= 12 * 1024 * 1024 {
                appStore.fileCache.ensureDownloaded(media.file, priority: 20)
            }
        }
        .onDisappear {
            isPlayingWithSound = false
        }
    }
}
