import AppKit
import SwiftUI

struct MessageBubbleView: View {
    @Environment(AppStore.self) private var appStore

    let entry: ConversationTimelineEntry
    let senderName: String?
    let senderNameColor: Color
    let showAvatarColumn: Bool
    let senderAvatar: SenderAvatarInfo?
    let isReadByRecipient: Bool
    let isHighlighted: Bool
    let isSelectionMode: Bool
    let isSelected: Bool
    let inFlightCallbackButtonKey: String?
    let onOpenLightbox: (Int64) -> Void
    let onQuickLook: (URL) -> Void
    let onToggleSelect: () -> Void
    let onReply: (MessageItem) -> Void
    let onEdit: (MessageItem) -> Void
    let onForward: ([MessageItem]) -> Void
    let onDelete: ([MessageItem]) -> Void
    let onTogglePin: (MessageItem) -> Void
    let onCopyLink: () -> Void
    let onEnterSelectionMode: () -> Void
    let onJumpToMessage: (Int64) -> Void
    let onTapSenderAvatar: ((Int64) -> Void)?
    let onTapInlineButton: (InlineKeyboardButtonItem, MessageItem) -> Void
    let onOpenStickerPack: (Int64) -> Void

    @State private var isHovering: Bool = false

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

    private var canReply: Bool {
        appStore.conversation.canReply(to: entry)
    }

    private var canEdit: Bool {
        appStore.conversation.canEdit(entry)
    }

    private var canForward: Bool {
        appStore.conversation.canForward(entry)
    }

    private var canDelete: Bool {
        appStore.conversation.canDelete(entry)
    }

    private var canPin: Bool {
        appStore.conversation.canPin(entry)
    }

