import AppKit
import SwiftUI

struct AudioMessageView: View {
    @Environment(AppStore.self) private var appStore

    let messageId: Int64
    let isOutgoing: Bool
    let media: AudioMedia
    let primaryTextColor: Color
    let metaColor: Color

    private var transferState: FileTransferState {
        appStore.fileCache.state(for: media.file)
    }

    private var isActive: Bool {
        appStore.audioPlayer.isActive(messageId: messageId)
    }

    private var isPlaying: Bool {
        appStore.audioPlayer.isPlaying(messageId: messageId)
    }

    private var playbackProgress: Double {
        appStore.audioPlayer.progress(for: messageId)
    }

    private var coverImage: NSImage? {
        if let thumb = media.albumCoverThumbnail, thumb.format.isStaticImage,
           let img = appStore.fileCache.image(for: thumb.file)
        {
            return img
        }
        return appStore.fileCache.minithumbnailImage(for: media.albumCoverMinithumbnailData)
    }

    var body: some View {
        let state = transferState

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 11) {
                coverPlayButton(state: state)

                VStack(alignment: .leading, spacing: 4) {
                    Text(media.displayTitle)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(1)

                    Text(media.displayPerformer)
                        .font(.caption)
                        .foregroundStyle(metaColor)
                        .lineLimit(1)

                    if isActive {
                        scrubberBar
                    }

                    HStack(spacing: 6) {
                        Text(subtitleText(state: state))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(metaColor)

                        Spacer(minLength: 4)

                        if isActive {
                            Button {
                                appStore.audioPlayer.cyclePlaybackRate()
                            } label: {
                                Text(rateLabel)
                                    .font(.caption2.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(isOutgoing ? Color.white : Color.accentColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(
                                        isOutgoing ? Color.white.opacity(0.22) : Color.accentColor.opacity(0.14),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(minWidth: 245, maxWidth: 340, alignment: .leading)

            if !media.caption.isEmpty {
                Text(media.caption)
                    .font(.body)
                    .foregroundStyle(primaryTextColor)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: media.albumCoverThumbnail?.file.fileId) {
            if let thumb = media.albumCoverThumbnail, thumb.format.isStaticImage {
                appStore.fileCache.ensureDownloaded(thumb.file, priority: 14)
            }
        }
        .onChange(of: transferState.localPath) { _, newPath in
            if appStore.audioPlayer.pendingAutoPlayMessageId == messageId,
               let newPath, !newPath.isEmpty
            {
                appStore.audioPlayer.togglePlayback(
                    messageId: messageId,
                    filePath: newPath,
                    fallbackDuration: media.duration
                )
            }
        }
    }

    private func coverPlayButton(state: FileTransferState) -> some View {
        Button {
            if state.isDownloaded, let path = state.localPath {
                appStore.audioPlayer.togglePlayback(
                    messageId: messageId,
                    filePath: path,
                    fallbackDuration: media.duration
                )
            } else if state.isDownloading {
                if appStore.audioPlayer.pendingAutoPlayMessageId == messageId {
                    appStore.audioPlayer.pendingAutoPlayMessageId = nil
                }
                appStore.fileCache.cancelDownload(fileId: media.file.fileId)
            } else if !state.isUploading {
                appStore.audioPlayer.pendingAutoPlayMessageId = messageId
                appStore.fileCache.startDownload(fileId: media.file.fileId, priority: 28)
            }
        } label: {
            ZStack {
                if let coverImage {
                    Image(nsImage: coverImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 46, height: 46)
                        .clipShape(Circle())
                    Circle()
                        .fill(.black.opacity(0.42))
                        .frame(width: 46, height: 46)
                } else {
                    Circle()
                        .fill(isOutgoing ? Color.white.opacity(0.22) : Color.purple.opacity(0.85))
                        .frame(width: 46, height: 46)
                }

                if state.isUploading {
                    CircularProgressRing(progress: state.uploadProgress, lineWidth: 2.5)
                        .frame(width: 38, height: 38)
                    Image(systemName: "arrow.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else if state.isDownloading {
                    CircularProgressRing(progress: state.downloadProgress, lineWidth: 2.5)
                        .frame(width: 38, height: 38)
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                } else if !state.isDownloaded {
                    Image(systemName: "arrow.down")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .offset(x: isPlaying ? 0 : 1)
                }
            }
        }
        .buttonStyle(.plain)
        .help(isPlaying ? "暂停音频" : "播放音频")
    }

    private var scrubberBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isOutgoing ? Color.white.opacity(0.3) : Color.secondary.opacity(0.25))
                    .frame(height: 4)

                Capsule()
                    .fill(isOutgoing ? Color.white : Color.accentColor)
                    .frame(width: max(4, proxy.size.width * playbackProgress), height: 4)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let fraction = Double(value.location.x / max(proxy.size.width, 1))
                        appStore.audioPlayer.seek(toFraction: fraction, for: messageId)
                    }
            )
        }
        .frame(height: 12)
    }

    private func subtitleText(state: FileTransferState) -> String {
        if isActive {
            let current = MediaFormatters.formatDuration(appStore.audioPlayer.currentTime(for: messageId))
            let total = MediaFormatters.formatDuration(max(appStore.audioPlayer.duration, TimeInterval(media.duration)))
            return "\(current) / \(total)"
        }
        let durationStr = MediaFormatters.formatDuration(media.duration)
        let sizeStr = MediaFormatters.formatFileSize(state.expectedSize)
        if state.isUploading {
            return "正在上传 \(Int((state.uploadProgress * 100).rounded()))%"
        }
        if state.isDownloading {
            return "正在下载 \(Int((state.downloadProgress * 100).rounded()))%"
        }
        return sizeStr.isEmpty ? durationStr : "\(durationStr) · \(sizeStr)"
    }

    private var rateLabel: String {
        let rate = appStore.audioPlayer.playbackRate
        if abs(rate - 1.5) < 0.05 { return "1.5x" }
        if abs(rate - 2.0) < 0.05 { return "2x" }
        return "1x"
    }
}
