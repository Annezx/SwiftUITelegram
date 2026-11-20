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
    private(set) var scrollToBottomTrigger: Int = 0

    var draftText: String = ""
    var errorMessage: String?

    init(service: TDLibService) {
        self.service = service
    }

    func selectChat(_ chatId: Int64?) {
        guard activeChatId != chatId else { return }

        let previousChatId = activeChatId
        activeChatId = chatId
        loadTask?.cancel()
        messages = []
        draftText = ""
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

    func sendCurrentDraft() async {
        guard let chatId = activeChatId else { return }
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }

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
        errorMessage = nil
        hasMoreOlder = true
        isLoadingInitial = false
        isLoadingOlder = false
        isSending = false
    }

    // MARK: - Private

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
