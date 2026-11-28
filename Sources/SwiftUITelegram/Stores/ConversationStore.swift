import AppKit
import Foundation
import Observation
import TDLibKit

enum ComposerMode: Equatable {
    case normal
    case replying(MessageItem)
    case editing(MessageItem)

    var replyingMessage: MessageItem? {
        if case .replying(let message) = self { return message }
        return nil
    }

    var editingMessage: MessageItem? {
        if case .editing(let message) = self { return message }
        return nil
    }

    var isEditing: Bool {
        if case .editing = self { return true }
        return false
    }
}

enum RepliedMessageState: Equatable {
    case loading
    case loaded(MessageItem)
    case deleted
}

struct ScrollToMessageRequest: Equatable {
    let entryId: Int64
    let token: Int
}

@MainActor
@Observable
final class ConversationStore {
    private let service: TDLibService
    private var loadTask: Task<Void, Never>?
    private var botContextTask: Task<Void, Never>?
    private var highlightClearTask: Task<Void, Never>?
    private var noticeClearTask: Task<Void, Never>?
    private var inFlightReplyFetchIds: Set<Int64> = []
    private var inFlightPermissionIds: Set<Int64> = []
    private var savedDraftBeforeEditing: String = ""
    private var scrollToMessageToken: Int = 0
    private var pendingJumpMessageId: Int64?

    private(set) var activeChatId: Int64?
    private(set) var activeChatKind: ChatKind?
    private(set) var activeBotUserId: Int64?
    private(set) var messages: [MessageItem] = []
    private(set) var isLoadingInitial: Bool = false
    private(set) var isLoadingOlder: Bool = false
    private(set) var hasMoreOlder: Bool = true
    private(set) var isSending: Bool = false
    private(set) var isPreparingAttachments: Bool = false
    private(set) var pendingAttachments: [PendingAttachment] = []
    private(set) var scrollToBottomTrigger: Int = 0
    private(set) var composerMode: ComposerMode = .normal
    private(set) var composerFocusTrigger: Int = 0
    private(set) var repliedMessages: [Int64: RepliedMessageState] = [:]
    private(set) var messagePermissions: [Int64: MessagePermissions] = [:]
    private(set) var highlightedEntryId: Int64?
    private(set) var scrollToMessageRequest: ScrollToMessageRequest?
    private(set) var isSelectionMode: Bool = false
    private(set) var selectedMessageIds: Set<Int64> = []
    private(set) var botCommands: [BotCommandItem] = []
    private(set) var botMenuButton: BotMenuButtonItem?
    private(set) var botDescription: String = ""
    private(set) var activeReplyKeyboard: ReplyKeyboardMarkup?
    private(set) var activeInputPlaceholder: String?
    private(set) var inFlightCallbackButtonKey: String?
    private(set) var pendingBotStart: PendingBotStartContext?
    private(set) var canJoinActiveChat: Bool = false
    private(set) var activeChatJoinRequiresRequest: Bool = false
    private(set) var isJoiningActiveChat: Bool = false
    private(set) var isViewingHistoricalAnchor: Bool = false

    var draftText: String = ""
    var sendAsDocument: Bool = false
    var sendWithSpoiler: Bool = false
    var isReplyKeyboardVisible: Bool = false
    var errorMessage: String?
    var noticeMessage: String?
    var callbackAlert: BotCallbackAlert?
    var pendingPasswordCallback: BotCallbackPasswordRequest?

    var onOpenTelegramURL: ((URL) async -> Void)?

    init(service: TDLibService) {
        self.service = service
    }

    var isActiveChatBot: Bool {
        activeBotUserId != nil
    }

    var timelineEntries: [ConversationTimelineEntry] {
        ConversationTimelineEntry.group(messages)
    }

    var hasSendableContent: Bool {
        if case .editing(let target) = composerMode {
            let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
            if target.content.isTextMessage {
                return !trimmed.isEmpty
            }
            return true
        }
        return !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty
    }

    var hasToggleableOriginalMedia: Bool {
        pendingAttachments.contains { $0.supportsOriginalFileToggle }
    }

    var hasSpoilerCapableMedia: Bool {
        !sendAsDocument && pendingAttachments.contains { $0.supportsSpoiler }
    }

    var selectedMessages: [MessageItem] {
        messages.filter { selectedMessageIds.contains($0.id) }
    }

    var selectedEntriesCount: Int {
        timelineEntries.filter { isEntrySelected($0) }.count
    }

    func selectChat(_ chatId: Int64?, jumpToMessageId: Int64? = nil) {
        if activeChatId == chatId {
            if let jumpToMessageId, jumpToMessageId != 0 {
                Task {
                    await jumpToMessage(id: jumpToMessageId)
                }
            }
            return
        }

        let previousChatId = activeChatId
        activeChatId = chatId
        activeChatKind = nil
        activeBotUserId = nil
        pendingJumpMessageId = (jumpToMessageId ?? 0) != 0 ? jumpToMessageId : nil
        loadTask?.cancel()
        botContextTask?.cancel()
        highlightClearTask?.cancel()
        noticeClearTask?.cancel()
        messages = []
        draftText = ""
        savedDraftBeforeEditing = ""
        composerMode = .normal
        repliedMessages = [:]
        messagePermissions = [:]
        inFlightReplyFetchIds = []
        inFlightPermissionIds = []
        highlightedEntryId = nil
        scrollToMessageRequest = nil
        isSelectionMode = false
        selectedMessageIds = []
        botCommands = []
        botMenuButton = nil
        botDescription = ""
        activeReplyKeyboard = nil
        isReplyKeyboardVisible = false
        activeInputPlaceholder = nil
        inFlightCallbackButtonKey = nil
        callbackAlert = nil
        pendingPasswordCallback = nil
        pendingBotStart = nil
        canJoinActiveChat = false
        activeChatJoinRequiresRequest = false
        isJoiningActiveChat = false
        isViewingHistoricalAnchor = false
        clearPendingAttachments()
        errorMessage = nil
        noticeMessage = nil
        hasMoreOlder = true
        isLoadingInitial = false
        isLoadingOlder = false

        if let previousChatId {
            Task {
                _ = try? await service.closeChat(chatId: previousChatId)
            }
        }

        guard let chatId else { return }

        loadTask = Task {
            await loadInitialHistory(for: chatId)
        }
        botContextTask = Task {
            await loadBotAndMarkupContext(for: chatId)
        }
    }

    func preparePendingBotStart(_ context: PendingBotStartContext) {
        guard activeChatId == context.chatId else { return }
        pendingBotStart = context
        if activeBotUserId == nil {
            activeBotUserId = context.botUserId
        }
    }

    func dismissPendingBotStart() {
        pendingBotStart = nil
    }

