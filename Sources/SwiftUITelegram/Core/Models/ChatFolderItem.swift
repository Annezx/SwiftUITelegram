import Foundation
import TDLibKit

/// Lightweight domain model mapped from TDLib's `ChatFolderInfo` (delivered via `updateChatFolders`).
struct ChatFolderItem: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    var title: String
    var iconName: String
    var colorId: Int
    var isShareable: Bool
    var hasMyInviteLinks: Bool

    init(
        id: Int,
        title: String,
        iconName: String = "",
        colorId: Int = -1,
        isShareable: Bool = false,
        hasMyInviteLinks: Bool = false
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.colorId = colorId
        self.isShareable = isShareable
        self.hasMyInviteLinks = hasMyInviteLinks
    }

    init(tdInfo: ChatFolderInfo) {
        let rawTitle = tdInfo.name.text.text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = tdInfo.id
        self.title = rawTitle.isEmpty ? "文件夹 \(tdInfo.id)" : rawTitle
        self.iconName = tdInfo.icon.name
        self.colorId = tdInfo.colorId
        self.isShareable = tdInfo.isShareable
        self.hasMyInviteLinks = tdInfo.hasMyInviteLinks
    }

    var filter: ChatListFilter {
        .folder(id)
    }

    var sfSymbolName: String {
        ChatFolderIconCatalog.sfSymbolName(for: iconName)
    }
}

/// Maps TDLib's `ChatFolderIcon.name` values to native macOS SF Symbols and exposes selectable options.
enum ChatFolderIconCatalog {
    struct Option: Identifiable, Hashable, Sendable {
        let tdName: String
        let label: String
        let sfSymbolName: String

        var id: String { tdName.isEmpty ? "auto" : tdName }
    }

    /// Curated selectable icons shown in the folder editor. Empty `tdName` lets TDLib pick automatically.
    static let selectableOptions: [Option] = [
        Option(tdName: "", label: "自动", sfSymbolName: "sparkles"),
        Option(tdName: "Custom", label: "文件夹", sfSymbolName: "folder"),
        Option(tdName: "All", label: "全部", sfSymbolName: "bubble.left.and.bubble.right"),
        Option(tdName: "Unread", label: "未读", sfSymbolName: "message.badge"),
        Option(tdName: "Unmuted", label: "提醒", sfSymbolName: "bell"),
        Option(tdName: "Private", label: "私聊", sfSymbolName: "person"),
        Option(tdName: "Groups", label: "群组", sfSymbolName: "person.3"),
        Option(tdName: "Channels", label: "频道", sfSymbolName: "megaphone"),
        Option(tdName: "Bots", label: "机器人", sfSymbolName: "cpu"),
        Option(tdName: "Work", label: "工作", sfSymbolName: "briefcase"),
        Option(tdName: "Study", label: "学习", sfSymbolName: "graduationcap"),
        Option(tdName: "Favorite", label: "收藏", sfSymbolName: "star"),
        Option(tdName: "Love", label: "喜爱", sfSymbolName: "heart"),
        Option(tdName: "Home", label: "家庭", sfSymbolName: "house"),
        Option(tdName: "Game", label: "游戏", sfSymbolName: "gamecontroller"),
        Option(tdName: "Trade", label: "财经", sfSymbolName: "chart.line.uptrend.xyaxis"),
        Option(tdName: "Money", label: "财务", sfSymbolName: "banknote"),
        Option(tdName: "Travel", label: "旅行", sfSymbolName: "suitcase"),
        Option(tdName: "Book", label: "阅读", sfSymbolName: "book"),
        Option(tdName: "Note", label: "笔记", sfSymbolName: "note.text"),
        Option(tdName: "Light", label: "灵感", sfSymbolName: "lightbulb"),
        Option(tdName: "Cat", label: "宠物", sfSymbolName: "pawprint"),
        Option(tdName: "Sport", label: "运动", sfSymbolName: "sportscourt"),
        Option(tdName: "Palette", label: "创作", sfSymbolName: "paintpalette")
    ]

