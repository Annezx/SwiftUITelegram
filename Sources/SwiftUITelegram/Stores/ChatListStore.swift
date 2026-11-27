import Foundation
import Observation
import TDLibKit

@MainActor
@Observable
final class ChatListStore {
    private let service: TDLibService
    private var searchTask: Task<Void, Never>?
    private var inFlightUserIds: Set<Int64> = []
    private var inFlightChatIds: Set<Int64> = []

    private(set) var chatsById: [Int64: ChatSummary] = [:]
    private(set) var usersById: [Int64: UserSummary] = [:]
    private(set) var isLoadingChats: Bool = false
    private(set) var hasReachedEnd: [ChatListFilter: Bool] = [:]
    private(set) var remoteSearchChatIds: [Int64] = []

    var selectedFilter: ChatListFilter = .main
    var selectedChatId: Int64?
    var searchQuery: String = ""
    var errorMessage: String?

    init(service: TDLibService) {
        self.service = service
    }

    var selectedChat: ChatSummary? {
        guard let selectedChatId else { return nil }
        return chatsById[selectedChatId]
    }

    /// Chats sorted strictly by TDLib's `(order, chat.id)` descending specification.
    var visibleChats: [ChatSummary] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedQuery.isEmpty {
            let localMatches = chatsById.values.filter { chat in
                chat.title.localizedCaseInsensitiveContains(trimmedQuery)
                    || chat.lastMessagePreview.localizedCaseInsensitiveContains(trimmedQuery)
            }
            var merged: [Int64: ChatSummary] = Dictionary(uniqueKeysWithValues: localMatches.map { ($0.id, $0) })
            for chatId in remoteSearchChatIds {
                if let chat = chatsById[chatId] {
                    merged[chatId] = chat
                }
            }
            return merged.values.sorted { lhs, rhs in
                let lhsOrder = lhs.order(in: .main)
                let rhsOrder = rhs.order(in: .main)
                if lhsOrder != rhsOrder { return lhsOrder > rhsOrder }
                return lhs.id > rhs.id
            }
        }

