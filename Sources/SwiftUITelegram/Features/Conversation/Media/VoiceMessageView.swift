import SwiftUI

struct VoiceMessageView: View {
    @Environment(AppStore.self) private var appStore

    let messageId: Int64
    let isOutgoing: Bool
    let media: VoiceNoteMedia
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

    var body: some View {
        let state = transferState

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                playOrTransferButton(state: state)

                VStack(alignment: .leading, spacing: 5) {
                    waveformScrubber(state: state)

                    HStack(spacing: 6) {
                        Text(durationLabel)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(metaColor)

                        if !isOutgoing && !media.isListened {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 6, height: 6)
                        }

                        if state.isUploading {
                            Text("上传中 \(Int((state.uploadProgress * 100).rounded()))%")
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(metaColor)
                        } else if state.isDownloading {
                            Text("下载中 \(Int((state.downloadProgress * 100).rounded()))%")
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(metaColor)
                        }

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
                                    .padding(.vertical, 2)
                                    .background(
                                        isOutgoing ? Color.white.opacity(0.22) : Color.accentColor.opacity(0.14),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("切换倍速 (1x / 1.5x / 2x)")
                        }
                    }
                }
            }
            .frame(minWidth: 230, maxWidth: 310)

            if !media.caption.isEmpty {
                Text(media.caption)
                    .font(.body)
                    .foregroundStyle(primaryTextColor)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: transferState.localPath) { _, newPath in
            if appStore.audioPlayer.pendingAutoPlayMessageId == messageId,
               let newPath, !newPath.isEmpty
            {
                startOrTogglePlayback(path: newPath)
            }
        }
    }

    private func playOrTransferButton(state: FileTransferState) -> some View {
        Button {
            if state.isDownloaded, let path = state.localPath {
                startOrTogglePlayback(path: path)
            } else if state.isDownloading {
                if appStore.audioPlayer.pendingAutoPlayMessageId == messageId {
                    appStore.audioPlayer.pendingAutoPlayMessageId = nil
                }
                appStore.fileCache.cancelDownload(fileId: media.file.fileId)
            } else if !state.isUploading {
                appStore.audioPlayer.pendingAutoPlayMessageId = messageId
                appStore.fileCache.startDownload(fileId: media.file.fileId, priority: 30)
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isOutgoing ? Color.white.opacity(0.22) : Color.accentColor)
                    .frame(width: 40, height: 40)

                if state.isUploading {
                    CircularProgressRing(progress: state.uploadProgress, lineWidth: 2.5)
                        .frame(width: 32, height: 32)
                    Image(systemName: "arrow.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else if state.isDownloading {
                    CircularProgressRing(progress: state.downloadProgress, lineWidth: 2.5)
                        .frame(width: 32, height: 32)
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
        .help(isPlaying ? "暂停" : "播放语音消息")
    }

    private func waveformScrubber(state: FileTransferState) -> some View {
        let bars = media.waveformLevels.isEmpty ? Array(repeating: Float(0.3), count: 32) : media.waveformLevels
        let playedColor: Color = isOutgoing ? .white : .accentColor
        let unplayedColor: Color = isOutgoing ? .white.opacity(0.35) : .secondary.opacity(0.35)

        return GeometryReader { proxy in
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(bars.enumerated()), id: \.offset) { index, level in
                    let barPosition = Double(index + 1) / Double(max(bars.count, 1))
                    let isFilled = isActive && barPosition <= playbackProgress
                    let barHeight = max(4, CGFloat(level) * 24)

                    Capsule()
                        .fill(isFilled ? playedColor : unplayedColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: barHeight)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let width = max(proxy.size.width, 1)
                        let fraction = min(1.0, max(0.0, Double(value.location.x / width)))
                        if isActive {
                            appStore.audioPlayer.seek(toFraction: fraction, for: messageId)
                        } else if state.isDownloaded, let path = state.localPath {
                            startOrTogglePlayback(path: path)
                            appStore.audioPlayer.seek(toFraction: fraction, for: messageId)
                        }
                    }
            )
        }
        .frame(height: 26)
    }

    private func startOrTogglePlayback(path: String) {
        appStore.audioPlayer.togglePlayback(
            messageId: messageId,
            filePath: path,
            fallbackDuration: media.duration,
            onStarted: {
                if !isOutgoing && !media.isListened {
                    appStore.conversation.markMessageContentOpened(messageId: messageId)
                }
            }
        )
    }

    private var durationLabel: String {
        if isActive {
            let current = MediaFormatters.formatDuration(appStore.audioPlayer.currentTime(for: messageId))
            let total = MediaFormatters.formatDuration(max(appStore.audioPlayer.duration, TimeInterval(media.duration)))
            return "\(current) / \(total)"
        }
        return MediaFormatters.formatDuration(media.duration)
    }

    private var rateLabel: String {
        let rate = appStore.audioPlayer.playbackRate
        if abs(rate - 1.5) < 0.05 { return "1.5x" }
        if abs(rate - 2.0) < 0.05 { return "2x" }
        return "1x"
    }
}
