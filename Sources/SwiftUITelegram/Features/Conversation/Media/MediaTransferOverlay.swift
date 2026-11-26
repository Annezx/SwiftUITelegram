import AppKit
import SwiftUI

/// Reusable circular progress ring used across photo, video, document, and audio transfer badges.
struct CircularProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 2.5
    var trackColor: Color = .white.opacity(0.28)
    var fillColor: Color = .white

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(0.06, min(1.0, progress)))
                .stroke(
                    fillColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.12), value: progress)
        }
    }
}

/// Frosted circular action/progress overlay for media cards (download / cancel / upload / play).
struct MediaTransferButton: View {
    let state: FileTransferState
    var readySystemImage: String? = nil
    var size: CGFloat = 46
    let onStartDownload: () -> Void
    let onCancelDownload: () -> Void
    var onReadyAction: (() -> Void)? = nil

    var body: some View {
        if state.isUploading {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.55))
                CircularProgressRing(progress: state.uploadProgress)
                    .padding(4)
                Image(systemName: "arrow.up")
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
        } else if state.isDownloading {
            Button(action: onCancelDownload) {
                ZStack {
                    Circle()
                        .fill(.black.opacity(0.58))
                    CircularProgressRing(progress: state.downloadProgress)
                        .padding(4)
                    Image(systemName: "xmark")
                        .font(.system(size: size * 0.30, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
            }
            .buttonStyle(.plain)
            .help("取消下载")
        } else if !state.isDownloaded {
            Button(action: onStartDownload) {
                ZStack {
                    Circle()
                        .fill(.black.opacity(0.58))
                    Image(systemName: "arrow.down")
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
            }
            .buttonStyle(.plain)
            .help("下载媒体")
        } else if let readySystemImage {
            Button {
                onReadyAction?()
            } label: {
                ZStack {
                    Circle()
                        .fill(.black.opacity(0.56))
                    Image(systemName: readySystemImage)
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: readySystemImage == "play.fill" ? 1.5 : 0)
                }
                .frame(width: size, height: size)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Interactive spoiler cover matching Telegram's tap-to-reveal media spoiler behavior.
struct MediaSpoilerOverlay: View {
    let onReveal: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            VStack(spacing: 6) {
                Image(systemName: "eye.slash.fill")
                    .font(.title3)
                Text("点击查看剧透内容")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(0.45), in: Capsule())
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onReveal)
    }
}

/// Blurred instant placeholder rendered from Telegram's tiny embedded JPEG minithumbnail.
struct MinithumbnailBackdrop: View {
    @Environment(AppStore.self) private var appStore
    let minithumbnailData: Data?

    var body: some View {
        if let mini = appStore.fileCache.minithumbnailImage(for: minithumbnailData) {
            Image(nsImage: mini)
                .resizable()
                .scaledToFill()
                .blur(radius: 10)
        } else {
            Rectangle()
                .fill(.quaternary.opacity(0.55))
        }
    }
}

/// Helper for computing balanced visual media bubble dimensions on desktop.
enum MediaBubbleSizing {
    static func fitSize(
        width: Int,
        height: Int,
        maxWidth: CGFloat = 340,
        maxHeight: CGFloat = 360,
        minWidth: CGFloat = 170,
        minHeight: CGFloat = 110
    ) -> CGSize {
        let w = CGFloat(max(width, 1))
        let h = CGFloat(max(height, 1))
        let aspect = w / h

        var targetW = min(maxWidth, max(minWidth, w))
        var targetH = targetW / max(aspect, 0.35)

        if targetH > maxHeight {
            targetH = maxHeight
            targetW = min(maxWidth, max(minWidth, targetH * aspect))
        } else if targetH < minHeight {
            targetH = minHeight
            targetW = min(maxWidth, max(minWidth, targetH * aspect))
        }

        return CGSize(width: targetW.rounded(), height: targetH.rounded())
    }
}
