import AppKit
import SwiftUI

struct StickerMessageView: View {
    let media: StickerMedia
    var onOpenStickerPack: ((Int64) -> Void)? = nil

    @State private var replayTrigger: Int = 0
    @State private var isPressed: Bool = false

    private var displaySize: CGSize {
        let w = CGFloat(max(media.width, 160))
        let h = CGFloat(max(media.height, 160))
        let maxSide: CGFloat = media.isAnimatedEmoji ? 148 : 176
        let scale = min(maxSide / w, maxSide / h)
        return CGSize(
            width: max(88, (w * scale).rounded()),
            height: max(88, (h * scale).rounded())
        )
    }

    var body: some View {
        AnimatedStickerSurfaceView(
            media: media,
            size: displaySize,
            isPlaying: true,
            firstFrameOnly: false,
            replayTrigger: replayTrigger,
            maxPixelSize: 288,
            downloadPriority: 22,
            allowWebKitFallback: true,
            showDownloadSpinner: true
        )
        .scaleEffect(isPressed ? 0.94 : 1.0)
        .animation(.spring(response: 0.24, dampingFraction: 0.65), value: isPressed)
        .contentShape(Rectangle())
        .onTapGesture {
            if !media.isAnimatedEmoji, media.setId != 0, let onOpenStickerPack {
                onOpenStickerPack(media.setId)
            } else {
                replayTrigger += 1
                isPressed = true
                Task {
                    try? await Task.sleep(for: .milliseconds(140))
                    isPressed = false
                }
            }
        }
        .help(tooltipText)
    }

    private var tooltipText: String {
        if !media.isAnimatedEmoji, media.setId != 0 {
            return "点击查看贴纸包"
        }
        if media.format.isAnimated {
            return "点击重新播放动画"
        }
        return media.emoji.isEmpty ? "贴纸" : media.emoji
    }
}
