import Foundation
import TDLibKit

enum ChatListFilter: Identifiable, Hashable, Sendable {
    case main
    case archive
    case folder(Int)

    var id: String {
        switch self {
        case .main:
            return "main"
        case .archive:
            return "archive"
        case .folder(let folderId):
            return "folder_\(folderId)"
        }
    }

    var folderId: Int? {
        if case .folder(let id) = self {
            return id
        }
        return nil
    }

    var defaultTitle: String {
        switch self {
        case .main:
            return "全部对话"
        case .archive:
            return "已归档"
        case .folder(let folderId):
            return "文件夹 \(folderId)"
        }
    }

    var tdChatList: ChatList {
        switch self {
        case .main:
            return .chatListMain
        case .archive:
            return .chatListArchive
        case .folder(let folderId):
            return .chatListFolder(ChatListFolder(chatFolderId: folderId))
        }
    }

    init(tdChatList: ChatList) {
        switch tdChatList {
        case .chatListMain:
            self = .main
        case .chatListArchive:
            self = .archive
        case .chatListFolder(let folder):
            self = .folder(folder.chatFolderId)
        }
    }
}

enum ChatKind: Equatable, Hashable, Sendable {
    case privateUser(userId: Int64)
    case basicGroup(id: Int64)
    case supergroup(id: Int64)
    case channel(id: Int64)
    case secret(id: Int)

    init(from tdType: ChatType) {
        switch tdType {
        case .chatTypePrivate(let info):
            self = .privateUser(userId: info.userId)
        case .chatTypeBasicGroup(let info):
            self = .basicGroup(id: info.basicGroupId)
        case .chatTypeSupergroup(let info):
            self = info.isChannel ? .channel(id: info.supergroupId) : .supergroup(id: info.supergroupId)
        case .chatTypeSecret(let info):
            self = .secret(id: info.secretChatId)
        }
    }

    var isGroup: Bool {
        switch self {
        case .basicGroup, .supergroup:
            return true
        case .privateUser, .channel, .secret:
            return false
        }
    }

    var isChannel: Bool {
        if case .channel = self { return true }
        return false
    }
}

struct ChatOrderPosition: Equatable, Hashable, Sendable {
    let isPinned: Bool
    let order: Int64
}

struct ChatSummary: Identifiable, Equatable, Hashable, Sendable {
    let id: Int64
    var title: String
    var kind: ChatKind
    var accentColorId: Int
    var smallPhotoFileId: Int?
    var smallPhotoLocalPath: String?
    var lastMessage: MessageItem?
    var unreadCount: Int
    var isMarkedAsUnread: Bool
    var lastReadInboxMessageId: Int64
    var lastReadOutboxMessageId: Int64
    var muteFor: Int
    var canBeDeletedOnlyForSelf: Bool
    var canBeDeletedForAllUsers: Bool
    var positions: [ChatListFilter: ChatOrderPosition]
    var chatLists: Set<ChatListFilter>

    init(
        id: Int64,
        title: String,
        kind: ChatKind,
        accentColorId: Int,
        smallPhotoFileId: Int? = nil,
        smallPhotoLocalPath: String? = nil,
        lastMessage: MessageItem? = nil,
        unreadCount: Int = 0,
        isMarkedAsUnread: Bool = false,
        lastReadInboxMessageId: Int64 = 0,
        lastReadOutboxMessageId: Int64 = 0,
        muteFor: Int = 0,
        canBeDeletedOnlyForSelf: Bool = true,
        canBeDeletedForAllUsers: Bool = false,
        positions: [ChatListFilter: ChatOrderPosition] = [:],
        chatLists: Set<ChatListFilter> = []
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.accentColorId = accentColorId
        self.smallPhotoFileId = smallPhotoFileId
        self.smallPhotoLocalPath = smallPhotoLocalPath
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
        self.isMarkedAsUnread = isMarkedAsUnread
        self.lastReadInboxMessageId = lastReadInboxMessageId
        self.lastReadOutboxMessageId = lastReadOutboxMessageId
        self.muteFor = muteFor
        self.canBeDeletedOnlyForSelf = canBeDeletedOnlyForSelf
        self.canBeDeletedForAllUsers = canBeDeletedForAllUsers
        self.positions = positions
        self.chatLists = chatLists
    }

