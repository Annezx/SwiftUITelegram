import AppKit
import SwiftUI

struct StickerMessageView: View {
    @Environment(AppStore.self) private var appStore

    let media: StickerMedia

    private var displaySize: CGSize {
        let w = CGFloat(max(media.width, 160))
        let h = CGFloat(max(media.height, 160))
        let maxSide: CGFloat = 176
        let scale = min(maxSide / w, maxSide / h)
        return CGSize(width: max(88, (w * scale).rounded()), height: max(88, (h * scale).rounded()))
    }

    private var stickerImage: NSImage? {
        if media.format == .webp, let full = appStore.fileCache.image(for: media.file) {
            return full
        }
        if let thumb = media.thumbnail, thumb.format.isStaticImage,
           let thumbImg = appStore.fileCache.image(for: thumb.file)
        {
            return thumbImg
        }
        return nil
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = stickerImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: displaySize.width, height: displaySize.height)
            } else {
                VStack(spacing: 4) {
                    Text(media.emoji.isEmpty ? "🙂" : media.emoji)
                        .font(.system(size: 64))
                    if let badge = media.format.badgeLabel {
                        Text(badge)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 120, height: 120)
            }

            if stickerImage != nil, let badge = media.format.badgeLabel {
                Text(badge)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.48), in: Capsule())
                    .padding(4)
            }
        }
        .task(id: media.file.fileId) {
            if media.format == .webp {
                appStore.fileCache.ensureDownloaded(media.file, priority: 20)
            }
            if let thumb = media.thumbnail, thumb.format.isStaticImage {
                appStore.fileCache.ensureDownloaded(thumb.file, priority: 22)
            }
        }
    }
}