    func prefillDraftText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draftText = text
        composerFocusTrigger += 1
    }

    func joinActiveChat() async {
        guard let chatId = activeChatId, canJoinActiveChat, !isJoiningActiveChat else { return }
        isJoiningActiveChat = true
        errorMessage = nil
        defer { isJoiningActiveChat = false }

        do {
            let result = try await service.joinChat(chatId: chatId)
            guard activeChatId == chatId else { return }
            switch result {
            case .chatJoinResultSuccess:
                canJoinActiveChat = false
                let isChannel = activeChatKind?.isChannel == true
                showTransientNotice(isChannel ? "已加入频道" : "已加入群组")
            case .chatJoinResultRequestSent:
                canJoinActiveChat = false
                showTransientNotice("已提交加入申请，请等待管理员审批")
            case .chatJoinResultGuardBotApprovalRequired:
                showTransientNotice("该群组需要通过验证机器人完成入群验证")
            case .chatJoinResultDeclined:
                errorMessage = "加入群组被拒绝"
            }
        } catch {
            if activeChatId == chatId {
                errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
            }
        }
    }

    func returnToLatestMessages() async {
        guard let chatId = activeChatId else { return }
        isViewingHistoricalAnchor = false
        messages = []
        hasMoreOlder = true
        pendingJumpMessageId = nil
        await loadInitialHistory(for: chatId)
    }

    func loadOlderMessages() async {
        guard
            let chatId = activeChatId,
            !isLoadingInitial,
            !isLoadingOlder,
            hasMoreOlder,
            let oldestMessageId = messages.first?.id
        else {
            return
        }

        isLoadingOlder = true
        defer { isLoadingOlder = false }

        do {
            let batch = try await service.getChatHistory(
                chatId: chatId,
                fromMessageId: oldestMessageId,
                limit: 40,
                offset: 0,
                onlyLocal: false
            )
            guard activeChatId == chatId else { return }

            if batch.isEmpty {
                hasMoreOlder = false
                return
            }

            let items = batch.map(MessageItem.init(tdMessage:))
            mergeMessages(items)
            prefetchPermissions(for: items)
        } catch {
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
        }
    }

    // MARK: - Reply, Edit & Selection Modes

    func beginReply(to message: MessageItem) {
        guard activeChatId == message.chatId else { return }
        if case .editing = composerMode {
            draftText = savedDraftBeforeEditing
            savedDraftBeforeEditing = ""
        }
        exitSelectionMode()
        composerMode = .replying(message)
        composerFocusTrigger += 1
    }

    func beginEdit(message: MessageItem) {
        guard activeChatId == message.chatId, message.content.isEditableInComposer else { return }
        exitSelectionMode()
        if !composerMode.isEditing {
            savedDraftBeforeEditing = draftText
        }
        composerMode = .editing(message)
        draftText = message.content.editableText
        composerFocusTrigger += 1
    }

    func cancelComposerMode() {
        if case .editing = composerMode {
            draftText = savedDraftBeforeEditing
            savedDraftBeforeEditing = ""
        }
        composerMode = .normal
    }

    func enterSelectionMode(with entry: ConversationTimelineEntry) {
        cancelComposerMode()
        isSelectionMode = true
        selectedMessageIds = Set(entry.messageIds)
    }

    func toggleSelection(for entry: ConversationTimelineEntry) {
        guard isSelectionMode else { return }
        let ids = entry.messageIds
        if ids.allSatisfy({ selectedMessageIds.contains($0) }) {
            for id in ids {
                selectedMessageIds.remove(id)
            }
            if selectedMessageIds.isEmpty {
                isSelectionMode = false
            }
        } else {
            for id in ids {
                selectedMessageIds.insert(id)
            }
        }
    }

    func isEntrySelected(_ entry: ConversationTimelineEntry) -> Bool {
        entry.messageIds.allSatisfy { selectedMessageIds.contains($0) }
    }

    func exitSelectionMode() {
        isSelectionMode = false
        selectedMessageIds.removeAll()
    }

    func insertBotCommand(_ command: String) {
        if draftText.isEmpty {
            draftText = command
        } else if draftText.hasSuffix(" ") || draftText.hasSuffix("\n") {
            draftText += command
        } else {
            draftText += " \(command)"
        }
        composerFocusTrigger += 1
    }

    func showTransientNotice(_ message: String) {
        noticeClearTask?.cancel()
        noticeMessage = message
        noticeClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.noticeMessage = nil
        }
    }

    // MARK: - Replied Message Lookup & Jump

    func repliedMessageState(for message: MessageItem) -> RepliedMessageState? {
        guard let reply = message.replyTo,
              !reply.isStoryReply,
              reply.chatId == message.chatId,
              reply.messageId != 0
        else {
            return nil
        }

        if let local = messages.first(where: { $0.id == reply.messageId }) {
            return .loaded(local)
        }
        if let cached = repliedMessages[reply.messageId] {
            return cached
        }
        return .loading
    }

    func ensureRepliedMessageLoaded(for message: MessageItem) {
        guard let chatId = activeChatId,
              let reply = message.replyTo,
              !reply.isStoryReply,
              reply.chatId == chatId,
              reply.messageId != 0
        else {
            return
        }

        let targetId = reply.messageId
        if messages.contains(where: { $0.id == targetId }) {
            return
        }
        if repliedMessages[targetId] != nil || inFlightReplyFetchIds.contains(targetId) {
            return
        }

        inFlightReplyFetchIds.insert(targetId)
        repliedMessages[targetId] = .loading

        Task {
            defer { inFlightReplyFetchIds.remove(targetId) }
            do {
                let tdReplied = try await service.getRepliedMessage(chatId: chatId, messageId: message.id)
                guard activeChatId == chatId else { return }
                repliedMessages[targetId] = .loaded(MessageItem(tdMessage: tdReplied))
            } catch {
                guard activeChatId == chatId else { return }
                if TDLibErrorHelper.isNotFound(error) {
                    repliedMessages[targetId] = .deleted
                } else {
                    repliedMessages.removeValue(forKey: targetId)
                }
            }
        }
    }

    func jumpToMessage(id targetMessageId: Int64) async {
        guard let chatId = activeChatId, targetMessageId != 0 else { return }

        if let entry = timelineEntries.first(where: { $0.contains(messageId: targetMessageId) }) {
            triggerScrollAndHighlight(entryId: entry.id)
            return
        }

        // Try loading up to 3 contiguous older pages so normal timeline pagination stays gap-free.
        for _ in 0..<3 {
            guard activeChatId == chatId, hasMoreOlder else { break }
            await loadOlderMessages()
            if let entry = timelineEntries.first(where: { $0.contains(messageId: targetMessageId) }) {
                triggerScrollAndHighlight(entryId: entry.id)
                return
            }
        }

        // For distant deep-linked messages, load a centered slice directly around the target message.
        do {
            let targetTdMessage = try? await service.getMessage(chatId: chatId, messageId: targetMessageId)
            let aroundBatch = try await service.getChatHistory(
                chatId: chatId,
                fromMessageId: targetMessageId,
                limit: 35,
                offset: -15,
                onlyLocal: false
            )
            guard activeChatId == chatId else { return }

            var fetched: [MessageItem] = aroundBatch.map(MessageItem.init(tdMessage:))
            if let targetTdMessage, !fetched.contains(where: { $0.id == targetTdMessage.id }) {
                fetched.append(MessageItem(tdMessage: targetTdMessage))
            }

            if fetched.contains(where: { $0.id == targetMessageId }) {
                let byId = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
                messages = byId.values.sorted(by: Self.chronologicalOrder)
                hasMoreOlder = true
                isViewingHistoricalAnchor = true
                prefetchPermissions(for: messages)
                if let entry = timelineEntries.first(where: { $0.contains(messageId: targetMessageId) }) {
                    triggerScrollAndHighlight(entryId: entry.id)
                    return
                }
            }
        } catch {
            // Fall through to gentle notice below.
        }

        showTransientNotice("原消息较早或已删除，可继续向上滚动历史记录查看。")
    }

    private func triggerScrollAndHighlight(entryId: Int64) {
        scrollToMessageToken += 1
        scrollToMessageRequest = ScrollToMessageRequest(entryId: entryId, token: scrollToMessageToken)
        highlightedEntryId = entryId

        highlightClearTask?.cancel()
        highlightClearTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            if self?.highlightedEntryId == entryId {
                self?.highlightedEntryId = nil
            }
        }
    }

    // MARK: - Message Permissions (TDLib Offline Properties)

    func permissions(for messageId: Int64) -> MessagePermissions? {
        messagePermissions[messageId]
    }

    func fetchPermissions(for message: MessageItem) async -> MessagePermissions? {
        if let cached = messagePermissions[message.id] {
            return cached
        }
        guard message.deliveryStatus == .sent else { return nil }
        do {
            let tdProps = try await service.getMessageProperties(chatId: message.chatId, messageId: message.id)
            let mapped = MessagePermissions(from: tdProps)
            if activeChatId == message.chatId {
                messagePermissions[message.id] = mapped
            }
            return mapped
        } catch {
            return nil
        }
    }

    func canReply(to entry: ConversationTimelineEntry) -> Bool {
        let message = entry.leadMessage
        if let perms = messagePermissions[message.id] {
            return perms.canBeReplied
        }
        return message.deliveryStatus == .sent
    }

    func canEdit(_ entry: ConversationTimelineEntry) -> Bool {
        let target = entry.editableMessage
        guard target.content.isEditableInComposer else { return false }
        if let perms = messagePermissions[target.id] {
            return perms.canBeEdited
        }
        return target.isOutgoing && target.deliveryStatus == .sent
    }

    func canForward(_ entry: ConversationTimelineEntry) -> Bool {
        let message = entry.leadMessage
        if let perms = messagePermissions[message.id] {
            return perms.canBeForwarded
        }
        return message.deliveryStatus == .sent
    }

    func canDelete(_ entry: ConversationTimelineEntry) -> Bool {
        let message = entry.leadMessage
        if let perms = messagePermissions[message.id] {
            return perms.canBeDeleted
        }
        return true
    }

    func canPin(_ entry: ConversationTimelineEntry) -> Bool {
        let message = entry.leadMessage
        if let perms = messagePermissions[message.id] {
            return perms.canBePinned
        }
        return false
    }

    func canCopyLink(_ entry: ConversationTimelineEntry) -> Bool {
        let message = entry.leadMessage
        if let perms = messagePermissions[message.id] {
            return perms.canGetLink
        }
        return false
    }

    func togglePin(message: MessageItem) async {
        guard let chatId = activeChatId else { return }
        errorMessage = nil
        do {
            if message.isPinned {
                try await service.unpinChatMessage(chatId: chatId, messageId: message.id)
                if let index = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[index].isPinned = false
                }
                showTransientNotice("已取消置顶消息")
            } else {
                try await service.pinChatMessage(
                    chatId: chatId,
                    messageId: message.id,
                    disableNotification: false,
                    onlyForSelf: false
                )
                if let index = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[index].isPinned = true
                }
                showTransientNotice("已置顶消息")
            }
        } catch {
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
        }
    }

    func copyMessageLink(for entry: ConversationTimelineEntry) async {
        guard let chatId = activeChatId else { return }
        let message = entry.leadMessage
        let isAlbum: Bool = {
            if case .album = entry { return true }
            return false
        }()
        errorMessage = nil
        do {
            let link = try await service.getMessageLink(
                chatId: chatId,
                messageId: message.id,
                forAlbum: isAlbum
            )
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link.link, forType: .string)
            showTransientNotice("已复制消息链接")
        } catch {
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
        }
    }

    func prefetchPermissions(for items: [MessageItem]) {
        guard let chatId = activeChatId else { return }
        let candidates = items.filter { item in
            item.deliveryStatus == .sent
                && messagePermissions[item.id] == nil
                && !inFlightPermissionIds.contains(item.id)
        }
        guard !candidates.isEmpty else { return }

        for item in candidates {
            inFlightPermissionIds.insert(item.id)
        }

        Task {
            defer {
                for item in candidates {
                    inFlightPermissionIds.remove(item.id)
                }
            }
            for item in candidates {
                guard activeChatId == chatId else { return }
                if let tdProps = try? await service.getMessageProperties(chatId: chatId, messageId: item.id) {
                    guard activeChatId == chatId else { return }
                    messagePermissions[item.id] = MessagePermissions(from: tdProps)
                }
            }
        }
    }

    // MARK: - Attachments Staging

    func stageAttachmentURLs(_ urls: [URL], forceDocument: Bool = false) {
        guard activeChatId != nil, !urls.isEmpty else { return }
        if composerMode.isEditing {
            cancelComposerMode()
        }
        let targetChatId = activeChatId
        errorMessage = nil
        isPreparingAttachments = true

        Task {
            defer { isPreparingAttachments = false }
            let prepared = await MediaAttachmentPreparer.prepare(urls: urls, forceDocument: forceDocument)
            guard activeChatId == targetChatId else {
                for item in prepared { MediaAttachmentPreparer.cleanup(item) }
                return
            }
            if prepared.isEmpty {
                errorMessage = "所选内容不包含可发送的文件（暂不支持直接发送文件夹）。"
                return
            }
            pendingAttachments.append(contentsOf: prepared)
            if forceDocument && !pendingAttachments.contains(where: { $0.supportsOriginalFileToggle }) {
                sendAsDocument = false
            }
        }
    }

    func stagePastedImage(_ image: NSImage) {
        guard activeChatId != nil else { return }
        if composerMode.isEditing {
            cancelComposerMode()
        }
        let targetChatId = activeChatId
        errorMessage = nil
        isPreparingAttachments = true

        Task {
            defer { isPreparingAttachments = false }
            guard let prepared = await MediaAttachmentPreparer.preparePastedImage(image) else {
                errorMessage = "无法读取剪贴板中的图片。"
                return
            }
            guard activeChatId == targetChatId else {
                MediaAttachmentPreparer.cleanup(prepared)
                return
            }
            pendingAttachments.append(prepared)
        }
    }

    func removeAttachment(id: UUID) {
        if let idx = pendingAttachments.firstIndex(where: { $0.id == id }) {
            let removed = pendingAttachments.remove(at: idx)
            MediaAttachmentPreparer.cleanup(removed)
        }
        if pendingAttachments.isEmpty {
            sendAsDocument = false
            sendWithSpoiler = false
        }
    }

    func clearPendingAttachments() {
        for item in pendingAttachments {
            MediaAttachmentPreparer.cleanup(item)
        }
        pendingAttachments = []
        sendAsDocument = false
        sendWithSpoiler = false
    }

    // MARK: - Sending, Editing, Deleting & Forwarding Messages

    func sendCurrentDraft() async {
        guard let chatId = activeChatId, !isSending else { return }

        if case .editing(let target) = composerMode {
            await commitEdit(target: target, in: chatId)
            return
        }

        let replyTarget = composerMode.replyingMessage

        if !pendingAttachments.isEmpty {
            await sendPendingAttachments(in: chatId, replyTarget: replyTarget)
            return
        }

        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let outgoingText = trimmed
        let tdReplyTo = replyTarget.map { TDLibService.makeReplyToMessage(messageId: $0.id) }
        draftText = ""
        composerMode = .normal
        errorMessage = nil
        isSending = true
        defer { isSending = false }

        do {
            let sentMessage = try await service.sendTextMessage(
                chatId: chatId,
                text: outgoingText,
                replyTo: tdReplyTo
            )
            guard activeChatId == chatId else { return }
            let item = MessageItem(tdMessage: sentMessage)
            upsertMessage(item)
            prefetchPermissions(for: [item])
            scrollToBottomTrigger += 1
        } catch {
            if activeChatId == chatId {
                draftText = outgoingText
                if let replyTarget {
                    composerMode = .replying(replyTarget)
                }
                errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
            }
        }
    }

    func sendVoiceNote(_ recorded: RecordedVoiceNote) async {
        guard let chatId = activeChatId, !isSending else { return }
        let replyTarget = composerMode.replyingMessage
        let tdReplyTo = replyTarget.map { TDLibService.makeReplyToMessage(messageId: $0.id) }

        composerMode = .normal
        errorMessage = nil
        isSending = true
        defer { isSending = false }

        do {
            let sentMessage = try await service.sendVoiceNote(
                chatId: chatId,
                filePath: recorded.fileURL.path,
                duration: recorded.duration,
                waveform: recorded.waveform,
                replyTo: tdReplyTo
            )
            guard activeChatId == chatId else { return }
            let item = MessageItem(tdMessage: sentMessage)
            upsertMessage(item)
            prefetchPermissions(for: [item])
            scrollToBottomTrigger += 1
        } catch {
            if activeChatId == chatId {
                if let replyTarget {
                    composerMode = .replying(replyTarget)
                }
                errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
            }
        }
    }

    func insertEmoji(_ emoji: String) {
        guard !emoji.isEmpty else { return }
        draftText.append(emoji)
        composerFocusTrigger += 1
    }

    func sendSticker(_ sticker: StickerItem, clearDraft: Bool = false) async {
        guard let chatId = activeChatId, !isSending else { return }
        if composerMode.isEditing {
            cancelComposerMode()
        }

        let replyTarget = composerMode.replyingMessage
        let tdReplyTo = replyTarget.map { TDLibService.makeReplyToMessage(messageId: $0.id) }
        let savedDraft = draftText

        if clearDraft {
            draftText = ""
        }
        composerMode = .normal
        errorMessage = nil
        isSending = true
        defer { isSending = false }

        do {
            let sentMessage = try await service.sendSticker(
                chatId: chatId,
                fileId: sticker.file.fileId,
                remoteFileId: sticker.remoteFileId,
                width: sticker.width,
                height: sticker.height,
                emoji: sticker.emoji,
                replyTo: tdReplyTo
            )
            guard activeChatId == chatId else { return }
            let item = MessageItem(tdMessage: sentMessage)
            upsertMessage(item)
            prefetchPermissions(for: [item])
            scrollToBottomTrigger += 1
        } catch {
            if activeChatId == chatId {
                if clearDraft {
                    draftText = savedDraft
                }
                if let replyTarget {
                    composerMode = .replying(replyTarget)
                }
                errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
            }
        }
    }

    @discardableResult
    func deleteMessages(_ messageIds: [Int64], revoke: Bool) async -> Bool {
        guard let chatId = activeChatId, !messageIds.isEmpty else { return false }
        errorMessage = nil

        do {
            try await service.deleteMessages(chatId: chatId, messageIds: messageIds, revoke: revoke)
            guard activeChatId == chatId else { return true }
            let deletedIds = Set(messageIds)
            messages.removeAll { deletedIds.contains($0.id) }
            handleDeletedMessageIds(deletedIds)
            return true
        } catch {
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
            return false
        }
    }

    @discardableResult
    func forwardMessages(
        _ messageIds: [Int64],
        fromChatId: Int64,
        toChatIds: [Int64],
        sendCopy: Bool = false,
        removeCaption: Bool = false,
        comment: String = ""
    ) async -> Bool {
        guard !messageIds.isEmpty, !toChatIds.isEmpty else { return false }
        errorMessage = nil

        let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let sortedIds = Array(Set(messageIds)).sorted()

        do {
            for targetChatId in toChatIds {
                let forwarded = try await service.forwardMessages(
                    toChatId: targetChatId,
                    fromChatId: fromChatId,
                    messageIds: sortedIds,
                    sendCopy: sendCopy,
                    removeCaption: removeCaption
                )

                if activeChatId == targetChatId {
                    let mapped = forwarded.map(MessageItem.init(tdMessage:))
                    for item in mapped {
                        upsertMessage(item)
                    }
                    prefetchPermissions(for: mapped)
                    scrollToBottomTrigger += 1
                }

                if !trimmedComment.isEmpty {
                    let commentMessage = try await service.sendTextMessage(
                        chatId: targetChatId,
                        text: trimmedComment
                    )
                    if activeChatId == targetChatId {
                        let item = MessageItem(tdMessage: commentMessage)
                        upsertMessage(item)
                        prefetchPermissions(for: [item])
                        scrollToBottomTrigger += 1
                    }
                }
            }

            exitSelectionMode()
            return true
        } catch {
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
            return false
        }
    }

    func markMessageContentOpened(messageId: Int64) {
        guard let chatId = activeChatId else { return }
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            messages[index].markContentOpened()
        }
        Task {
            _ = try? await service.openMessageContent(chatId: chatId, messageId: messageId)
        }
    }

    // MARK: - Bot Menu, Commands & Keyboard Actions

    func toggleReplyKeyboard() {
        guard activeReplyKeyboard != nil else { return }
        isReplyKeyboardVisible.toggle()
    }

    func sendImmediateText(_ text: String, replyToMessageId: Int64? = nil) async {
        guard let chatId = activeChatId else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let tdReplyTo = replyToMessageId.map { TDLibService.makeReplyToMessage(messageId: $0) }
        errorMessage = nil
        do {
            let sentMessage = try await service.sendTextMessage(
                chatId: chatId,
                text: trimmed,
                replyTo: tdReplyTo
            )
            guard activeChatId == chatId else { return }
            let item = MessageItem(tdMessage: sentMessage)
            upsertMessage(item)
            prefetchPermissions(for: [item])
            scrollToBottomTrigger += 1
        } catch {
            if activeChatId == chatId {
                errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
            }
        }
    }

    func sendBotCommand(
        _ command: BotCommandItem,
        botUsername: String? = nil,
        clearDraft: Bool = false
    ) async {
        let text: String
        if activeBotUserId == nil,
           let botUsername, !botUsername.isEmpty,
           botCommands.filter({ $0.command == command.command }).count > 1
        {
            text = "\(command.slashCommand)@\(botUsername)"
        } else {
            text = command.slashCommand
        }

        if clearDraft {
            draftText = ""
        }
        await sendImmediateText(text)
    }

    func fillBotCommand(_ command: BotCommandItem, botUsername: String? = nil) {
        let text: String
        if activeBotUserId == nil,
           let botUsername, !botUsername.isEmpty,
           botCommands.filter({ $0.command == command.command }).count > 1
        {
            text = "\(command.slashCommand)@\(botUsername) "
        } else {
            text = "\(command.slashCommand) "
        }
        draftText = text
        composerFocusTrigger += 1
    }

    func sendBotStart(parameter: String? = nil, botUserIdOverride: Int64? = nil) async {
        guard let chatId = activeChatId else { return }
        let effectiveParameter = parameter ?? pendingBotStart?.parameter ?? ""
        let effectiveBotUserId = botUserIdOverride ?? pendingBotStart?.botUserId ?? activeBotUserId
        pendingBotStart = nil

        if let botUserId = effectiveBotUserId {
            errorMessage = nil
            do {
                let sentMessage = try await service.sendBotStartMessage(
                    botUserId: botUserId,
                    chatId: chatId,
                    parameter: effectiveParameter
                )
                guard activeChatId == chatId else { return }
                let item = MessageItem(tdMessage: sentMessage)
                upsertMessage(item)
                prefetchPermissions(for: [item])
                scrollToBottomTrigger += 1
                return
            } catch {
                // Fall back to sending literal /start text below.
            }
        }
        let fallbackText = effectiveParameter.isEmpty ? "/start" : "/start \(effectiveParameter)"
        await sendImmediateText(fallbackText)
    }

    func openBotMenuWebApp() async {
        guard let chatId = activeChatId,
              let menuButton = botMenuButton,
              menuButton.hasCustomWebApp
        else {
            return
        }

        if let botUserId = activeBotUserId {
            if let webAppInfo = try? await service.openWebApp(
                chatId: chatId,
                botUserId: botUserId,
                url: menuButton.url
            ), let resolvedURL = URL(string: webAppInfo.url.url) {
                NSWorkspace.shared.open(resolvedURL)
                return
            }
            if let webAppUrl = try? await service.getWebAppUrl(
                botUserId: botUserId,
                url: menuButton.url
            ), let resolvedURL = URL(string: webAppUrl.url) {
                NSWorkspace.shared.open(resolvedURL)
                return
            }
        }

        openExternalURLString(menuButton.url)
    }

    func handleReplyKeyboardButton(_ button: ReplyKeyboardButtonItem) async {
        guard let chatId = activeChatId else { return }
        let replyTargetId: Int64? = (activeReplyKeyboard?.forceReply == true)
            ? activeReplyKeyboard?.messageId
            : nil

        switch button.action {
        case .text:
            if activeReplyKeyboard?.oneTime == true && activeReplyKeyboard?.isPersistent == false {
                isReplyKeyboardVisible = false
            }
            await sendImmediateText(button.text, replyToMessageId: replyTargetId)

        case .webApp(let url):
            if let botUserId = activeBotUserId {
                if let webAppUrl = try? await service.getWebAppUrl(botUserId: botUserId, url: url),
                   let resolved = URL(string: webAppUrl.url)
                {
                    NSWorkspace.shared.open(resolved)
                    return
                }
                if let webAppInfo = try? await service.openWebApp(chatId: chatId, botUserId: botUserId, url: url),
                   let resolved = URL(string: webAppInfo.url.url)
                {
                    NSWorkspace.shared.open(resolved)
                    return
                }
            }
            openExternalURLString(url)

        case .requestPhoneNumber:
            showTransientNotice("桌面端暂不支持通过机器人键盘直接发送手机号。")
        case .requestLocation:
            showTransientNotice("桌面端暂不支持通过机器人键盘直接发送实时位置。")
        case .requestPoll:
            showTransientNotice("暂不支持通过机器人键盘创建投票。")
        case .requestUsers, .requestChat:
            showTransientNotice("暂不支持通过机器人键盘选择并分享用户或群组。")
        case .requestManagedBot:
            showTransientNotice("暂不支持在当前客户端创建托管机器人。")
        }
    }

    func handleInlineKeyboardButton(
        _ button: InlineKeyboardButtonItem,
        on message: MessageItem,
        openUserChat: @escaping (Int64) -> Void,
        resolveBotUsername: @escaping (Int64) -> String?
    ) async {
        let chatId = message.chatId
        let buttonKey = "\(message.id):\(button.id)"
        guard activeChatId == chatId, !button.action.isDisabled else { return }

        switch button.action {
        case .callback(let data):
            await performCallbackQuery(
                chatId: chatId,
                messageId: message.id,
                buttonKey: buttonKey,
                buttonTitle: button.text,
                payload: .callbackQueryPayloadData(CallbackQueryPayloadData(data: data))
            )

        case .callbackWithPassword(let data):
            pendingPasswordCallback = BotCallbackPasswordRequest(
                chatId: chatId,
                messageId: message.id,
                buttonId: button.id,
                buttonText: button.text,
                payloadData: data
            )

        case .url(let urlString):
            openExternalURLString(urlString)

        case .loginUrl(let buttonId, let fallbackURL, _):
            inFlightCallbackButtonKey = buttonKey
            defer {
                if inFlightCallbackButtonKey == buttonKey {
                    inFlightCallbackButtonKey = nil
                }
            }
            if let httpUrl = try? await service.getLoginUrl(
                chatId: chatId,
                messageId: message.id,
                buttonId: buttonId,
                allowWriteAccess: false
            ) {
                openExternalURLString(httpUrl.url)
            } else {
                openExternalURLString(fallbackURL)
            }

        case .webApp(let urlString):
            inFlightCallbackButtonKey = buttonKey
            defer {
                if inFlightCallbackButtonKey == buttonKey {
                    inFlightCallbackButtonKey = nil
                }
            }
            let botUserId = resolvedBotUserId(for: message)
            if let botUserId,
               let webAppInfo = try? await service.openWebApp(
                chatId: chatId,
                botUserId: botUserId,
                url: urlString
               ),
               let resolvedURL = URL(string: webAppInfo.url.url)
            {
                NSWorkspace.shared.open(resolvedURL)
                return
            }
            openExternalURLString(urlString)

        case .switchInline(let query, _):
            let botUserId = resolvedBotUserId(for: message)
            let botUsername = botUserId.flatMap { resolveBotUsername($0) }
            if let botUsername, !botUsername.isEmpty {
                let prefix = "@\(botUsername) "
                draftText = query.isEmpty ? prefix : "\(prefix)\(query)"
            } else {
                draftText = query
            }
            composerFocusTrigger += 1

        case .copyText(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            showTransientNotice("已复制内容到剪贴板")

        case .user(let userId):
            openUserChat(userId)

        case .callbackGame:
            await performCallbackQuery(
                chatId: chatId,
                messageId: message.id,
                buttonKey: buttonKey,
                buttonTitle: button.text,
                payload: .callbackQueryPayloadGame(CallbackQueryPayloadGame(gameShortName: ""))
            )

        case .buy:
            showTransientNotice("暂不支持应用内支付，请在官方客户端完成付款。")

        case .disabled:
            break
        }
    }

    func submitPasswordCallback(_ request: BotCallbackPasswordRequest, password: String) async -> String? {
        let buttonKey = "\(request.messageId):\(request.buttonId)"
        let payload = CallbackQueryPayload.callbackQueryPayloadDataWithPassword(
            CallbackQueryPayloadDataWithPassword(data: request.payloadData, password: password)
        )
        return await performCallbackQuery(
            chatId: request.chatId,
            messageId: request.messageId,
            buttonKey: buttonKey,
            buttonTitle: request.buttonText,
            payload: payload
        )
    }

    @discardableResult
    private func performCallbackQuery(
        chatId: Int64,
        messageId: Int64,
        buttonKey: String,
        buttonTitle: String,
        payload: CallbackQueryPayload
    ) async -> String? {
        guard inFlightCallbackButtonKey == nil else { return nil }
        inFlightCallbackButtonKey = buttonKey
        defer {
            if inFlightCallbackButtonKey == buttonKey {
                inFlightCallbackButtonKey = nil
            }
        }

        do {
            let answer = try await service.getCallbackQueryAnswer(
                chatId: chatId,
                messageId: messageId,
                payload: payload
            )
            guard activeChatId == chatId else { return nil }

            let trimmedText = answer.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty {
                if answer.showAlert {
                    callbackAlert = BotCallbackAlert(
                        title: buttonTitle.isEmpty ? "机器人提示" : buttonTitle,
                        message: trimmedText
                    )
                } else {
                    showTransientNotice(trimmedText)
                }
            }

            let trimmedURL = answer.url.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedURL.isEmpty {
                openExternalURLString(trimmedURL)
            }
            return nil
        } catch {
            let message = TDLibErrorHelper.userFacingMessage(for: error)
            if let message, !message.isEmpty {
                showTransientNotice(message)
            }
            return message
        }
    }

    private func resolvedBotUserId(for message: MessageItem) -> Int64? {
        if case .user(let userId) = message.sender {
            return userId
        }
        return activeBotUserId
    }

    private func openExternalURLString(_ rawURL: String) {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = TelegramLinkDetector.normalizedURL(from: trimmed) else {
            showTransientNotice("无效链接地址")
            return
        }
        if TelegramLinkDetector.isTelegramLink(url), let onOpenTelegramURL {
            Task {
                await onOpenTelegramURL(url)
            }
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - TDLib Updates

    func handleUpdate(_ update: Update) {
        switch update {
        case .updateNewMessage(let info):
            guard info.message.chatId == activeChatId else { return }
            let item = MessageItem(tdMessage: info.message)
            if isViewingHistoricalAnchor && !item.isOutgoing {
                return
            }
            upsertMessage(item)
            prefetchPermissions(for: [item])
            if !item.isOutgoing {
                markAsRead(chatId: info.message.chatId, messageIds: [info.message.id])
            }

        case .updateMessageSendSucceeded(let info):
            guard info.message.chatId == activeChatId else { return }
            let item = MessageItem(tdMessage: info.message)
            replaceMessage(oldId: info.oldMessageId, with: item)
            messagePermissions.removeValue(forKey: info.oldMessageId)
            if selectedMessageIds.remove(info.oldMessageId) != nil {
                selectedMessageIds.insert(item.id)
            }
            if case .replying(let replyMsg) = composerMode, replyMsg.id == info.oldMessageId {
                composerMode = .replying(item)
            }
            prefetchPermissions(for: [item])

        case .updateMessageSendFailed(let info):
            guard info.message.chatId == activeChatId else { return }
            replaceMessage(oldId: info.oldMessageId, with: MessageItem(tdMessage: info.message))
            errorMessage = TDLibErrorHelper.userFacingMessage(for: info.error)

        case .updateMessageContent(let info):
            guard info.chatId == activeChatId else { return }
            let newDisplayContent = MessageDisplayContent(from: info.newContent)
            if let index = messages.firstIndex(where: { $0.id == info.messageId }) {
                messages[index].content = newDisplayContent
            }
            if case .loaded(var replied) = repliedMessages[info.messageId] {
                replied.content = newDisplayContent
                repliedMessages[info.messageId] = .loaded(replied)
            }
            if case .replying(var target) = composerMode, target.id == info.messageId {
                target.content = newDisplayContent
                composerMode = .replying(target)
            }

        case .updateMessageContentOpened(let info):
            guard info.chatId == activeChatId else { return }
            if let index = messages.firstIndex(where: { $0.id == info.messageId }) {
                messages[index].markContentOpened()
            }

        case .updateMessageEdited(let info):
            guard info.chatId == activeChatId else { return }
            let editDate = info.editDate > 0
                ? Foundation.Date(timeIntervalSince1970: TimeInterval(info.editDate))
                : nil
            let updatedReplyMarkup = info.replyMarkup.map {
                MessageReplyMarkup(from: $0, messageId: info.messageId)
            }
            if let index = messages.firstIndex(where: { $0.id == info.messageId }) {
                messages[index].editDate = editDate
                messages[index].replyMarkup = updatedReplyMarkup
            }
            if case .loaded(var replied) = repliedMessages[info.messageId] {
                replied.editDate = editDate
                replied.replyMarkup = updatedReplyMarkup
                repliedMessages[info.messageId] = .loaded(replied)
            }

        case .updateChatReplyMarkup(let info):
            guard info.chatId == activeChatId else { return }
            if let tdMessage = info.replyMarkupMessage {
                let item = MessageItem(tdMessage: tdMessage)
                applyChatReplyMarkup(item.replyMarkup, sourceMessage: item)
            } else {
                clearChatReplyMarkup()
            }

        case .updateUserFullInfo(let info):
            if let activeBotUserId, info.userId == activeBotUserId {
                applyBotInfo(info.userFullInfo.botInfo, botUserId: info.userId)
            } else if case .privateUser(let userId) = activeChatKind,
                      info.userId == userId,
                      let botInfo = info.userFullInfo.botInfo
            {
                activeBotUserId = userId
                applyBotInfo(botInfo, botUserId: userId)
            }

        case .updateBasicGroupFullInfo(let info):
            if case .basicGroup(let groupId) = activeChatKind, groupId == info.basicGroupId {
                applyGroupBotCommands(info.basicGroupFullInfo.botCommands)
            }

        case .updateSupergroup(let info):
            switch activeChatKind {
            case .supergroup(let supergroupId) where supergroupId == info.supergroup.id,
                 .channel(let supergroupId) where supergroupId == info.supergroup.id:
                applySupergroupMembership(info.supergroup)
            default:
                break
            }

        case .updateSupergroupFullInfo(let info):
            if case .supergroup(let supergroupId) = activeChatKind, supergroupId == info.supergroupId {
                applyGroupBotCommands(info.supergroupFullInfo.botCommands)
            }

        case .updateMessageIsPinned(let info):
            guard info.chatId == activeChatId else { return }
            if let index = messages.firstIndex(where: { $0.id == info.messageId }) {
                messages[index].isPinned = info.isPinned
            }

        case .updateDeleteMessages(let info):
            guard info.chatId == activeChatId, !info.fromCache else { return }
            let deletedIds = Set(info.messageIds)
            messages.removeAll { deletedIds.contains($0.id) }
            handleDeletedMessageIds(deletedIds)
            if let kb = activeReplyKeyboard, deletedIds.contains(kb.messageId) {
                clearChatReplyMarkup()
            }

        default:
            break
        }
    }

    func reset() {
        loadTask?.cancel()
        botContextTask?.cancel()
        highlightClearTask?.cancel()
        noticeClearTask?.cancel()
        activeChatId = nil
        activeChatKind = nil
        activeBotUserId = nil
        pendingJumpMessageId = nil
        messages = []
        draftText = ""
        savedDraftBeforeEditing = ""
        composerMode = .normal
        repliedMessages = [:]
        messagePermissions = [:]
        inFlightReplyFetchIds = []
        inFlightPermissionIds = []
        highlightedEntryId = nil
        scrollToMessageRequest = nil
        isSelectionMode = false
        selectedMessageIds = []
        botCommands = []
        botMenuButton = nil
        botDescription = ""
        activeReplyKeyboard = nil
        isReplyKeyboardVisible = false
        activeInputPlaceholder = nil
        inFlightCallbackButtonKey = nil
        callbackAlert = nil
        pendingPasswordCallback = nil
        pendingBotStart = nil
        canJoinActiveChat = false
        activeChatJoinRequiresRequest = false
        isJoiningActiveChat = false
        isViewingHistoricalAnchor = false
        clearPendingAttachments()
        errorMessage = nil
        noticeMessage = nil
        hasMoreOlder = true
        isLoadingInitial = false
        isLoadingOlder = false
        isSending = false
        isPreparingAttachments = false
    }

    // MARK: - Private Bot Context & Reply Markup Helpers

    private func loadBotAndMarkupContext(for chatId: Int64) async {
        guard let tdChat = try? await service.getChat(chatId: chatId),
              !Task.isCancelled,
              activeChatId == chatId
        else {
            return
        }

        let kind = ChatKind(from: tdChat.type)
        activeChatKind = kind

        if tdChat.replyMarkupMessageId != 0 {
            if let existing = messages.first(where: { $0.id == tdChat.replyMarkupMessageId }) {
                applyChatReplyMarkup(existing.replyMarkup, sourceMessage: existing)
            } else if let tdMarkupMsg = try? await service.getMessage(
                chatId: chatId,
                messageId: tdChat.replyMarkupMessageId
            ), !Task.isCancelled, activeChatId == chatId {
                let item = MessageItem(tdMessage: tdMarkupMsg)
                applyChatReplyMarkup(item.replyMarkup, sourceMessage: item)
            }
        }

        switch kind {
        case .privateUser(let userId):
            if let tdUser = try? await service.getUser(userId: userId),
               !Task.isCancelled,
               activeChatId == chatId,
               case .userTypeBot = tdUser.type
            {
                activeBotUserId = userId
                if let fullInfo = try? await service.getUserFullInfo(userId: userId),
                   !Task.isCancelled,
                   activeChatId == chatId
                {
                    applyBotInfo(fullInfo.botInfo, botUserId: userId)
                }
            }

        case .basicGroup(let groupId):
            if let fullInfo = try? await service.getBasicGroupFullInfo(basicGroupId: groupId),
               !Task.isCancelled,
               activeChatId == chatId
            {
                applyGroupBotCommands(fullInfo.botCommands)
            }

        case .supergroup(let supergroupId):
            if let supergroup = try? await service.getSupergroup(supergroupId: supergroupId),
               !Task.isCancelled,
               activeChatId == chatId
            {
                applySupergroupMembership(supergroup)
            }
            if let fullInfo = try? await service.getSupergroupFullInfo(supergroupId: supergroupId),
               !Task.isCancelled,
               activeChatId == chatId
            {
                applyGroupBotCommands(fullInfo.botCommands)
            }

        case .channel(let supergroupId):
            if let supergroup = try? await service.getSupergroup(supergroupId: supergroupId),
               !Task.isCancelled,
               activeChatId == chatId
            {
                applySupergroupMembership(supergroup)
            }

        case .secret:
            break
        }
    }

    private func applySupergroupMembership(_ supergroup: Supergroup) {
        if case .chatMemberStatusLeft = supergroup.status {
            canJoinActiveChat = true
            activeChatJoinRequiresRequest = supergroup.joinByRequest
        } else {
            canJoinActiveChat = false
            activeChatJoinRequiresRequest = false
        }
    }

    private func applyBotInfo(_ botInfo: BotInfo?, botUserId: Int64) {
        guard let botInfo else {
            botCommands = []
            botMenuButton = nil
            botDescription = ""
            return
        }

        botCommands = botInfo.commands.map { BotCommandItem(tdCommand: $0, botUserId: botUserId) }
        if let menuBtn = botInfo.menuButton {
            let mapped = BotMenuButtonItem(tdMenuButton: menuBtn)
            botMenuButton = mapped.hasCustomWebApp ? mapped : nil
        } else {
            botMenuButton = nil
        }
        botDescription = botInfo.description.isEmpty ? botInfo.shortDescription : botInfo.description
    }

    private func applyGroupBotCommands(_ groupCommands: [BotCommands]) {
        var flattened: [BotCommandItem] = []
        for entry in groupCommands {
            for cmd in entry.commands {
                flattened.append(BotCommandItem(tdCommand: cmd, botUserId: entry.botUserId))
            }
        }
        botCommands = flattened
    }

    private func applyChatReplyMarkup(_ markup: MessageReplyMarkup?, sourceMessage: MessageItem?) {
        guard let markup else {
            clearChatReplyMarkup()
            return
        }

        switch markup {
        case .showKeyboard(let keyboard):
            if keyboard.isEmpty {
                clearChatReplyMarkup()
            } else {
                activeReplyKeyboard = keyboard
                isReplyKeyboardVisible = true
                activeInputPlaceholder = keyboard.inputFieldPlaceholder.isEmpty ? nil : keyboard.inputFieldPlaceholder
            }

        case .removeKeyboard:
            clearChatReplyMarkup()

        case .forceReply(let placeholder, _):
            activeReplyKeyboard = nil
            isReplyKeyboardVisible = false
            activeInputPlaceholder = placeholder.isEmpty ? nil : placeholder
            if let sourceMessage, composerMode == .normal {
                composerMode = .replying(sourceMessage)
            }

        case .inlineKeyboard:
            clearChatReplyMarkup()
        }
    }

    private func clearChatReplyMarkup() {
        activeReplyKeyboard = nil
        isReplyKeyboardVisible = false
        activeInputPlaceholder = nil
    }

    // MARK: - Private Edit & Media Dispatch

    private func commitEdit(target: MessageItem, in chatId: Int64) async {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if target.content.isTextMessage && trimmed.isEmpty {
            return
        }

        let originalTrimmed = target.content.editableText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == originalTrimmed {
            cancelComposerMode()
            return
        }

        errorMessage = nil
        isSending = true
        defer { isSending = false }

        do {
            let edited: Message
            if target.content.isTextMessage {
                edited = try await service.editMessageText(
                    chatId: chatId,
                    messageId: target.id,
                    text: trimmed
                )
            } else {
                edited = try await service.editMessageCaption(
                    chatId: chatId,
                    messageId: target.id,
                    caption: trimmed,
                    showCaptionAboveMedia: target.content.showCaptionAboveMedia
                )
            }

            guard activeChatId == chatId else { return }
            let updatedItem = MessageItem(tdMessage: edited)
            upsertMessage(updatedItem)
            if repliedMessages[updatedItem.id] != nil {
                repliedMessages[updatedItem.id] = .loaded(updatedItem)
            }
            composerMode = .normal
            draftText = savedDraftBeforeEditing
            savedDraftBeforeEditing = ""
        } catch {
            if activeChatId == chatId {
                errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
            }
        }
    }

    private func sendPendingAttachments(in chatId: Int64, replyTarget: MessageItem?) async {
        let attachments = pendingAttachments
        let caption = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let asDocument = sendAsDocument
        let spoiler = sendWithSpoiler && !asDocument
        let tdReplyTo = replyTarget.map { TDLibService.makeReplyToMessage(messageId: $0.id) }

        // Keep staged files on disk because TDLib uploads asynchronously in the background.
        pendingAttachments = []
        draftText = ""
        sendAsDocument = false
        sendWithSpoiler = false
        composerMode = .normal
        errorMessage = nil
        isSending = true
        defer { isSending = false }

        do {
            let canGroupAsAlbum = Self.canSendAsAlbum(attachments: attachments, sendAsDocument: asDocument)
            var sentMessages: [Message] = []

            if canGroupAsAlbum {
                var offset = 0
                while offset < attachments.count {
                    let end = min(offset + 10, attachments.count)
                    let slice = Array(attachments[offset..<end])
                    let contents: [InputMessageContent] = slice.enumerated().map { index, item in
                        let itemCaption = (offset == 0 && index == 0) ? caption : ""
                        return TDLibService.makeInputContent(
                            for: item,
                            caption: itemCaption,
                            sendAsDocument: asDocument,
                            hasSpoiler: spoiler
                        )
                    }
                    let batch = try await service.sendMessageAlbum(
                        chatId: chatId,
                        contents: contents,
                        replyTo: offset == 0 ? tdReplyTo : nil
                    )
                    sentMessages.append(contentsOf: batch)
                    offset = end
                }
            } else {
                for (index, item) in attachments.enumerated() {
                    let itemCaption = index == 0 ? caption : ""
                    let content = TDLibService.makeInputContent(
                        for: item,
                        caption: itemCaption,
                        sendAsDocument: asDocument,
                        hasSpoiler: spoiler
                    )
                    let msg = try await service.sendMessage(
                        chatId: chatId,
                        content: content,
                        replyTo: index == 0 ? tdReplyTo : nil
                    )
                    sentMessages.append(msg)
                }
            }

            guard activeChatId == chatId else { return }
            let mapped = sentMessages.map(MessageItem.init(tdMessage:))
            for item in mapped {
                upsertMessage(item)
            }
            prefetchPermissions(for: mapped)
            scrollToBottomTrigger += 1
        } catch {
            if activeChatId == chatId {
                pendingAttachments = attachments
                draftText = caption
                sendAsDocument = asDocument
                sendWithSpoiler = spoiler
                if let replyTarget {
                    composerMode = .replying(replyTarget)
                }
                errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
            }
        }
    }

    private func handleDeletedMessageIds(_ deletedIds: Set<Int64>) {
        for id in deletedIds {
            messagePermissions.removeValue(forKey: id)
            selectedMessageIds.remove(id)
            if repliedMessages[id] != nil {
                repliedMessages[id] = .deleted
            }
        }
        if isSelectionMode && selectedMessageIds.isEmpty {
            isSelectionMode = false
        }
        switch composerMode {
        case .replying(let target) where deletedIds.contains(target.id):
            composerMode = .normal
        case .editing(let target) where deletedIds.contains(target.id):
            cancelComposerMode()
        default:
            break
        }
    }

    /// Checks TDLib's album grouping rules:
    /// - Photos & videos may be mixed in one album.
    /// - Documents may be grouped only with documents.
    /// - Audios may be grouped only with audios.
    /// - Animations (GIFs) cannot be grouped in albums.
    private static func canSendAsAlbum(attachments: [PendingAttachment], sendAsDocument: Bool) -> Bool {
        guard attachments.count >= 2 else { return false }
        if sendAsDocument {
            return true
        }
        let allPhotoOrVideo = attachments.allSatisfy { $0.kind == .photo || $0.kind == .video }
        if allPhotoOrVideo { return true }
        let allDocuments = attachments.allSatisfy { $0.kind == .document }
        if allDocuments { return true }
        let allAudios = attachments.allSatisfy { $0.kind == .audio }
        return allAudios
    }

    // MARK: - Private History Helpers

    private func loadInitialHistory(for chatId: Int64) async {
        isLoadingInitial = true
        defer { isLoadingInitial = false }

        _ = try? await service.openChat(chatId: chatId)
        guard !Task.isCancelled, activeChatId == chatId else { return }

        do {
            var collected: [Message] = []
            let firstBatch = try await service.getChatHistory(
                chatId: chatId,
                fromMessageId: 0,
                limit: 40,
                offset: 0,
                onlyLocal: false
            )
            guard !Task.isCancelled, activeChatId == chatId else { return }
            collected.append(contentsOf: firstBatch)

            // TDLib's first `getChatHistory` call often returns only the locally cached last message.
            // Fetch one additional page from the server immediately so the viewport fills naturally.
            if collected.count < 15, let oldest = collected.last?.id {
                let secondBatch = try await service.getChatHistory(
                    chatId: chatId,
                    fromMessageId: oldest,
                    limit: 40,
                    offset: 0,
                    onlyLocal: false
                )
                guard !Task.isCancelled, activeChatId == chatId else { return }
                collected.append(contentsOf: secondBatch)
                if secondBatch.isEmpty {
                    hasMoreOlder = false
                }
            } else if firstBatch.isEmpty {
                hasMoreOlder = false
            }

            let items = collected.map(MessageItem.init(tdMessage:))
            mergeMessages(items)
            prefetchPermissions(for: items)

            let unreadIncomingIds = messages.suffix(20).filter { !$0.isOutgoing }.map(\.id)
            markAsRead(chatId: chatId, messageIds: unreadIncomingIds)

            if let targetId = pendingJumpMessageId {
                pendingJumpMessageId = nil
                isLoadingInitial = false
                await jumpToMessage(id: targetId)
            } else {
                scrollToBottomTrigger += 1
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
        }
    }

    private func markAsRead(chatId: Int64, messageIds: [Int64]) {
        guard !messageIds.isEmpty else { return }
        Task {
            _ = try? await service.viewMessages(chatId: chatId, messageIds: messageIds)
        }
    }

    private func upsertMessage(_ item: MessageItem) {
        if let index = messages.firstIndex(where: { $0.id == item.id }) {
            messages[index] = item
        } else {
            messages.append(item)
            messages.sort(by: Self.chronologicalOrder)
        }
    }

    private func replaceMessage(oldId: Int64, with newItem: MessageItem) {
        messages.removeAll { $0.id == oldId || $0.id == newItem.id }
        messages.append(newItem)
        messages.sort(by: Self.chronologicalOrder)
    }

    private func mergeMessages(_ newItems: [MessageItem]) {
        var byId = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        for item in newItems {
            byId[item.id] = item
        }
        messages = byId.values.sorted(by: Self.chronologicalOrder)
    }

    private static func chronologicalOrder(_ lhs: MessageItem, _ rhs: MessageItem) -> Bool {
        if lhs.date != rhs.date {
            return lhs.date < rhs.date
        }
        return lhs.id < rhs.id
    }
}
