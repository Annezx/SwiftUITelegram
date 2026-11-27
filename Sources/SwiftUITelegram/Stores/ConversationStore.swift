import AppKit
import Foundation
import Observation
import TDLibKit

@MainActor
@Observable
final class ConversationStore {
    private let service: TDLibService
    private var loadTask: Task<Void, Never>?

    private(set) var activeChatId: Int64?
    private(set) var messages: [MessageItem] = []
    private(set) var isLoadingInitial: Bool = false
    private(set) var isLoadingOlder: Bool = false
    private(set) var hasMoreOlder: Bool = true
    private(set) var isSending: Bool = false
    private(set) var isPreparingAttachments: Bool = false
    private(set) var pendingAttachments: [PendingAttachment] = []
    private(set) var scrollToBottomTrigger: Int = 0

    var draftText: String = ""
    var sendAsDocument: Bool = false
    var sendWithSpoiler: Bool = false
    var errorMessage: String?

    init(service: TDLibService) {
        self.service = service
    }

    var timelineEntries: [ConversationTimelineEntry] {
        ConversationTimelineEntry.group(messages)
    }

    var hasSendableContent: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty
    }

    var hasToggleableOriginalMedia: Bool {
        pendingAttachments.contains { $0.supportsOriginalFileToggle }
    }

    var hasSpoilerCapableMedia: Bool {
        !sendAsDocument && pendingAttachments.contains { $0.supportsSpoiler }
    }

    func selectChat(_ chatId: Int64?) {
        guard activeChatId != chatId else { return }

        let previousChatId = activeChatId
        activeChatId = chatId
        loadTask?.cancel()
        messages = []
        draftText = ""
        clearPendingAttachments()
        errorMessage = nil
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
        } catch {
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
        }
    }

    // MARK: - Attachments Staging

    func stageAttachmentURLs(_ urls: [URL], forceDocument: Bool = false) {
        guard activeChatId != nil, !urls.isEmpty else { return }
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

    // MARK: - Sending Messages & Media

    func sendCurrentDraft() async {
        guard let chatId = activeChatId, !isSending else { return }

        if !pendingAttachments.isEmpty {
            await sendPendingAttachments(in: chatId)
            return
        }

        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let outgoingText = trimmed
        draftText = ""
        errorMessage = nil
        isSending = true
        defer { isSending = false }

        do {
            let sentMessage = try await service.sendTextMessage(chatId: chatId, text: outgoingText)
            guard activeChatId == chatId else { return }
            upsertMessage(MessageItem(tdMessage: sentMessage))
            scrollToBottomTrigger += 1
        } catch {
            draftText = outgoingText
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
        }
    }

    func sendVoiceNote(_ recorded: RecordedVoiceNote) async {
        guard let chatId = activeChatId, !isSending else { return }
        errorMessage = nil
        isSending = true
        defer { isSending = false }

        do {
            let sentMessage = try await service.sendVoiceNote(
                chatId: chatId,
                filePath: recorded.fileURL.path,
                duration: recorded.duration,
                waveform: recorded.waveform
            )
            guard activeChatId == chatId else { return }
            upsertMessage(MessageItem(tdMessage: sentMessage))
            scrollToBottomTrigger += 1
        } catch {
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
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

    // MARK: - TDLib Updates

    func handleUpdate(_ update: Update) {
        switch update {
        case .updateNewMessage(let info):
            guard info.message.chatId == activeChatId else { return }
            let item = MessageItem(tdMessage: info.message)
            upsertMessage(item)
            if !item.isOutgoing {
                markAsRead(chatId: info.message.chatId, messageIds: [info.message.id])
            }

        case .updateMessageSendSucceeded(let info):
            guard info.message.chatId == activeChatId else { return }
            replaceMessage(oldId: info.oldMessageId, with: MessageItem(tdMessage: info.message))

        case .updateMessageSendFailed(let info):
            guard info.message.chatId == activeChatId else { return }
            replaceMessage(oldId: info.oldMessageId, with: MessageItem(tdMessage: info.message))
            errorMessage = TDLibErrorHelper.userFacingMessage(for: info.error)

        case .updateMessageContent(let info):
            guard info.chatId == activeChatId else { return }
            if let index = messages.firstIndex(where: { $0.id == info.messageId }) {
                messages[index].content = MessageDisplayContent(from: info.newContent)
            }

        case .updateMessageContentOpened(let info):
            guard info.chatId == activeChatId else { return }
            if let index = messages.firstIndex(where: { $0.id == info.messageId }) {
                messages[index].markContentOpened()
            }

        case .updateMessageEdited(let info):
            guard info.chatId == activeChatId else { return }
            if let index = messages.firstIndex(where: { $0.id == info.messageId }) {
                messages[index].editDate = info.editDate > 0
                    ? Foundation.Date(timeIntervalSince1970: TimeInterval(info.editDate))
                    : nil
            }

        case .updateDeleteMessages(let info):
            guard info.chatId == activeChatId, info.isPermanent else { return }
            let deletedIds = Set(info.messageIds)
            messages.removeAll { deletedIds.contains($0.id) }

        default:
            break
        }
    }

    func reset() {
        loadTask?.cancel()
        activeChatId = nil
        messages = []
        draftText = ""
        clearPendingAttachments()
        errorMessage = nil
        hasMoreOlder = true
        isLoadingInitial = false
        isLoadingOlder = false
        isSending = false
        isPreparingAttachments = false
    }

    // MARK: - Private Media Dispatch

    private func sendPendingAttachments(in chatId: Int64) async {
        let attachments = pendingAttachments
        let caption = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let asDocument = sendAsDocument
        let spoiler = sendWithSpoiler && !asDocument

        // Keep staged files on disk because TDLib uploads asynchronously in the background.
        pendingAttachments = []
        draftText = ""
        sendAsDocument = false
        sendWithSpoiler = false
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
                    let batch = try await service.sendMessageAlbum(chatId: chatId, contents: contents)
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
                    let msg = try await service.sendMessage(chatId: chatId, content: content)
                    sentMessages.append(msg)
                }
            }

            guard activeChatId == chatId else { return }
            for msg in sentMessages {
                upsertMessage(MessageItem(tdMessage: msg))
            }
            scrollToBottomTrigger += 1
        } catch {
            if activeChatId == chatId {
                pendingAttachments = attachments
                draftText = caption
                sendAsDocument = asDocument
                sendWithSpoiler = spoiler
                errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
            }
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
            scrollToBottomTrigger += 1

            let unreadIncomingIds = messages.suffix(20).filter { !$0.isOutgoing }.map(\.id)
            markAsRead(chatId: chatId, messageIds: unreadIncomingIds)
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
