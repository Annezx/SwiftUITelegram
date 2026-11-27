import AppKit
import SwiftUI

/// Renders a Telegram media album (2–10 grouped photos/videos sharing a `mediaAlbumId`)
/// in a clean responsive mosaic grid inside a single message bubble.
struct MediaAlbumView: View {
    @Environment(AppStore.self) private var appStore

    let messages: [MessageItem]
    let isOutgoing: Bool
    let primaryTextColor: Color
    let onOpenLightbox: (Int64) -> Void

    private let gridWidth: CGFloat = 340
    private let spacing: CGFloat = 3

    private var sharedFormattedCaption: FormattedTextContent {
        messages.first(where: { !$0.content.formattedCaption.isEmpty })?.content.formattedCaption ?? .empty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            albumGrid
                .frame(width: gridWidth)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if !sharedFormattedCaption.isEmpty {
                FormattedTextView(
                    content: sharedFormattedCaption,
                    isOutgoing: isOutgoing
                )
                .frame(maxWidth: gridWidth, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var albumGrid: some View {
        switch messages.count {
        case 2:
            HStack(spacing: spacing) {
                tile(for: messages[0], width: (gridWidth - spacing) / 2, height: 190)
                tile(for: messages[1], width: (gridWidth - spacing) / 2, height: 190)
            }

        case 3:
            let leftW = (gridWidth - spacing) * 0.58
            let rightW = gridWidth - spacing - leftW
            let rightH = (240 - spacing) / 2
            HStack(spacing: spacing) {
                tile(for: messages[0], width: leftW, height: 240)
                VStack(spacing: spacing) {
                    tile(for: messages[1], width: rightW, height: rightH)
                    tile(for: messages[2], width: rightW, height: rightH)
                }
            }

        case 4:
            let tileW = (gridWidth - spacing) / 2
            VStack(spacing: spacing) {
                HStack(spacing: spacing) {
                    tile(for: messages[0], width: tileW, height: 150)
                    tile(for: messages[1], width: tileW, height: 150)
                }
                HStack(spacing: spacing) {
                    tile(for: messages[2], width: tileW, height: 150)
                    tile(for: messages[3], width: tileW, height: 150)
                }
            }

        default:
            let topCount = messages.count % 3 == 1 ? 2 : (messages.count == 5 ? 2 : 3)
            let topSlice = Array(messages.prefix(topCount))
            let remaining = Array(messages.dropFirst(topCount))
            let rows = chunked(remaining, size: 3)

            VStack(spacing: spacing) {
                rowView(topSlice, height: topCount == 2 ? 150 : 114)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    rowView(row, height: row.count == 2 ? 140 : 112)
                }
            }
        }
    }

    private func rowView(_ row: [MessageItem], height: CGFloat) -> some View {
        let count = CGFloat(max(row.count, 1))
        let tileW = (gridWidth - spacing * (count - 1)) / count
        return HStack(spacing: spacing) {
            ForEach(row) { item in
                tile(for: item, width: tileW, height: height)
            }
        }
    }

    @ViewBuilder
    private func tile(for message: MessageItem, width: CGFloat, height: CGFloat) -> some View {
        AlbumMediaTileView(
            message: message,
            width: width,
            height: height,
            onTap: { onOpenLightbox(message.id) }
        )
    }

    private func chunked(_ items: [MessageItem], size: Int) -> [[MessageItem]] {
        guard size > 0 else { return [items] }
        var result: [[MessageItem]] = []
        var idx = 0
        while idx < items.count {
            let end = min(idx + size, items.count)
            result.append(Array(items[idx..<end]))
            idx = end
        }
        return result
    }
}

private struct AlbumMediaTileView: View {
    @Environment(AppStore.self) private var appStore

    let message: MessageItem
    let width: CGFloat
    let height: CGFloat
    let onTap: () -> Void

    @State private var isSpoilerRevealed: Bool = false

    var body: some View {
        switch message.content {
        case .photo(let photo):
            photoTile(photo)
        case .video(let video):
            videoTile(video)
        default:
            Rectangle()
                .fill(.quaternary)
                .frame(width: width, height: height)
        }
    }

    private func photoTile(_ photo: PhotoMedia) -> some View {
        let full = appStore.fileCache.image(for: photo.file)
        let preview = photo.previewFile.flatMap { appStore.fileCache.image(for: $0) }
        let state = appStore.fileCache.state(for: photo.file)

        return ZStack {
            if let img = full ?? preview {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                MinithumbnailBackdrop(minithumbnailData: photo.minithumbnailData)
            }

            if state.isUploading || (full == nil && state.isDownloading) {
                MediaTransferButton(
                    state: state,
                    size: 34,
                    onStartDownload: {
                        appStore.fileCache.startDownload(fileId: photo.file.fileId, priority: 24)
                    },
                    onCancelDownload: {
                        appStore.fileCache.cancelDownload(fileId: photo.file.fileId)
                    }
                )
            }

            if photo.hasSpoiler && !isSpoilerRevealed {
                MediaSpoilerOverlay {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSpoilerRevealed = true
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            if photo.hasSpoiler && !isSpoilerRevealed {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSpoilerRevealed = true
                }
                return
            }
            onTap()
        }
        .task(id: photo.file.fileId) {
            if let previewFile = photo.previewFile {
                appStore.fileCache.ensureDownloaded(previewFile, priority: 20)
            }
            appStore.fileCache.ensureDownloaded(photo.file, priority: 22)
        }
    }

    private func videoTile(_ video: VideoMedia) -> some View {
        let thumb = video.thumbnail.flatMap { info -> NSImage? in
            info.format.isStaticImage ? appStore.fileCache.image(for: info.file) : nil
        }
        let state = appStore.fileCache.state(for: video.file)

        return ZStack {
            if let thumb {
                Image(nsImage: thumb)
                    .resizable()
                    .scaledToFill()
            } else {
                MinithumbnailBackdrop(minithumbnailData: video.minithumbnailData)
            }

            Rectangle().fill(.black.opacity(0.2))

            MediaTransferButton(
                state: state,
                readySystemImage: "play.fill",
                size: 38,
                onStartDownload: {},
                onCancelDownload: {}
            )
            .allowsHitTesting(false)

            VStack {
                HStack {
                    Text(MediaFormatters.formatDuration(video.duration))
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: Capsule())
                    Spacer()
                }
                Spacer()
            }
            .padding(6)

            if video.hasSpoiler && !isSpoilerRevealed {
                MediaSpoilerOverlay {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSpoilerRevealed = true
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            if video.hasSpoiler && !isSpoilerRevealed {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSpoilerRevealed = true
                }
                return
            }
            if state.isDownloaded {
                onTap()
            } else if state.isDownloading {
                appStore.fileCache.cancelDownload(fileId: video.file.fileId)
            } else {
                appStore.fileCache.startDownload(fileId: video.file.fileId, priority: 26)
            }
        }
        .task(id: video.thumbnail?.file.fileId) {
            if let info = video.thumbnail, info.format.isStaticImage {
                appStore.fileCache.ensureDownloaded(info.file, priority: 20)
            }
        }
    }
}
