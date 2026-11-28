import SwiftUI

/// Compact horizontal bar displayed above the message composer when the user enters
/// a single emoji, offering instant one-click sticker suggestions matching that emoji.
struct StickerSuggestionStrip: View {
    let emoji: String
    let stickers: [StickerItem]
    let onSendSticker: (StickerItem) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(emoji)
                .font(.title3)
                .padding(.leading, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(stickers) { sticker in
                        SuggestedStickerChip(sticker: sticker) {
                            onSendSticker(sticker)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("隐藏贴纸建议")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

private struct SuggestedStickerChip: View {
    let sticker: StickerItem
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onTap) {
            AnimatedStickerSurfaceView(
                sticker: sticker,
                size: CGSize(width: 52, height: 52),
                isPlaying: isHovered,
                firstFrameOnly: !isHovered,
                maxPixelSize: 120,
                downloadPriority: 18
            )
            .padding(3)
            .background(
                isHovered ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.03),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .scaleEffect(isHovered ? 1.07 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("点击发送推荐贴纸")
    }
}