    /// Maps every documented TDLib `ChatFolderIcon.name` to an SF Symbol available on macOS 15.
    static func sfSymbolName(for tdIconName: String) -> String {
        switch tdIconName {
        case "All":
            return "bubble.left.and.bubble.right"
        case "Unread":
            return "message.badge"
        case "Unmuted":
            return "bell"
        case "Bots":
            return "cpu"
        case "Channels":
            return "megaphone"
        case "Groups":
            return "person.3"
        case "Private":
            return "person"
        case "Custom":
            return "folder"
        case "Setup":
            return "slider.horizontal.3"
        case "Cat":
            return "pawprint"
        case "Crown":
            return "crown"
        case "Favorite":
            return "star"
        case "Flower":
            return "leaf"
        case "Game":
            return "gamecontroller"
        case "Home":
            return "house"
        case "Love":
            return "heart"
        case "Mask":
            return "theatermasks"
        case "Party":
            return "sparkles"
        case "Sport":
            return "sportscourt"
        case "Study":
            return "graduationcap"
        case "Trade":
            return "chart.line.uptrend.xyaxis"
        case "Travel":
            return "suitcase"
        case "Work":
            return "briefcase"
        case "Airplane":
            return "airplane"
        case "Book":
            return "book"
        case "Light":
            return "lightbulb"
        case "Like":
            return "hand.thumbsup"
        case "Money":
            return "banknote"
        case "Note":
            return "note.text"
        case "Palette":
            return "paintpalette"
        default:
            return "folder"
        }
    }
}

/// Unread chat/message counters tracked per `ChatListFilter` via `updateUnreadChatCount` and `updateUnreadMessageCount`.
struct ChatListUnreadCounts: Equatable, Hashable, Sendable {
    var unreadChatCount: Int = 0
    var unreadUnmutedChatCount: Int = 0
    var markedAsUnreadCount: Int = 0
    var markedAsUnreadUnmutedCount: Int = 0
    var totalChatCount: Int = 0
    var unreadMessageCount: Int = 0
    var unreadUnmutedMessageCount: Int = 0

    /// Number displayed inside a folder tab's unread pill (matches Telegram desktop convention of unread chats).
    var badgeCount: Int {
        unreadChatCount
    }

    var hasUnmutedUnread: Bool {
        unreadUnmutedChatCount > 0
    }
}

/// Single rendered tab entry inside the chat list folder tab strip.
struct ChatListTabItem: Identifiable, Equatable, Hashable, Sendable {
    let filter: ChatListFilter
    let title: String
    let menuTitle: String
    let sfSymbolName: String
    let colorId: Int
    let isCustomFolder: Bool

    var id: String { filter.id }
}

/// Editable draft representation of TDLib's `ChatFolder` used when creating or editing a folder.
struct ChatFolderDraft: Equatable {
    static let maxTitleLength: Int = 12

    var title: String = ""
    var iconName: String = ""
    var colorId: Int = -1
    var includeContacts: Bool = false
    var includeNonContacts: Bool = false
    var includeGroups: Bool = false
    var includeChannels: Bool = false
    var includeBots: Bool = false
    var excludeMuted: Bool = false
    var excludeRead: Bool = false
    var excludeArchived: Bool = false
    var includedChatIds: [Int64] = []
    var excludedChatIds: [Int64] = []
    var pinnedChatIds: [Int64] = []
    var isShareable: Bool = false
    var animateCustomEmoji: Bool = false
    var originalName: ChatFolderName?

    static let empty = ChatFolderDraft()

