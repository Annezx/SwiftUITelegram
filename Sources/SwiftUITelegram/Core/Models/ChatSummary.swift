import Foundation
import TDLibKit

enum ChatListFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case main
    case archive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .main: return "全部对话"
        case .archive: return "已归档"
        }
    }

    var tdChatList: ChatList {
        switch self {
        case .main: return .chatListMain
        case .archive: return .chatListArchive
        }
    }

    init?(tdChatList: ChatList) {
        switch tdChatList {
        case .chatListMain:
            self = .main
        case .chatListArchive:
            self = .archive
        case .chatListFolder:
            return nil
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
        positions: [ChatListFilter: ChatOrderPosition] = [:]
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
            if let filter = ChatListFilter(tdChatList: pos.list), pos.order.rawValue != 0 {
                mappedPositions[filter] = ChatOrderPosition(isPinned: pos.isPinned, order: pos.order.rawValue)
            }
        }
        self.positions = mappedPositions
    }

    mutating func applyPositions(_ tdPositions: [ChatPosition]) {
        for pos in tdPositions {
            applyPosition(pos)
        }
    }

    mutating func applyPosition(_ tdPosition: ChatPosition) {
        guard let filter = ChatListFilter(tdChatList: tdPosition.list) else { return }
        if tdPosition.order.rawValue == 0 {
            positions.removeValue(forKey: filter)
        } else {
            positions[filter] = ChatOrderPosition(
                isPinned: tdPosition.isPinned,
                order: tdPosition.order.rawValue
            )
        }
    }

    mutating func removeFromList(_ filter: ChatListFilter) {
        positions.removeValue(forKey: filter)
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
        order(in: .archive) != 0
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