    init(tdChat: Chat) {
        self.id = tdChat.id
        self.title = tdChat.title.isEmpty ? "未命名对话" : tdChat.title
        self.kind = ChatKind(from: tdChat.type)
        self.accentColorId = tdChat.accentColorId
        self.smallPhotoFileId = tdChat.photo?.small.id
        if let local = tdChat.photo?.small.local, local.isDownloadingCompleted, !local.path.isEmpty {
            self.smallPhotoLocalPath = local.path
        } else {
            self.smallPhotoLocalPath = nil
        }
        self.lastMessage = tdChat.lastMessage.map(MessageItem.init(tdMessage:))
        self.unreadCount = tdChat.unreadCount
        self.isMarkedAsUnread = tdChat.isMarkedAsUnread
        self.lastReadInboxMessageId = tdChat.lastReadInboxMessageId
        self.lastReadOutboxMessageId = tdChat.lastReadOutboxMessageId
        self.muteFor = tdChat.notificationSettings.muteFor
        self.canBeDeletedOnlyForSelf = tdChat.canBeDeletedOnlyForSelf
        self.canBeDeletedForAllUsers = tdChat.canBeDeletedForAllUsers

        var mappedPositions: [ChatListFilter: ChatOrderPosition] = [:]
        for pos in tdChat.positions {
            let filter = ChatListFilter(tdChatList: pos.list)
            if pos.order.rawValue != 0 {
                mappedPositions[filter] = ChatOrderPosition(isPinned: pos.isPinned, order: pos.order.rawValue)
            }
        }
        self.positions = mappedPositions
        self.chatLists = Set(tdChat.chatLists.map(ChatListFilter.init(tdChatList:)))
    }

    mutating func applyPositions(_ tdPositions: [ChatPosition]) {
        for pos in tdPositions {
            applyPosition(pos)
        }
    }

    mutating func applyPosition(_ tdPosition: ChatPosition) {
        let filter = ChatListFilter(tdChatList: tdPosition.list)
        if tdPosition.order.rawValue == 0 {
            positions.removeValue(forKey: filter)
        } else {
            positions[filter] = ChatOrderPosition(
                isPinned: tdPosition.isPinned,
                order: tdPosition.order.rawValue
            )
        }
    }

    mutating func addToList(_ filter: ChatListFilter) {
        chatLists.insert(filter)
    }

    mutating func removeFromList(_ filter: ChatListFilter) {
        chatLists.remove(filter)
        positions.removeValue(forKey: filter)
    }

    func belongsToList(_ filter: ChatListFilter) -> Bool {
        chatLists.contains(filter) || order(in: filter) != 0
    }

    var folderIds: Set<Int> {
        var ids = Set<Int>()
        for filter in chatLists {
            if let folderId = filter.folderId {
                ids.insert(folderId)
            }
        }
        for filter in positions.keys {
            if let folderId = filter.folderId {
                ids.insert(folderId)
            }
        }
        return ids
    }

    func order(in filter: ChatListFilter) -> Int64 {
        positions[filter]?.order ?? 0
    }

    func isPinned(in filter: ChatListFilter) -> Bool {
        positions[filter]?.isPinned ?? false
    }

    var isMuted: Bool {
        muteFor > 0
    }

    var isArchived: Bool {
        order(in: .archive) != 0 || chatLists.contains(.archive)
    }

    var hasUnreadIndicator: Bool {
        unreadCount > 0 || isMarkedAsUnread
    }

    var lastMessagePreview: String {
        lastMessage?.previewText ?? "暂无消息"
    }

    var lastMessageDate: Foundation.Date? {
        lastMessage?.date
    }

    var avatarInitials: String {
        let parts = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(title.prefix(2)).uppercased()
    }
}

struct UserSummary: Identifiable, Equatable, Hashable, Sendable {
    let id: Int64
    var firstName: String
    var lastName: String
    var username: String?
    var phoneNumber: String
    var statusText: String
    var smallPhotoFileId: Int?
    var smallPhotoLocalPath: String?

    var displayName: String {
        let full = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return full.isEmpty ? "User \(id)" : full
    }

    init(tdUser: User) {
        self.id = tdUser.id
        self.firstName = tdUser.firstName
        self.lastName = tdUser.lastName
        self.username = tdUser.usernames?.activeUsernames.first
        self.phoneNumber = tdUser.phoneNumber
        self.smallPhotoFileId = tdUser.profilePhoto?.small.id
        if let local = tdUser.profilePhoto?.small.local, local.isDownloadingCompleted, !local.path.isEmpty {
            self.smallPhotoLocalPath = local.path
        } else {
            self.smallPhotoLocalPath = nil
        }

        switch tdUser.status {
        case .userStatusOnline:
            self.statusText = "在线"
        case .userStatusOffline(let info):
            let date = Foundation.Date(timeIntervalSince1970: TimeInterval(info.wasOnline))
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            self.statusText = "上次在线 \(formatter.localizedString(for: date, relativeTo: .now))"
        case .userStatusRecently:
            self.statusText = "近期在线"
        case .userStatusLastWeek:
            self.statusText = "一周内在线"
        case .userStatusLastMonth:
            self.statusText = "一个月内在线"
        case .userStatusEmpty:
            self.statusText = ""
        }
    }
}
