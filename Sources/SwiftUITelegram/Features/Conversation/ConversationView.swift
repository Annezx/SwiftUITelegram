import AppKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct ConversationView: View {
    @Environment(AppStore.self) private var appStore

    let chat: ChatSummary

    @State private var scrollPosition = ScrollPosition(idType: Int64.self)
    @State private var isNearBottom: Bool = true
    @State private var voiceRecorder = VoiceRecorderManager()
    @State private var lightboxSession: MediaLightboxSession?
    @State private var quickLookURL: URL?
    @State private var deleteRequest: DeleteMessagesRequest?
    @State private var forwardRequest: ForwardMessagesRequest?
    @State private var isDropTargeted: Bool = false
    @State private var keyEventMonitor: Any?

    private var activeBannerError: String? {
        appStore.conversation.errorMessage
            ?? appStore.audioPlayer.errorMessage
            ?? voiceRecorder.errorMessage
    }

    var body: some View {
        @Bindable var conversation = appStore.conversation
        let entries = conversation.timelineEntries

        VStack(spacing: 0) {
            headerBar

            Divider()

            ZStack(alignment: .bottomTrailing) {
                messageTimeline(entries: entries)

                if let notice = conversation.noticeMessage {
                    VStack {
                        Text(notice)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(.separator.opacity(0.45), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                            .padding(.top, 10)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if !isNearBottom && !entries.isEmpty {
                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            scrollPosition.scrollTo(edge: .bottom)
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.body.weight(.semibold))
                            .frame(width: 34, height: 34)
                            .background(.regularMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isNearBottom)
            .animation(.easeInOut(duration: 0.2), value: conversation.noticeMessage)

            if let error = activeBannerError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button {
                        conversation.errorMessage = nil
                        appStore.audioPlayer.errorMessage = nil
                        voiceRecorder.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(.red.opacity(0.08))
            }

            Divider()

            if conversation.isSelectionMode {
                selectionActionBar(conversation: conversation)
            } else {
                MessageComposerView(
                    text: $conversation.draftText,
                    pendingAttachments: conversation.pendingAttachments,
                    sendAsDocument: $conversation.sendAsDocument,
                    sendWithSpoiler: $conversation.sendWithSpoiler,
                    hasToggleableOriginalMedia: conversation.hasToggleableOriginalMedia,
                    hasSpoilerCapableMedia: conversation.hasSpoilerCapableMedia,
                    isPreparingAttachments: conversation.isPreparingAttachments,
                    isSending: conversation.isSending,
                    composerMode: conversation.composerMode,
                    composerContextTitle: composerContextTitle(for: conversation.composerMode),
                    composerContextSubtitle: composerContextSubtitle(for: conversation.composerMode),
                    composerContextThumbnail: composerContextThumbnail(for: conversation.composerMode),
                    focusTrigger: conversation.composerFocusTrigger,
                    recorder: voiceRecorder,
                    onPickMedia: presentMediaPicker,
                    onPickDocuments: presentDocumentPicker,
                    onPasteClipboardImage: { pasteMediaFromClipboard(onlyWhenNoPlainText: false) },
                    onRemoveAttachment: { id in
                        conversation.removeAttachment(id: id)
                    },
                    onClearAttachments: {
                        conversation.clearPendingAttachments()
                    },
                    onCancelComposerMode: {
                        conversation.cancelComposerMode()
                    },
                    onTapComposerContext: {
                        if let targetId = conversation.composerMode.replyingMessage?.id
                            ?? conversation.composerMode.editingMessage?.id
                        {
                            Task { await conversation.jumpToMessage(id: targetId) }
                        }
                    },
                    onSend: {
                        Task { await conversation.sendCurrentDraft() }
                    },
                    onSendVoiceNote: { recorded in
                        Task { await conversation.sendVoiceNote(recorded) }
                    }
                )
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .overlay {
            if isDropTargeted {
                dropOverlay
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            handleDroppedProviders(providers)
        }
        .quickLookPreview($quickLookURL)
        .sheet(item: $lightboxSession) { session in
            MediaLightboxView(
                session: session,
                onQuickLook: { url in
                    quickLookURL = url
                }
            )
            .environment(appStore)
        }
        .sheet(item: $deleteRequest) { request in
            DeleteMessagesSheet(request: request) { revoke in
                await appStore.conversation.deleteMessages(request.messageIds, revoke: revoke)
            }
        }
        .sheet(item: $forwardRequest) { request in
            ForwardMessagesSheet(request: request) { targetChatIds, sendCopy, removeCaption, comment in
                let ok = await appStore.conversation.forwardMessages(
                    request.messageIds,
                    fromChatId: request.fromChatId,
                    toChatIds: targetChatIds,
                    sendCopy: sendCopy,
                    removeCaption: removeCaption,
                    comment: comment
                )
                if ok {
                    if targetChatIds.count == 1, let singleTarget = targetChatIds.first {
                        if singleTarget != chat.id {
                            appStore.chatList.selectedChatId = singleTarget
                        } else {
                            appStore.conversation.showTransientNotice("已转发到当前对话")
                        }
                    } else if targetChatIds.count > 1 {
                        appStore.conversation.showTransientNotice("已转发到 \(targetChatIds.count) 个对话")
                    }
                }
                return ok
            }
            .environment(appStore)
        }
        .onAppear {
            installKeyEventMonitor()
        }
        .onDisappear {
            removeKeyEventMonitor()
            voiceRecorder.cancelRecording()
        }
        .onChange(of: conversation.scrollToBottomTrigger) { _, _ in
            withAnimation(.snappy(duration: 0.2)) {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
        .onChange(of: conversation.scrollToMessageRequest) { _, request in
            guard let request else { return }
            withAnimation(.snappy(duration: 0.25)) {
                scrollPosition.scrollTo(id: request.entryId, anchor: .center)
            }
        }
        .onChange(of: conversation.messages.last?.id) { _, _ in
            if isNearBottom {
                withAnimation(.snappy(duration: 0.2)) {
                    scrollPosition.scrollTo(edge: .bottom)
                }
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            AvatarView(
                title: chat.title,
                initials: chat.avatarInitials,
                accentSeed: chat.accentColorId,
                fileId: chat.smallPhotoFileId,
                knownLocalPath: chat.smallPhotoLocalPath,
                size: 36
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(chat.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(appStore.chatList.subtitle(for: chat))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if appStore.audioPlayer.isPlaying {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Text("正在播放音频")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        appStore.audioPlayer.stop()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("停止播放")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func selectionActionBar(conversation: ConversationStore) -> some View {
        let selected = conversation.selectedMessages
        let canForwardAny = !selected.isEmpty
        let canDeleteAny = !selected.isEmpty

        return HStack(spacing: 12) {
            Button("取消") {
                conversation.exitSelectionMode()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Text("已选择 \(selected.count) 条消息")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                presentForwardSheet(for: selected)
            } label: {
                Label("转发", systemImage: "arrowshape.turn.up.right")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(!canForwardAny)

            Button(role: .destructive) {
                Task { await presentDeleteSheet(for: selected) }
            } label: {
                Label("删除…", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.regular)
            .disabled(!canDeleteAny)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, LayoutMetrics.composerVerticalPadding)
        .frame(minHeight: LayoutMetrics.bottomBarHeight)
        .background(.bar)
    }

    private func messageTimeline(entries: [ConversationTimelineEntry]) -> some View {
        let conversation = appStore.conversation

        return ScrollView {
            LazyVStack(spacing: 6) {
                if conversation.isLoadingOlder {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.vertical, 10)
                } else if !conversation.hasMoreOlder && !entries.isEmpty {
                    Text("已加载全部历史消息")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 10)
                }

                if conversation.isLoadingInitial && entries.isEmpty {
                    ProgressView("正在加载消息…")
                        .padding(.top, 80)
                } else if entries.isEmpty {
                    ContentUnavailableView(
                        "暂无消息",
                        systemImage: "text.bubble",
                        description: Text("发送文字、拖拽文件或粘贴图片开始聊天吧。")
                    )
                    .padding(.top, 80)
                } else {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if shouldShowDateDivider(at: index, in: entries) {
                            dateSeparator(for: entry.date)
                        }

                        MessageBubbleView(
                            entry: entry,
                            senderName: shouldShowSenderName(for: entry.leadMessage)
                                ? appStore.chatList.senderDisplayName(for: entry.leadMessage.sender)
                                : nil,
                            isReadByRecipient: entry.tailMessage.isOutgoing
                                && entry.tailMessage.id <= chat.lastReadOutboxMessageId,
                            isHighlighted: conversation.highlightedEntryId == entry.id,
                            isSelectionMode: conversation.isSelectionMode,
                            isSelected: conversation.isEntrySelected(entry),
                            onOpenLightbox: { messageId in
                                openLightbox(at: messageId)
                            },
                            onQuickLook: { url in
                                quickLookURL = url
                            },
                            onToggleSelect: {
                                conversation.toggleSelection(for: entry)
                            },
                            onReply: { message in
                                conversation.beginReply(to: message)
                            },
                            onEdit: { message in
                                conversation.beginEdit(message: message)
                            },
                            onForward: { messages in
                                presentForwardSheet(for: messages)
                            },
                            onDelete: { messages in
                                Task { await presentDeleteSheet(for: messages) }
                            },
                            onEnterSelectionMode: {
                                conversation.enterSelectionMode(with: entry)
                            },
                            onJumpToMessage: { messageId in
                                Task { await conversation.jumpToMessage(id: messageId) }
                            }
                        )
                        .id(entry.id)
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .defaultScrollAnchor(.bottom)
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            let distanceFromBottom = geometry.contentSize.height - geometry.visibleRect.maxY
            return distanceFromBottom <= 80
        } action: { _, nearBottom in
            isNearBottom = nearBottom
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            let hasScrollableOverflow = geometry.contentSize.height > geometry.containerSize.height + 40
            return hasScrollableOverflow && geometry.visibleRect.minY <= 80
        } action: { oldNearTop, newNearTop in
            if newNearTop && !oldNearTop {
                Task { await appStore.conversation.loadOlderMessages() }
            }
        }
    }

    private var dropOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor)
                Text("松开以添加到发送队列")
                    .font(.headline)
                Text("支持图片、视频、GIF、音频和任意文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 2, dash: [8, 5])
                    )
            )
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    // MARK: - Message Action Sheets & Composer Context Helpers

    private func presentForwardSheet(for messages: [MessageItem]) {
        guard !messages.isEmpty else { return }
        forwardRequest = ForwardMessagesRequest(
            fromChatId: chat.id,
            messages: messages
        )
    }

    private func presentDeleteSheet(for messages: [MessageItem]) async {
        guard !messages.isEmpty else { return }

        var fetchedPermissions: [MessagePermissions] = []
        for message in messages {
            if let perms = await appStore.conversation.fetchPermissions(for: message) {
                fetchedPermissions.append(perms)
            }
        }

        let canDeleteForSelf: Bool
        let canDeleteForAll: Bool
        if fetchedPermissions.count == messages.count {
            canDeleteForSelf = fetchedPermissions.allSatisfy(\.canBeDeletedOnlyForSelf)
            canDeleteForAll = fetchedPermissions.allSatisfy(\.canBeDeletedForAllUsers)
        } else {
            canDeleteForSelf = !chat.kind.isChannel
            canDeleteForAll = messages.allSatisfy(\.isOutgoing)
        }

        guard canDeleteForSelf || canDeleteForAll else {
            appStore.conversation.errorMessage = "当前权限无法删除所选消息。"
            return
        }

        deleteRequest = DeleteMessagesRequest(
            chatId: chat.id,
            chatTitle: chat.title,
            chatKind: chat.kind,
            messages: messages,
            canDeleteForSelf: canDeleteForSelf,
            canDeleteForAll: canDeleteForAll
        )
    }

    private func composerContextTitle(for mode: ComposerMode) -> String? {
        switch mode {
        case .normal:
            return nil
        case .replying(let message):
            let name = appStore.chatList.senderDisplayName(for: message.sender)
                ?? (message.isOutgoing ? (appStore.currentUser?.displayName ?? "我") : chat.title)
            return "回复 \(name)"
        case .editing(let message):
            return message.content.isTextMessage ? "编辑消息" : "编辑说明文字"
        }
    }

    private func composerContextSubtitle(for mode: ComposerMode) -> String? {
        switch mode {
        case .normal:
            return nil
        case .replying(let message):
            return message.previewText
        case .editing(let message):
            return message.previewText
        }
    }

    private func composerContextThumbnail(for mode: ComposerMode) -> MediaFileDescriptor? {
        switch mode {
        case .normal:
            return nil
        case .replying(let message):
            return message.content.replyThumbnailFile
        case .editing(let message):
            return message.content.replyThumbnailFile
        }
    }

    // MARK: - Media Lightbox & Pickers

    private func openLightbox(at messageId: Int64) {
        guard lightboxSession == nil else { return }
        let items = MediaLightboxItem.extract(from: appStore.conversation.messages)
        guard !items.isEmpty else { return }
        lightboxSession = MediaLightboxSession(items: items, initialMessageId: messageId)
    }

    private func presentMediaPicker() {
        let panel = NSOpenPanel()
        panel.title = "选择图片、视频或音频"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .movie, .video, .gif, .audio]

        panel.begin { response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            appStore.conversation.stageAttachmentURLs(panel.urls, forceDocument: false)
        }
    }

    private func presentDocumentPicker() {
        let panel = NSOpenPanel()
        panel.title = "选择要发送的文件"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        panel.begin { response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            appStore.conversation.stageAttachmentURLs(panel.urls, forceDocument: true)
        }
    }

    // MARK: - Drag & Drop and Keyboard Shortcuts

    private func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let resolvedURL: URL?
                    if let data = item as? Data {
                        resolvedURL = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let url = item as? URL {
                        resolvedURL = url
                    } else if let nsURL = item as? NSURL {
                        resolvedURL = nsURL as URL
                    } else {
                        resolvedURL = nil
                    }
                    guard let resolvedURL else { return }
                    Task { @MainActor in
                        appStore.conversation.stageAttachmentURLs([resolvedURL])
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in
                        if let image = NSImage(data: data) {
                            appStore.conversation.stagePastedImage(image)
                        }
                    }
                }
            }
        }

        return accepted
    }

    @discardableResult
    private func pasteMediaFromClipboard(onlyWhenNoPlainText: Bool) -> Bool {
        let pasteboard = NSPasteboard.general

        // When invoked via ⌘V shortcut, always let normal text paste flow into the TextField.
        if onlyWhenNoPlainText {
            if let text = pasteboard.string(forType: .string), !text.isEmpty {
                let hasFileURLs = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.isEmpty == false
                if !hasFileURLs {
                    return false
                }
            }
        }

        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            appStore.conversation.stageAttachmentURLs(urls)
            return true
        }

        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first
        {
            appStore.conversation.stagePastedImage(image)
            return true
        }

        if !onlyWhenNoPlainText {
            appStore.conversation.errorMessage = "剪贴板中未检测到可发送的图片或文件。"
        }
        return false
    }

    private func installKeyEventMonitor() {
        removeKeyEventMonitor()
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard lightboxSession == nil,
                  deleteRequest == nil,
                  forwardRequest == nil,
                  !voiceRecorder.isRecording
            else {
                return event
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Escape cancels multi-select or active reply/edit mode cleanly.
            if flags.isEmpty && event.keyCode == 53 {
                if appStore.conversation.isSelectionMode {
                    appStore.conversation.exitSelectionMode()
                    return nil
                }
                if appStore.conversation.composerMode != .normal {
                    appStore.conversation.cancelComposerMode()
                    return nil
                }
                return event
            }

            // ⌘V pastes clipboard images/files unless editing a text message.
            if flags == .command,
               event.charactersIgnoringModifiers?.lowercased() == "v",
               !appStore.conversation.composerMode.isEditing,
               !appStore.conversation.isSelectionMode
            {
                if pasteMediaFromClipboard(onlyWhenNoPlainText: true) {
                    return nil
                }
            }

            return event
        }
    }

    private func removeKeyEventMonitor() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
    }

    // MARK: - Timeline Helpers

    private func shouldShowSenderName(for message: MessageItem) -> Bool {
        chat.kind.isGroup && !message.isOutgoing
    }

    private func shouldShowDateDivider(at index: Int, in entries: [ConversationTimelineEntry]) -> Bool {
        guard index > 0 else { return true }
        return !Calendar.current.isDate(entries[index - 1].date, inSameDayAs: entries[index].date)
    }

    private func dateSeparator(for date: Date) -> some View {
        Text(Self.dateDividerFormatter.string(from: date))
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .padding(.vertical, 8)
    }

    private static let dateDividerFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
