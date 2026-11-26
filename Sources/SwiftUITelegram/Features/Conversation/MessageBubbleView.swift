import AppKit
import SwiftUI

struct MessageBubbleView: View {
    @Environment(AppStore.self) private var appStore

    let entry: ConversationTimelineEntry
    let senderName: String?
    let isReadByRecipient: Bool
    let onOpenLightbox: (Int64) -> Void
    let onQuickLook: (URL) -> Void

    private var leadMessage: MessageItem {
        entry.leadMessage
    }

    private var tailMessage: MessageItem {
        entry.tailMessage
    }

    private var isOutgoing: Bool {
        leadMessage.isOutgoing
    }

    private var isBorderless: Bool {
        if case .single(let message) = entry {
            return message.content.isBorderlessStyle
        }
        return false
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isOutgoing {
                Spacer(minLength: 72)
            }

            if isBorderless {
                borderlessContent
            } else {
                standardBubble
            }

            if !isOutgoing {
                Spacer(minLength: 72)
            }
        }
    }

    private var standardBubble: some View {
        Grid(alignment: .leading, verticalSpacing: 4) {
            if let senderName, !senderName.isEmpty {
                GridRow {
                    Text(senderName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isOutgoing ? Color.white.opacity(0.9) : Color.accentColor)
                }
            }

            GridRow {
                contentBody
            }

            GridRow {
                metadataRow(textColor: metaColor)
                    .gridCellAnchor(.trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isOutgoing ? Color.clear : Color(nsColor: .separatorColor).opacity(0.45),
                    lineWidth: 0.5
                )
        )
        .frame(maxWidth: 520, alignment: isOutgoing ? .trailing : .leading)
        .contextMenu {
            contextMenuItems
        }
    }

    private var borderlessContent: some View {
        VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
            if let senderName, !senderName.isEmpty {
                Text(senderName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.regularMaterial, in: Capsule())
            }

            contentBody

            metadataRow(textColor: .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.regularMaterial, in: Capsule())
        }
        .contextMenu {
            contextMenuItems
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        switch entry {
        case .album(_, let messages):
            MediaAlbumView(
                messages: messages,
                primaryTextColor: primaryTextColor,
                onOpenLightbox: onOpenLightbox
            )

        case .single(let message):
            singleMessageContent(message)
        }
    }

    @ViewBuilder
    private func singleMessageContent(_ message: MessageItem) -> some View {
        switch message.content {
        case .text(let text):
            Text(text)
                .font(.body)
                .foregroundStyle(primaryTextColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

        case .photo(let media):
            PhotoMessageView(
                messageId: message.id,
                media: media,
                primaryTextColor: primaryTextColor,
                onOpenLightbox: { onOpenLightbox(message.id) }
            )

        case .video(let media):
            VideoMessageView(
                messageId: message.id,
                media: media,
                primaryTextColor: primaryTextColor,
                onOpenLightbox: { onOpenLightbox(message.id) }
            )

        case .videoNote(let media):
            VideoNoteMessageView(
                messageId: message.id,
                isOutgoing: message.isOutgoing,
                media: media
            )

        case .animation(let media):
            AnimationMessageView(
                messageId: message.id,
                media: media,
                primaryTextColor: primaryTextColor,
                onOpenLightbox: { onOpenLightbox(message.id) }
            )

        case .document(let media):
            DocumentMessageView(
                media: media,
                isOutgoing: message.isOutgoing,
                primaryTextColor: primaryTextColor,
                metaColor: metaColor,
                onPreviewFile: onQuickLook
            )

        case .voice(let media):
            VoiceMessageView(
                messageId: message.id,
                isOutgoing: message.isOutgoing,
                media: media,
                primaryTextColor: primaryTextColor,
                metaColor: metaColor
            )

        case .audio(let media):
            AudioMessageView(
                messageId: message.id,
                isOutgoing: message.isOutgoing,
                media: media,
                primaryTextColor: primaryTextColor,
                metaColor: metaColor
            )

        case .sticker(let media):
            StickerMessageView(media: media)

        case .location(let location):
            locationCard(location)

        case .contact(let contact):
            contactCard(contact)

        case .unsupported(let label):
            Label(label, systemImage: "questionmark.circle")
                .font(.callout)
                .foregroundStyle(metaColor)
        }
    }

    private func locationCard(_ location: LocationMedia) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isOutgoing ? Color.white.opacity(0.22) : Color.red.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: "mappin.and.ellipse")
                    .font(.title3)
                    .foregroundStyle(isOutgoing ? Color.white : Color.red)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("位置分享")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(primaryTextColor)
                Text(String(format: "%.5f, %.5f", location.latitude, location.longitude))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(metaColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            openLocationInMaps(location)
        }
    }

    private func contactCard(_ contact: ContactMedia) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isOutgoing ? Color.white.opacity(0.22) : Color.accentColor.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isOutgoing ? Color.white : Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(primaryTextColor)
                if !contact.phoneNumber.isEmpty {
                    Text(contact.phoneNumber)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(metaColor)
                }
            }
        }
    }

    private func metadataRow(textColor: Color) -> some View {
        HStack(spacing: 4) {
            if tailMessage.editDate != nil {
                Text("已编辑")
                    .font(.caption2)
                    .foregroundStyle(textColor)
            }

            Text(Self.timeFormatter.string(from: tailMessage.date))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(textColor)

            if isOutgoing {
                statusIcon(color: textColor)
            }
        }
    }

    @ViewBuilder
    private func statusIcon(color: Color) -> some View {
        switch tailMessage.deliveryStatus {
        case .pending:
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundStyle(color)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.yellow)
        case .sent:
            Image(systemName: isReadByRecipient ? "checkmark.circle.fill" : "checkmark")
                .font(.caption2)
                .foregroundStyle(color)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        if let copyable = copyableText {
            Button("复制文本") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(copyable, forType: .string)
            }
        }

        if case .single(let message) = entry {
            singleMediaContextItems(for: message)
        } else if case .album(_, let messages) = entry, let first = messages.first {
            Button("查看相册 (\(messages.count) 项)") {
                onOpenLightbox(first.id)
            }
        }
    }

    @ViewBuilder
    private func singleMediaContextItems(for message: MessageItem) -> some View {
        switch message.content {
        case .photo(let media):
            let state = appStore.fileCache.state(for: media.file)
            if state.isDownloaded, let path = state.localPath {
                Button("查看大图") { onOpenLightbox(message.id) }
                Button("复制图片") { MediaFileActions.copyImageToPasteboard(from: path) }
                Button("Quick Look 预览") {
                    onQuickLook(MediaFileActions.quickLookURL(for: path, preferredFileName: "photo_\(message.id).jpg", mimeType: "image/jpeg"))
                }
                Button("另存为…") {
                    MediaFileActions.saveFile(from: path, suggestedFileName: "photo_\(message.id).jpg", mimeType: "image/jpeg")
                }
                Button("在 Finder 中显示") { MediaFileActions.revealInFinder(localPath: path) }
            } else {
                downloadToggleButton(for: media.file, state: state)
            }

        case .video(let media):
            let state = appStore.fileCache.state(for: media.file)
            if state.isDownloaded, let path = state.localPath {
                let name = media.fileName.isEmpty ? "video_\(message.id).mp4" : media.fileName
                Button("播放视频") { onOpenLightbox(message.id) }
                Button("Quick Look 预览") {
                    onQuickLook(MediaFileActions.quickLookURL(for: path, preferredFileName: name, mimeType: media.mimeType))
                }
                Button("使用默认应用打开") {
                    MediaFileActions.openExternally(localPath: path, preferredFileName: name, mimeType: media.mimeType)
                }
                Button("另存为…") {
                    MediaFileActions.saveFile(from: path, suggestedFileName: name, mimeType: media.mimeType)
                }
                Button("在 Finder 中显示") { MediaFileActions.revealInFinder(localPath: path) }
            } else {
                downloadToggleButton(for: media.file, state: state)
            }

        case .videoNote(let media):
            let state = appStore.fileCache.state(for: media.file)
            if state.isDownloaded, let path = state.localPath {
                let name = "video_note_\(message.id).mp4"
                Button("另存为…") {
                    MediaFileActions.saveFile(from: path, suggestedFileName: name, mimeType: "video/mp4")
                }
                Button("在 Finder 中显示") { MediaFileActions.revealInFinder(localPath: path) }
            } else {
                downloadToggleButton(for: media.file, state: state)
            }

        case .animation(let media):
            let state = appStore.fileCache.state(for: media.file)
            if state.isDownloaded, let path = state.localPath {
                let name = media.fileName.isEmpty ? (media.isGIFImage ? "animation_\(message.id).gif" : "animation_\(message.id).mp4") : media.fileName
                Button("查看大图") { onOpenLightbox(message.id) }
                Button("另存为…") {
                    MediaFileActions.saveFile(from: path, suggestedFileName: name, mimeType: media.mimeType)
                }
                Button("在 Finder 中显示") { MediaFileActions.revealInFinder(localPath: path) }
            } else {
                downloadToggleButton(for: media.file, state: state)
            }

        case .document(let media):
            let state = appStore.fileCache.state(for: media.file)
            if state.isDownloaded, let path = state.localPath {
                Button("Quick Look 预览") {
                    onQuickLook(MediaFileActions.quickLookURL(for: path, preferredFileName: media.fileName, mimeType: media.mimeType))
                }
                Button("使用默认应用打开") {
                    MediaFileActions.openExternally(localPath: path, preferredFileName: media.fileName, mimeType: media.mimeType)
                }
                Button("另存为…") {
                    MediaFileActions.saveFile(from: path, suggestedFileName: media.fileName, mimeType: media.mimeType)
                }
                Button("在 Finder 中显示") { MediaFileActions.revealInFinder(localPath: path) }
            } else {
                downloadToggleButton(for: media.file, state: state)
            }

        case .audio(let media):
            let state = appStore.fileCache.state(for: media.file)
            if state.isDownloaded, let path = state.localPath {
                let name = media.fileName.isEmpty ? "\(media.displayTitle).mp3" : media.fileName
                Button("另存为…") {
                    MediaFileActions.saveFile(from: path, suggestedFileName: name, mimeType: media.mimeType)
                }
                Button("在 Finder 中显示") { MediaFileActions.revealInFinder(localPath: path) }
            } else {
                downloadToggleButton(for: media.file, state: state)
            }

        case .voice(let media):
            let state = appStore.fileCache.state(for: media.file)
            if state.isDownloaded, let path = state.localPath {
                Button("另存为…") {
                    MediaFileActions.saveFile(from: path, suggestedFileName: "voice_\(message.id).ogg", mimeType: media.mimeType)
                }
                Button("在 Finder 中显示") { MediaFileActions.revealInFinder(localPath: path) }
            } else {
                downloadToggleButton(for: media.file, state: state)
            }

        case .location(let location):
            Button("在 Apple 地图中打开") { openLocationInMaps(location) }

        case .contact(let contact):
            if !contact.phoneNumber.isEmpty {
                Button("复制手机号") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(contact.phoneNumber, forType: .string)
                }
            }

        case .text, .sticker, .unsupported:
            EmptyView()
        }
    }

    @ViewBuilder
    private func downloadToggleButton(for descriptor: MediaFileDescriptor, state: FileTransferState) -> some View {
        if state.isDownloading {
            Button("取消下载") {
                appStore.fileCache.cancelDownload(fileId: descriptor.fileId)
            }
        } else if !state.isUploading {
            Button("下载文件") {
                appStore.fileCache.startDownload(fileId: descriptor.fileId, priority: 28)
            }
        }
    }

    private func openLocationInMaps(_ location: LocationMedia) {
        let urlString = "https://maps.apple.com/?ll=\(location.latitude),\(location.longitude)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Styling Helpers

    private var bubbleBackground: Color {
        isOutgoing ? Color.accentColor : Color(nsColor: .controlBackgroundColor)
    }

    private var primaryTextColor: Color {
        isOutgoing ? .white : .primary
    }

    private var metaColor: Color {
        isOutgoing ? .white.opacity(0.78) : .secondary
    }

    private var copyableText: String? {
        switch entry {
        case .single(let message):
            switch message.content {
            case .text(let text):
                return text
            default:
                let caption = message.content.captionText
                return caption.isEmpty ? nil : caption
            }
        case .album(_, let messages):
            let caption = messages.first(where: { !$0.content.captionText.isEmpty })?.content.captionText ?? ""
            return caption.isEmpty ? nil : caption
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
