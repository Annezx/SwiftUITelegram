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
    private(set) var loadingFilters: Set<ChatListFilter> = []
    private(set) var hasReachedEnd: [ChatListFilter: Bool] = [:]
    private(set) var remoteSearchChatIds: [Int64] = []
    private(set) var chatFolders: [ChatFolderItem] = []
    private(set) var mainChatListPosition: Int = 0
    private(set) var areFolderTagsEnabled: Bool = false
    private(set) var unreadCountsByFilter: [ChatListFilter: ChatListUnreadCounts] = [:]

    var selectedFilter: ChatListFilter = .main
    var selectedChatId: Int64?
    var searchQuery: String = ""
    var errorMessage: String?

    init(service: TDLibService) {
        self.service = service
    }

    var isLoadingChats: Bool {
        loadingFilters.contains(selectedFilter)
    }

    func isLoadingChats(for filter: ChatListFilter) -> Bool {
        loadingFilters.contains(filter)
    }

    var selectedChat: ChatSummary? {
        guard let selectedChatId else { return nil }
        return chatsById[selectedChatId]
    }

    /// Ordered folder tabs honoring TDLib's `mainChatListPosition` among custom folders,
    /// followed by the Archive list.
    var orderedTabs: [ChatListTabItem] {
        let hasCustomFolders = !chatFolders.isEmpty
        let mainTab = ChatListTabItem(
            filter: .main,
            title: hasCustomFolders ? "全部" : "全部对话",
            menuTitle: "全部对话",
            sfSymbolName: "bubble.left.and.bubble.right",
            colorId: -1,
            isCustomFolder: false
        )

        var tabs = chatFolders.map { folder in
            ChatListTabItem(
                filter: folder.filter,
                title: folder.title,
                menuTitle: folder.title,
                sfSymbolName: folder.sfSymbolName,
                colorId: folder.colorId,
                isCustomFolder: true
            )
        }

        let clampedMainIndex = min(max(0, mainChatListPosition), tabs.count)
        tabs.insert(mainTab, at: clampedMainIndex)

        tabs.append(
            ChatListTabItem(
                filter: .archive,
                title: "已归档",
                menuTitle: "已归档",
                sfSymbolName: "archivebox",
                colorId: -1,
                isCustomFolder: false
            )
        )
        return tabs
    }

    func folder(for id: Int) -> ChatFolderItem? {
        chatFolders.first { $0.id == id }
    }

    func title(for filter: ChatListFilter) -> String {
        switch filter {
        case .main:
            return "全部对话"
        case .archive:
            return "已归档"
        case .folder(let id):
            return folder(for: id)?.title ?? filter.defaultTitle
        }
    }

    func unreadCounts(for filter: ChatListFilter) -> ChatListUnreadCounts {
        unreadCountsByFilter[filter] ?? ChatListUnreadCounts()
    }

    /// Custom folders a chat belongs to, ordered consistently with `chatFolders`.
    func folderTags(for chat: ChatSummary) -> [ChatFolderItem] {
        let ids = chat.folderIds
        guard !ids.isEmpty else { return [] }
        return chatFolders.filter { ids.contains($0.id) }
    }

    func selectFilter(_ filter: ChatListFilter) {
        if !searchQuery.isEmpty {
            updateSearchQuery("")
        }
        selectedFilter = filter
    }

    func selectPreviousTab() {
        let tabs = orderedTabs
        guard tabs.count > 1 else { return }
        if let currentIndex = tabs.firstIndex(where: { $0.filter == selectedFilter }) {
            let prevIndex = (currentIndex - 1 + tabs.count) % tabs.count
            selectFilter(tabs[prevIndex].filter)
        } else if let first = tabs.first {
            selectFilter(first.filter)
        }
    }

    func selectNextTab() {
        let tabs = orderedTabs
        guard tabs.count > 1 else { return }
        if let currentIndex = tabs.firstIndex(where: { $0.filter == selectedFilter }) {
            let nextIndex = (currentIndex + 1) % tabs.count
            selectFilter(tabs[nextIndex].filter)
        } else if let first = tabs.first {
            selectFilter(first.filter)
        }
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
        guard !loadingFilters.contains(targetFilter), hasReachedEnd[targetFilter] != true else { return }

        loadingFilters.insert(targetFilter)
        defer { loadingFilters.remove(targetFilter) }

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

    func refreshList(for filter: ChatListFilter) async {
        hasReachedEnd[filter] = false
        await loadMoreChats(for: filter)
    }

    func refreshCurrentList() async {
        await refreshList(for: selectedFilter)
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

    // MARK: - Chat Context Menu Actions

    func markAsRead(chatId: Int64) async {
        errorMessage = nil
        do {
            if let chat = chatsById[chatId] {
                if chat.unreadCount > 0, let lastMsgId = chat.lastMessage?.id {
                    try await service.viewMessages(chatId: chatId, messageIds: [lastMsgId])
                }
                if chat.isMarkedAsUnread {
                    try await service.toggleChatIsMarkedAsUnread(chatId: chatId, isMarkedAsUnread: false)
                }
            } else {
                try await service.toggleChatIsMarkedAsUnread(chatId: chatId, isMarkedAsUnread: false)
            }
        } catch {
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
        }
    }

    func markAsUnread(chatId: Int64) async {
        errorMessage = nil
        do {
            try await service.toggleChatIsMarkedAsUnread(chatId: chatId, isMarkedAsUnread: true)
        } catch {
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
        }
    }

    func togglePin(chatId: Int64, in filter: ChatListFilter) async {
        guard let chat = chatsById[chatId] else { return }
        errorMessage = nil
        let targetPinned = !chat.isPinned(in: filter)
        do {
            try await service.toggleChatIsPinned(
                chatList: filter.tdChatList,
                chatId: chatId,
                isPinned: targetPinned
            )
        } catch {
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
        }
    }

    func setMute(chatId: Int64, muteFor: Int) async {
        errorMessage = nil
        do {
            try await service.setChatMuteFor(chatId: chatId, muteFor: muteFor)
            chatsById[chatId]?.muteFor = max(0, muteFor)
        } catch {
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
        }
    }

    func toggleArchive(chatId: Int64) async {
        guard let chat = chatsById[chatId] else { return }
        errorMessage = nil
        let destination: ChatList = chat.isArchived ? .chatListMain : .chatListArchive
        do {
            try await service.addChatToList(chatId: chatId, chatList: destination)
        } catch {
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
        }
    }

    @discardableResult
    func clearHistory(chatId: Int64, revoke: Bool) async -> Bool {
        errorMessage = nil
        do {
            try await service.deleteChatHistory(
                chatId: chatId,
                removeFromChatList: false,
                revoke: revoke
            )
            return true
        } catch {
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
            return false
        }
    }

    @discardableResult
    func deleteOrLeaveChat(chatId: Int64, revoke: Bool) async -> Bool {
        guard let chat = chatsById[chatId] else { return false }
        errorMessage = nil
        do {
            switch chat.kind {
            case .privateUser, .secret:
                try await service.deleteChatHistory(
                    chatId: chatId,
                    removeFromChatList: true,
                    revoke: revoke
                )
            case .basicGroup:
                try await service.leaveChat(chatId: chatId)
                _ = try? await service.deleteChatHistory(
                    chatId: chatId,
                    removeFromChatList: true,
                    revoke: false
                )
            case .supergroup, .channel:
                try await service.leaveChat(chatId: chatId)
            }

            if selectedChatId == chatId {
                selectedChatId = nil
            }
            return true
        } catch {
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
            return false
        }
    }

    // MARK: - Chat Folder Actions

    func markChatListAsRead(_ filter: ChatListFilter) async {
        errorMessage = nil
        do {
            try await service.readChatList(filter.tdChatList)
        } catch {
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
        }
    }

    func loadFolderDraft(folderId: Int) async -> (draft: ChatFolderDraft?, error: String?) {
        do {
            let tdFolder = try await service.getChatFolder(chatFolderId: folderId)
            return (ChatFolderDraft(tdFolder: tdFolder), nil)
        } catch {
            return (nil, TDLibErrorHelper.userFacingMessage(for: error) ?? "无法加载文件夹详情")
        }
    }

    func saveFolder(folderId: Int?, draft: ChatFolderDraft) async -> String? {
        guard draft.isValid else {
            return "请输入 1–12 个字符的文件夹名称，并至少选择一个对话分类或具体对话。"
        }

        let tdFolder = draft.toTDChatFolder()
        do {
            if let folderId {
                let updatedInfo = try await service.editChatFolder(chatFolderId: folderId, folder: tdFolder)
                let updatedItem = ChatFolderItem(tdInfo: updatedInfo)
                if let index = chatFolders.firstIndex(where: { $0.id == updatedItem.id }) {
                    chatFolders[index] = updatedItem
                }
                let filter = ChatListFilter.folder(folderId)
                hasReachedEnd[filter] = false
                if selectedFilter == filter {
                    await loadMoreChats(for: filter)
                }
            } else {
                let createdInfo = try await service.createChatFolder(tdFolder)
                let createdItem = ChatFolderItem(tdInfo: createdInfo)
                if !chatFolders.contains(where: { $0.id == createdItem.id }) {
                    chatFolders.append(createdItem)
                }
                let filter = ChatListFilter.folder(createdItem.id)
                selectFilter(filter)
                hasReachedEnd[filter] = false
                await loadMoreChats(for: filter)
            }
            return nil
        } catch {
            return TDLibErrorHelper.userFacingMessage(for: error) ?? "保存文件夹失败"
        }
    }

    @discardableResult
    func deleteFolder(folderId: Int) async -> Bool {
        errorMessage = nil
        do {
            try await service.deleteChatFolder(chatFolderId: folderId, leaveChatIds: [])
            if selectedFilter == .folder(folderId) {
                selectedFilter = .main
            }
            return true
        } catch {
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
            return false
        }
    }

    func moveFolder(folderId: Int, offset: Int) async {
        guard let currentIndex = chatFolders.firstIndex(where: { $0.id == folderId }) else { return }
        let targetIndex = currentIndex + offset
        guard targetIndex >= 0, targetIndex < chatFolders.count, targetIndex != currentIndex else { return }

        var reordered = chatFolders
        let moved = reordered.remove(at: currentIndex)
        reordered.insert(moved, at: targetIndex)
        await reorderFolders(to: reordered)
    }

    func reorderFolders(to reordered: [ChatFolderItem]) async {
        let previous = chatFolders
        let ids = reordered.map(\.id)
        let clampedMainPos = min(max(0, mainChatListPosition), ids.count)

        errorMessage = nil
        chatFolders = reordered
        do {
            try await service.reorderChatFolders(
                chatFolderIds: ids,
                mainChatListPosition: clampedMainPos
            )
        } catch {
            chatFolders = previous
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
        }
    }

    func addChat(_ chatId: Int64, toFolder folderId: Int) async {
        errorMessage = nil
        let targetFilter = ChatListFilter.folder(folderId)
        do {
            try await service.addChatToList(chatId: chatId, chatList: targetFilter.tdChatList)
            chatsById[chatId]?.addToList(targetFilter)
            hasReachedEnd[targetFilter] = false
            if selectedFilter == targetFilter {
                await loadMoreChats(for: targetFilter)
            }
        } catch {
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
        }
    }

    func removeChat(_ chatId: Int64, fromFolder folderId: Int) async {
        errorMessage = nil
        do {
            let current = try await service.getChatFolder(chatFolderId: folderId)
            var included = current.includedChatIds.filter { $0 != chatId }
            let pinned = current.pinnedChatIds.filter { $0 != chatId }
            var excluded = current.excludedChatIds

            if !current.isShareable {
                let wasExplicitlyIncluded = current.includedChatIds.contains(chatId)
                    || current.pinnedChatIds.contains(chatId)
                let matchesCategories = chatMatchesFolderCategories(chatId: chatId, folder: current)
                if (!wasExplicitlyIncluded || matchesCategories), !excluded.contains(chatId) {
                    excluded.append(chatId)
                }
                let excludedSet = Set(excluded)
                included.removeAll { excludedSet.contains($0) }
            }

            let updated = ChatFolder(
                colorId: current.colorId,
                excludeArchived: current.excludeArchived,
                excludeMuted: current.excludeMuted,
                excludeRead: current.excludeRead,
                excludedChatIds: excluded,
                icon: current.icon,
                includeBots: current.includeBots,
                includeChannels: current.includeChannels,
                includeContacts: current.includeContacts,
                includeGroups: current.includeGroups,
                includeNonContacts: current.includeNonContacts,
                includedChatIds: included,
                isShareable: current.isShareable,
                name: current.name,
                pinnedChatIds: pinned
            )
            _ = try await service.editChatFolder(chatFolderId: folderId, folder: updated)
        } catch {
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
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

        case .updateChatAddedToList(let info):
            let filter = ChatListFilter(tdChatList: info.chatList)
            chatsById[info.chatId]?.addToList(filter)

        case .updateChatRemovedFromList(let info):
            let filter = ChatListFilter(tdChatList: info.chatList)
            chatsById[info.chatId]?.removeFromList(filter)

        case .updateChatFolders(let info):
            let mappedFolders = info.chatFolders.map(ChatFolderItem.init(tdInfo:))
            let previousFolderIds = Set(chatFolders.map(\.id))
            let newFolderIds = Set(mappedFolders.map(\.id))
            let removedFolderIds = previousFolderIds.subtracting(newFolderIds)

            chatFolders = mappedFolders
            mainChatListPosition = info.mainChatListPosition
            areFolderTagsEnabled = info.areTagsEnabled

            for removedId in removedFolderIds {
                let removedFilter = ChatListFilter.folder(removedId)
                hasReachedEnd.removeValue(forKey: removedFilter)
                loadingFilters.remove(removedFilter)
                unreadCountsByFilter.removeValue(forKey: removedFilter)
                for chatId in chatsById.keys {
                    chatsById[chatId]?.removeFromList(removedFilter)
                }
            }

            // Allow remaining folders to fetch newly matching chats when viewed.
            for folder in mappedFolders {
                hasReachedEnd[folder.filter] = false
            }

            if case .folder(let activeId) = selectedFilter {
                if !newFolderIds.contains(activeId) {
                    selectedFilter = .main
                } else {
                    let activeFilter = ChatListFilter.folder(activeId)
                    Task { [weak self] in
                        await self?.loadMoreChats(for: activeFilter)
                    }
                }
            }

        case .updateUnreadChatCount(let info):
            let filter = ChatListFilter(tdChatList: info.chatList)
            var counts = unreadCountsByFilter[filter] ?? ChatListUnreadCounts()
            counts.unreadChatCount = max(0, info.unreadCount)
            counts.unreadUnmutedChatCount = max(0, info.unreadUnmutedCount)
            counts.markedAsUnreadCount = max(0, info.markedAsUnreadCount)
            counts.markedAsUnreadUnmutedCount = max(0, info.markedAsUnreadUnmutedCount)
            counts.totalChatCount = max(0, info.totalCount)
            unreadCountsByFilter[filter] = counts

        case .updateUnreadMessageCount(let info):
            let filter = ChatListFilter(tdChatList: info.chatList)
            var counts = unreadCountsByFilter[filter] ?? ChatListUnreadCounts()
            counts.unreadMessageCount = max(0, info.unreadCount)
            counts.unreadUnmutedMessageCount = max(0, info.unreadUnmutedCount)
            unreadCountsByFilter[filter] = counts

        case .updateChatNotificationSettings(let info):
            chatsById[info.chatId]?.muteFor = info.notificationSettings.muteFor

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
        loadingFilters.removeAll()
        hasReachedEnd.removeAll()
        chatFolders.removeAll()
        mainChatListPosition = 0
        areFolderTagsEnabled = false
        unreadCountsByFilter.removeAll()
        selectedFilter = .main
        selectedChatId = nil
        searchQuery = ""
        errorMessage = nil
    }

    // MARK: - Private

    private func chatMatchesFolderCategories(chatId: Int64, folder: ChatFolder) -> Bool {
        guard let chat = chatsById[chatId] else {
            return folder.includeContacts
                || folder.includeNonContacts
                || folder.includeGroups
                || folder.includeChannels
                || folder.includeBots
        }
        switch chat.kind {
        case .privateUser, .secret:
            return folder.includeContacts || folder.includeNonContacts || folder.includeBots
        case .basicGroup, .supergroup:
            return folder.includeGroups
        case .channel:
            return folder.includeChannels
        }
    }

    private func syncKnownChats(for filter: ChatListFilter) async {
        let currentCount = chatsById.values.filter { $0.order(in: filter) != 0 }.count
        let limit = max(100, currentCount + 40)
        guard let ids = try? await service.getChats(list: filter.tdChatList, limit: limit) else {
            return
        }
        for id in ids where chatsById[id] == nil || chatsById[id]?.order(in: filter) == 0 {
            if let tdChat = try? await service.getChat(chatId: id) {
                chatsById[tdChat.id] = ChatSummary(tdChat: tdChat)
            }
        }
    }
}