    init(
        title: String = "",
        iconName: String = "",
        colorId: Int = -1,
        includeContacts: Bool = false,
        includeNonContacts: Bool = false,
        includeGroups: Bool = false,
        includeChannels: Bool = false,
        includeBots: Bool = false,
        excludeMuted: Bool = false,
        excludeRead: Bool = false,
        excludeArchived: Bool = false,
        includedChatIds: [Int64] = [],
        excludedChatIds: [Int64] = [],
        pinnedChatIds: [Int64] = [],
        isShareable: Bool = false,
        animateCustomEmoji: Bool = false,
        originalName: ChatFolderName? = nil
    ) {
        self.title = title
        self.iconName = iconName
        self.colorId = colorId
        self.includeContacts = includeContacts
        self.includeNonContacts = includeNonContacts
        self.includeGroups = includeGroups
        self.includeChannels = includeChannels
        self.includeBots = includeBots
        self.excludeMuted = excludeMuted
        self.excludeRead = excludeRead
        self.excludeArchived = excludeArchived
        self.includedChatIds = includedChatIds
        self.excludedChatIds = excludedChatIds
        self.pinnedChatIds = pinnedChatIds
        self.isShareable = isShareable
        self.animateCustomEmoji = animateCustomEmoji
        self.originalName = originalName
    }

    init(tdFolder: ChatFolder) {
        self.title = tdFolder.name.text.text
        self.iconName = tdFolder.icon?.name ?? ""
        self.colorId = tdFolder.colorId
        self.includeContacts = tdFolder.includeContacts
        self.includeNonContacts = tdFolder.includeNonContacts
        self.includeGroups = tdFolder.includeGroups
        self.includeChannels = tdFolder.includeChannels
        self.includeBots = tdFolder.includeBots
        self.excludeMuted = tdFolder.excludeMuted
        self.excludeRead = tdFolder.excludeRead
        self.excludeArchived = tdFolder.excludeArchived
        self.includedChatIds = tdFolder.includedChatIds
        self.excludedChatIds = tdFolder.excludedChatIds
        self.pinnedChatIds = tdFolder.pinnedChatIds
        self.isShareable = tdFolder.isShareable
        self.animateCustomEmoji = tdFolder.name.animateCustomEmoji
        self.originalName = tdFolder.name
    }

    var trimmedTitle: String {
        title
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasAnyIncludedCategory: Bool {
        includeContacts || includeNonContacts || includeGroups || includeChannels || includeBots
    }

    var hasIncludeCriteria: Bool {
        if isShareable {
            return !includedChatIds.isEmpty || !pinnedChatIds.isEmpty
        }
        return hasAnyIncludedCategory || !includedChatIds.isEmpty || !pinnedChatIds.isEmpty
    }

    var isValid: Bool {
        let len = trimmedTitle.count
        return len >= 1 && len <= Self.maxTitleLength && hasIncludeCriteria
    }

    func toTDChatFolder() -> ChatFolder {
        let cleanedTitle = String(trimmedTitle.prefix(Self.maxTitleLength))
        let resolvedName: ChatFolderName
        if let originalName, originalName.text.text == cleanedTitle {
            resolvedName = originalName
        } else {
            resolvedName = ChatFolderName(
                animateCustomEmoji: animateCustomEmoji,
                text: FormattedText(entities: [], text: cleanedTitle)
            )
        }

        let cleanIconName = iconName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedIcon: ChatFolderIcon? = cleanIconName.isEmpty ? nil : ChatFolderIcon(name: cleanIconName)

        let effectiveExcludedIds = isShareable ? [] : excludedChatIds
        let excludedSet = Set(effectiveExcludedIds)
        let effectiveIncludedIds = includedChatIds.filter { !excludedSet.contains($0) }
        let effectivePinnedIds = pinnedChatIds.filter { !excludedSet.contains($0) }

        return ChatFolder(
            colorId: colorId,
            excludeArchived: isShareable ? false : excludeArchived,
            excludeMuted: isShareable ? false : excludeMuted,
            excludeRead: isShareable ? false : excludeRead,
            excludedChatIds: effectiveExcludedIds,
            icon: resolvedIcon,
            includeBots: isShareable ? false : includeBots,
            includeChannels: isShareable ? false : includeChannels,
            includeContacts: isShareable ? false : includeContacts,
            includeGroups: isShareable ? false : includeGroups,
            includeNonContacts: isShareable ? false : includeNonContacts,
            includedChatIds: effectiveIncludedIds,
            isShareable: isShareable,
            name: resolvedName,
            pinnedChatIds: effectivePinnedIds
        )
    }
}