        let filter = selectedFilter
        return chatsById.values
            .filter { $0.order(in: filter) != 0 }
            .sorted { lhs, rhs in
                let lhsOrder = lhs.order(in: filter)
                let rhsOrder = rhs.order(in: filter)
                if lhsOrder != rhsOrder { return lhsOrder > rhsOrder }
                return lhs.id > rhs.id
            }
    }

    /// All known chats sorted by main-list order then archive-list order, suitable for target pickers such as forwarding.
    var allSortedChats: [ChatSummary] {
        chatsById.values.sorted { lhs, rhs in
            let lhsMain = lhs.order(in: .main)
            let rhsMain = rhs.order(in: .main)
            if lhsMain != rhsMain { return lhsMain > rhsMain }
            let lhsArchive = lhs.order(in: .archive)
            let rhsArchive = rhs.order(in: .archive)
            if lhsArchive != rhsArchive { return lhsArchive > rhsArchive }
            return lhs.id > rhs.id
        }
    }

    func loadMoreChats(for filter: ChatListFilter? = nil) async {
        let targetFilter = filter ?? selectedFilter
        guard !isLoadingChats, hasReachedEnd[targetFilter] != true else { return }

        isLoadingChats = true
        defer { isLoadingChats = false }

        do {
            try await service.loadChats(list: targetFilter.tdChatList, limit: 40)
            await syncKnownChats(for: targetFilter)
        } catch {
            if TDLibErrorHelper.isNotFound(error) {
                hasReachedEnd[targetFilter] = true
                await syncKnownChats(for: targetFilter)
            } else {
                errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
            }
        }
    }

    func refreshCurrentList() async {
        hasReachedEnd[selectedFilter] = false
        await loadMoreChats(for: selectedFilter)
    }

    func updateSearchQuery(_ query: String) {
        searchQuery = query
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            remoteSearchChatIds = []
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            do {
                let ids = try await service.searchChats(query: trimmed, limit: 30)
                guard !Task.isCancelled else { return }
                remoteSearchChatIds = ids
                for id in ids where chatsById[id] == nil {
                    if let tdChat = try? await service.getChat(chatId: id) {
                        chatsById[tdChat.id] = ChatSummary(tdChat: tdChat)
                    }
                }
            } catch {
                // Local search still displays cached chats cleanly.
            }
        }
    }

    func searchForwardTargets(query: String) async -> [ChatSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return allSortedChats
        }

        let localMatches = chatsById.values.filter { chat in
            chat.title.localizedCaseInsensitiveContains(trimmed)
        }
        var merged = Dictionary(uniqueKeysWithValues: localMatches.map { ($0.id, $0) })

        if let ids = try? await service.searchChats(query: trimmed, limit: 30) {
            for id in ids {
                if let existing = chatsById[id] {
                    merged[id] = existing
                } else if let tdChat = try? await service.getChat(chatId: id) {
                    let summary = ChatSummary(tdChat: tdChat)
                    chatsById[tdChat.id] = summary
                    merged[tdChat.id] = summary
                }
            }
        }

        return merged.values.sorted { lhs, rhs in
            let lhsOrder = lhs.order(in: .main)
            let rhsOrder = rhs.order(in: .main)
            if lhsOrder != rhsOrder { return lhsOrder > rhsOrder }
            return lhs.id > rhs.id
        }
    }

    func ensureSavedMessagesChat(currentUserId: Int64) async -> ChatSummary? {
        if let existing = chatsById.values.first(where: { chat in
            if case .privateUser(let userId) = chat.kind {
                return userId == currentUserId
            }
            return false
        }) {
            return existing
        }

        if let tdChat = try? await service.createPrivateChat(userId: currentUserId, force: false) {
            let summary = ChatSummary(tdChat: tdChat)
            chatsById[summary.id] = summary
            return summary
        }
        return nil
    }

    func openChatByUsername(_ username: String) async -> String? {
        let cleaned = username.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !cleaned.isEmpty else { return nil }

        do {
            let tdChat = try await service.searchPublicChat(username: cleaned)
            let summary = ChatSummary(tdChat: tdChat)
            chatsById[summary.id] = summary
            selectedChatId = summary.id
            return nil
        } catch {
            return TDLibErrorHelper.userFacingMessage(for: error) ?? "无法打开 @\(cleaned)"
        }
    }

    func openPrivateChat(userId: Int64) async -> String? {
        do {
            let tdChat = try await service.createPrivateChat(userId: userId, force: false)
            let summary = ChatSummary(tdChat: tdChat)
            chatsById[summary.id] = summary
            selectedChatId = summary.id
            return nil
        } catch {
            return TDLibErrorHelper.userFacingMessage(for: error) ?? "无法打开该用户的对话"
        }
    }

    func senderDisplayName(for sender: MessageSenderKind) -> String? {
        switch sender {
        case .user(let userId):
            if let user = usersById[userId] {
                return user.displayName
            }
            ensureUserLoaded(userId: userId)
            return nil
        case .chat(let chatId):
            if let chat = chatsById[chatId] {
                return chat.title
            }
            ensureChatLoaded(chatId: chatId)
            return nil
        }
    }

    func originDisplayName(for origin: MessageOriginInfo) -> String {
        switch origin {
        case .user(let userId):
            if let user = usersById[userId] {
                return user.displayName
            }
            ensureUserLoaded(userId: userId)
            return "用户"

        case .hiddenUser(let senderName):
            return senderName.isEmpty ? "隐藏用户" : senderName

        case .chat(let chatId, let authorSignature):
            let base: String
            if let chat = chatsById[chatId] {
                base = chat.title
            } else {
                ensureChatLoaded(chatId: chatId)
                base = "群组"
            }
            return authorSignature.isEmpty ? base : "\(base) (\(authorSignature))"

        case .channel(let chatId, _, let authorSignature):
            let base: String
            if let chat = chatsById[chatId] {
                base = chat.title
            } else {
                ensureChatLoaded(chatId: chatId)
                base = "频道"
            }
            return authorSignature.isEmpty ? base : "\(base) (\(authorSignature))"
        }
    }

    func subtitle(for chat: ChatSummary) -> String {
        switch chat.kind {
        case .privateUser(let userId):
            if let user = usersById[userId] {
                return user.statusText.isEmpty ? "私聊" : user.statusText
            }
            ensureUserLoaded(userId: userId)
            return "私聊"
        case .basicGroup:
            return "群组"
        case .supergroup:
            return "超级群组"
        case .channel:
            return "频道"
        case .secret:
            return "加密对话"
        }
    }

    func ensureUserLoaded(userId: Int64) {
        guard usersById[userId] == nil, !inFlightUserIds.contains(userId) else { return }
        inFlightUserIds.insert(userId)

        Task {
            defer { inFlightUserIds.remove(userId) }
            if let tdUser = try? await service.getUser(userId: userId) {
                usersById[tdUser.id] = UserSummary(tdUser: tdUser)
            }
        }
    }

    func ensureChatLoaded(chatId: Int64) {
        guard chatId != 0, chatsById[chatId] == nil, !inFlightChatIds.contains(chatId) else { return }
        inFlightChatIds.insert(chatId)

        Task {
            defer { inFlightChatIds.remove(chatId) }
            if let tdChat = try? await service.getChat(chatId: chatId) {
                chatsById[tdChat.id] = ChatSummary(tdChat: tdChat)
            }
        }
    }

    // MARK: - TDLib Updates

    func handleUpdate(_ update: Update) {
        switch update {
        case .updateNewChat(let info):
            chatsById[info.chat.id] = ChatSummary(tdChat: info.chat)

        case .updateChatTitle(let info):
            chatsById[info.chatId]?.title = info.title

        case .updateChatPhoto(let info):
            chatsById[info.chatId]?.smallPhotoFileId = info.photo?.small.id
            if let local = info.photo?.small.local, local.isDownloadingCompleted, !local.path.isEmpty {
                chatsById[info.chatId]?.smallPhotoLocalPath = local.path
            } else {
                chatsById[info.chatId]?.smallPhotoLocalPath = nil
            }

        case .updateChatLastMessage(let info):
            chatsById[info.chatId]?.lastMessage = info.lastMessage.map(MessageItem.init(tdMessage:))
            chatsById[info.chatId]?.applyPositions(info.positions)

        case .updateChatPosition(let info):
            chatsById[info.chatId]?.applyPosition(info.position)

        case .updateChatReadInbox(let info):
            chatsById[info.chatId]?.lastReadInboxMessageId = info.lastReadInboxMessageId
            chatsById[info.chatId]?.unreadCount = info.unreadCount

        case .updateChatReadOutbox(let info):
            chatsById[info.chatId]?.lastReadOutboxMessageId = info.lastReadOutboxMessageId

        case .updateChatIsMarkedAsUnread(let info):
            chatsById[info.chatId]?.isMarkedAsUnread = info.isMarkedAsUnread

        case .updateUser(let info):
            usersById[info.user.id] = UserSummary(tdUser: info.user)

        default:
            break
        }
    }

    func reset() {
        searchTask?.cancel()
        chatsById.removeAll()
        usersById.removeAll()
        remoteSearchChatIds.removeAll()
        inFlightUserIds.removeAll()
        inFlightChatIds.removeAll()
        hasReachedEnd.removeAll()
        selectedChatId = nil
        searchQuery = ""
        errorMessage = nil
        isLoadingChats = false
    }

    // MARK: - Private

    private func syncKnownChats(for filter: ChatListFilter) async {
        guard let ids = try? await service.getChats(list: filter.tdChatList, limit: 100) else {
            return
        }
        for id in ids where chatsById[id] == nil {
            if let tdChat = try? await service.getChat(chatId: id) {
                chatsById[tdChat.id] = ChatSummary(tdChat: tdChat)
            }
        }
    }
}