    private var canCopyLink: Bool {
        appStore.conversation.canCopyLink(entry)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isSelectionMode {
                Button(action: onToggleSelect) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.55))
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 6)
            }

            if isOutgoing {
                Spacer(minLength: 24)
                hoverQuickActions
            } else if showAvatarColumn {
                groupSenderAvatarColumn
            }

            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
                if isBorderless {
                    borderlessContent
                } else {
                    standardBubble
                }

                if let inlineSource = entry.inlineKeyboardSourceMessage,
                   let rows = inlineSource.replyMarkup?.inlineKeyboardRows
                {
                    InlineKeyboardView(
                        messageId: inlineSource.id,
                        rows: rows,
                        inFlightButtonKey: inFlightCallbackButtonKey
                    ) { button in
                        onTapInlineButton(button, inlineSource)
                    }
                    .allowsHitTesting(!isSelectionMode)
                }
            }

            if !isOutgoing {
                hoverQuickActions
                Spacer(minLength: 24)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(rowBackdrop, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            if isSelectionMode {
                onToggleSelect()
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isHighlighted)
        .animation(.easeInOut(duration: 0.14), value: isSelected)
        .task(id: leadMessage.id) {
            if leadMessage.replyTo != nil {
                appStore.conversation.ensureRepliedMessageLoaded(for: leadMessage)
            }
        }
    }

    @ViewBuilder
    private var groupSenderAvatarColumn: some View {
        if let avatar = senderAvatar {
            let avatarView = AvatarView(
                title: avatar.title,
                initials: avatar.initials,
                accentSeed: avatar.accentColorId,
                fileId: avatar.smallPhotoFileId,
                knownLocalPath: avatar.smallPhotoLocalPath,
                size: 32
            )

            if let userId = avatar.userId, let onTapSenderAvatar, !isSelectionMode {
                Button {
                    onTapSenderAvatar(userId)
                } label: {
                    avatarView
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(avatar.title)
            } else {
                avatarView
                    .help(avatar.title)
            }
        } else {
            Color.clear
                .frame(width: 32, height: 1)
        }
    }

    private var rowBackdrop: Color {
        if isHighlighted {
            return Color.accentColor.opacity(0.18)
        }
        if isSelectionMode && isSelected {
            return Color.accentColor.opacity(0.10)
        }
        return .clear
    }

    @ViewBuilder
    private var hoverQuickActions: some View {
        let visible = isHovering && !isSelectionMode && (canReply || canEdit || canForward)
        HStack(spacing: 2) {
            if canReply {
                Button {
                    onReply(leadMessage)
                } label: {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("回复")
            }

            if canEdit {
                Button {
                    onEdit(entry.editableMessage)
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("编辑")
            }

            if canForward {
                Button {
                    onForward(entry.allMessages)
                } label: {
                    Image(systemName: "arrowshape.turn.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("转发")
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator.opacity(0.45), lineWidth: 0.5))
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .animation(.easeInOut(duration: 0.14), value: visible)
    }

    private var standardBubble: some View {
        Grid(alignment: .leading, verticalSpacing: 4) {
            if let senderName, !senderName.isEmpty {
                GridRow {
                    Text(senderName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isOutgoing ? Color.white.opacity(0.92) : senderNameColor)
                }
            }

            if let forwardInfo = leadMessage.forwardInfo {
                GridRow {
                    forwardedHeader(forwardInfo)
                }
            }

            if let replyRef = leadMessage.replyTo {
                GridRow {
                    replyQuoteView(for: replyRef)
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
        .allowsHitTesting(!isSelectionMode)
        .contextMenu {
            contextMenuItems
        }
    }

    private var borderlessContent: some View {
        VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
            if let senderName, !senderName.isEmpty {
                Text(senderName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(senderNameColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.regularMaterial, in: Capsule())
            }

            if let forwardInfo = leadMessage.forwardInfo {
                forwardedHeader(forwardInfo, inMaterialPill: true)
            }

            if let replyRef = leadMessage.replyTo {
                replyQuoteView(for: replyRef, inBorderlessBubble: true)
                    .frame(maxWidth: 260, alignment: isOutgoing ? .trailing : .leading)
            }

            contentBody

            metadataRow(textColor: .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.regularMaterial, in: Capsule())
        }
        .allowsHitTesting(!isSelectionMode)
        .contextMenu {
            contextMenuItems
        }
    }

    @ViewBuilder
    private func forwardedHeader(_ info: MessageForwardMetadata, inMaterialPill: Bool = false) -> some View {
        let originName = appStore.chatList.originDisplayName(for: info.origin)
        let label = HStack(spacing: 4) {
            Image(systemName: "arrowshape.turn.up.forward.fill")
                .font(.caption2)
            Text("转发自 \(originName)")
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(inMaterialPill ? Color.accentColor : (isOutgoing ? Color.white.opacity(0.88) : Color.accentColor))

        if inMaterialPill {
            label
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.regularMaterial, in: Capsule())
        } else {
            label
        }
    }

    private func replyQuoteView(
        for replyRef: MessageReplyReference,
        inBorderlessBubble: Bool = false
    ) -> some View {
        let state = appStore.conversation.repliedMessageState(for: leadMessage)
        let isJumpable = !replyRef.isStoryReply
            && replyRef.chatId == leadMessage.chatId
            && replyRef.messageId != 0

        let titleText = resolvedReplyAuthorTitle(replyRef: replyRef, state: state)
        let snippetText = resolvedReplySnippetText(replyRef: replyRef, state: state)
        let isDeletedState: Bool = {
            if case .deleted = state { return true }
            return false
        }()
        let thumbnailFile: MediaFileDescriptor? = {
            if case .loaded(let msg) = state {
                return msg.content.replyThumbnailFile
            }
            return nil
        }()

        let useLightText = isOutgoing && !inBorderlessBubble

        return HStack(alignment: .center, spacing: 7) {
            if let thumbFile = thumbnailFile,
               let nsImage = appStore.fileCache.image(for: thumbFile)
            {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 1.5) {
                Text(titleText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(useLightText ? Color.white.opacity(0.95) : Color.accentColor)
                    .lineLimit(1)

                Text(snippetText)
                    .font(.caption)
                    .italic(isDeletedState)
                    .foregroundStyle(useLightText ? Color.white.opacity(0.82) : Color.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .background {
            if inBorderlessBubble {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.regularMaterial)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOutgoing ? Color.white.opacity(0.16) : Color.accentColor.opacity(0.08))
            }
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(useLightText ? Color.white.opacity(0.85) : Color.accentColor)
                .frame(width: 2.5)
                .padding(.vertical, 4)
                .padding(.leading, 5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            if isJumpable {
                onJumpToMessage(replyRef.messageId)
            }
        }
        .task(id: thumbnailFile?.fileId) {
            if let thumbFile = thumbnailFile {
                appStore.fileCache.ensureDownloaded(thumbFile, priority: 10)
            }
        }
    }

    private func resolvedReplyAuthorTitle(
        replyRef: MessageReplyReference,
        state: RepliedMessageState?
    ) -> String {
        if replyRef.isStoryReply {
            return "回复动态"
        }
        if case .loaded(let repliedMessage) = state {
            if let name = appStore.chatList.senderDisplayName(for: repliedMessage.sender), !name.isEmpty {
                return name
            }
            return repliedMessage.isOutgoing ? (appStore.currentUser?.displayName ?? "我") : "消息"
        }
        if let origin = replyRef.origin {
            return appStore.chatList.originDisplayName(for: origin)
        }
        if case .deleted = state {
            return "引用消息"
        }
        return "回复消息"
    }

    private func resolvedReplySnippetText(
        replyRef: MessageReplyReference,
        state: RepliedMessageState?
    ) -> String {
        if let quoteText = replyRef.quoteText, !quoteText.isEmpty {
            return quoteText.text.replacingOccurrences(of: "\n", with: " ")
        }
        if let state {
            switch state {
            case .loaded(let repliedMessage):
                return repliedMessage.previewText
            case .deleted:
                return "原消息已删除"
            case .loading:
                return replyRef.externalPreviewText ?? "正在加载引用消息…"
            }
        }
        return replyRef.externalPreviewText ?? "[消息]"
    }

    @ViewBuilder
    private var contentBody: some View {
        switch entry {
        case .album(_, let messages):
            MediaAlbumView(
                messages: messages,
                isOutgoing: isOutgoing,
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
        case .text(let formatted):
            FormattedTextView(
                content: formatted,
                isOutgoing: message.isOutgoing
            )

        case .photo(let media):
            PhotoMessageView(
                messageId: message.id,
                isOutgoing: message.isOutgoing,
                media: media,
                primaryTextColor: primaryTextColor,
                onOpenLightbox: { onOpenLightbox(message.id) }
            )

        case .video(let media):
            VideoMessageView(
                messageId: message.id,
                isOutgoing: message.isOutgoing,
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
                isOutgoing: message.isOutgoing,
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
            StickerMessageView(
                media: media,
                onOpenStickerPack: onOpenStickerPack
            )

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
            if leadMessage.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(textColor)
            }

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
        if canReply {
            Button {
                onReply(leadMessage)
            } label: {
                Label("回复", systemImage: "arrowshape.turn.up.left")
            }
        }

        if canEdit {
            let editTarget = entry.editableMessage
            Button {
                onEdit(editTarget)
            } label: {
                Label(editTarget.content.isTextMessage ? "编辑消息" : "编辑说明文字", systemImage: "pencil")
            }
        }

        if canPin {
            Button {
                onTogglePin(leadMessage)
            } label: {
                Label(
                    leadMessage.isPinned ? "取消置顶" : "置顶消息",
                    systemImage: leadMessage.isPinned ? "pin.slash" : "pin"
                )
            }
        }

        if canForward {
            Button {
                onForward(entry.allMessages)
            } label: {
                if case .album(_, let messages) = entry {
                    Label("转发相册 (\(messages.count) 项)", systemImage: "arrowshape.turn.up.right")
                } else {
                    Label("转发", systemImage: "arrowshape.turn.up.right")
                }
            }
        }

        Button {
            onEnterSelectionMode()
        } label: {
            Label("多选", systemImage: "checkmark.circle")
        }

        Divider()

        if let copyable = copyableText {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(copyable, forType: .string)
            } label: {
                Label("复制文本", systemImage: "doc.on.doc")
            }
        }

        if canCopyLink {
            Button {
                onCopyLink()
            } label: {
                Label("复制消息链接", systemImage: "link")
            }
        }

        if case .single(let message) = entry {
            singleMediaContextItems(for: message)
        } else if case .album(_, let messages) = entry, let first = messages.first {
            Button("查看相册 (\(messages.count) 项)") {
                onOpenLightbox(first.id)
            }
        }

        if canDelete {
            Divider()

            Button(role: .destructive) {
                onDelete(entry.allMessages)
            } label: {
                if case .album(_, let messages) = entry {
                    Label("删除相册 (\(messages.count) 项)…", systemImage: "trash")
                } else {
                    Label("删除…", systemImage: "trash")
                }
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

        case .sticker(let media):
            if !media.isAnimatedEmoji && media.setId != 0 {
                Button {
                    onOpenStickerPack(media.setId)
                } label: {
                    Label("查看贴纸包…", systemImage: "square.grid.2x2")
                }
            }

            if !media.isAnimatedEmoji {
                let isFav = appStore.stickers.isFavorite(media)
                Button {
                    Task {
                        let nowFav = await appStore.stickers.toggleFavorite(
                            fileId: media.file.fileId,
                            remoteFileId: media.remoteFileId
                        )
                        appStore.conversation.showTransientNotice(nowFav ? "已收藏贴纸" : "已取消收藏贴纸")
                    }
                } label: {
                    Label(
                        isFav ? "取消收藏贴纸" : "收藏贴纸",
                        systemImage: isFav ? "star.slash" : "star"
                    )
                }
            }

            let state = appStore.fileCache.state(for: media.file)
            if state.isDownloaded, let path = state.localPath {
                if media.format == .webp {
                    Button("复制图片") { MediaFileActions.copyImageToPasteboard(from: path) }
                }
                Button("另存为…") {
                    MediaFileActions.saveFile(
                        from: path,
                        suggestedFileName: "sticker_\(message.id).\(media.format.fileExtension)",
                        mimeType: media.format.mimeType
                    )
                }
                Button("在 Finder 中显示") { MediaFileActions.revealInFinder(localPath: path) }
            }

        case .text, .unsupported:
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
            case .text(let formatted):
                return formatted.isEmpty ? nil : formatted.text
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
