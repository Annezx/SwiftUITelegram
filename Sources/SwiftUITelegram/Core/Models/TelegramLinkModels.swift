import Foundation
import TDLibKit

/// Preview payload displayed when opening a private Telegram group or channel invite link
/// (`t.me/+...`, `t.me/joinchat/...`, or `tg://join?invite=...`).
struct PendingChatInvitePreview: Identifiable, Equatable, Sendable {
    let id = UUID()
    let inviteLink: String
    let originalURL: URL
    let title: String
    let description: String
    let memberCount: Int
    let chatTypeLabel: String
    let isChannel: Bool
    let createsJoinRequest: Bool
    let accentColorId: Int
    let smallPhotoFileId: Int?
    let smallPhotoLocalPath: String?

    var avatarInitials: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "TG" }
        let parts = trimmed.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(trimmed.prefix(2)).uppercased()
    }

    init(inviteLink: String, originalURL: URL, tdInfo: ChatInviteLinkInfo) {
        self.inviteLink = inviteLink
        self.originalURL = originalURL
        self.title = tdInfo.title
        self.description = tdInfo.description
        self.memberCount = tdInfo.memberCount
        self.createsJoinRequest = tdInfo.createsJoinRequest
        self.accentColorId = tdInfo.accentColorId

        switch tdInfo.type {
        case .inviteLinkChatTypeBasicGroup:
            self.chatTypeLabel = "群组"
            self.isChannel = false
        case .inviteLinkChatTypeSupergroup:
            self.chatTypeLabel = "超级群组"
            self.isChannel = false
        case .inviteLinkChatTypeChannel:
            self.chatTypeLabel = "频道"
            self.isChannel = true
        }

        if let small = tdInfo.photo?.small {
            self.smallPhotoFileId = small.id
            self.smallPhotoLocalPath = small.local.isDownloadingCompleted && !small.local.path.isEmpty
                ? small.local.path
                : nil
        } else {
            self.smallPhotoFileId = nil
            self.smallPhotoLocalPath = nil
        }
    }
}

/// Carries an optional deep-link `/start <parameter>` context after navigating to a bot chat
/// via `t.me/<bot>?start=<param>` when `autostart == false`.
struct PendingBotStartContext: Equatable, Sendable {
    let chatId: Int64
    let botUserId: Int64
    let botUsername: String
    let parameter: String
}

/// Offline fallback classification used only if TDLib's `getInternalLinkType` fails.
enum LocalTelegramLinkFallback: Equatable, Sendable {
    case publicChat(username: String, draftText: String)
    case botStart(username: String, parameter: String)
    case botStartInGroup(username: String, parameter: String)
    case chatInvite(link: String)
    case messageLink(url: String)
}

/// Recognizes Telegram deep links (`t.me`, `*.t.me`, `telegram.me`, `telegram.dog`, `tx.me`, `tg://`)
/// so clicks open chats, bots, groups, channels, and messages natively inside the app.
enum TelegramLinkDetector {
    private static let exactHosts: Set<String> = [
        "t.me",
        "www.t.me",
        "telegram.me",
        "www.telegram.me",
        "telegram.dog",
        "www.telegram.dog",
        "tx.me",
        "www.tx.me"
    ]

    /// Reserved top-level paths on `t.me` that are NOT public usernames.
    private static let reservedRootSegments: Set<String> = [
        "addemoji",
        "addlist",
        "addstickers",
        "addtheme",
        "bg",
        "blog",
        "boost",
        "c",
        "confirmphone",
        "contact",
        "giftcode",
        "invoice",
        "iv",
        "joinchat",
        "login",
        "m",
        "nft",
        "proxy",
        "s",
        "setlanguage",
        "share",
        "socks"
    ]

    static func normalizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        let hasScheme = lower.hasPrefix("http://")
            || lower.hasPrefix("https://")
            || lower.hasPrefix("tg://")
            || lower.hasPrefix("mailto:")
            || lower.hasPrefix("tel:")
            || lower.hasPrefix("ftp://")

        let candidate = hasScheme ? trimmed : "https://\(trimmed)"
        if let direct = URL(string: candidate) {
            return direct
        }
        if let encoded = candidate.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) {
            return URL(string: encoded)
        }
        return nil
    }

    /// Returns true if `url` points to a Telegram link (`tg://`, `t.me/...`, `username.t.me`,
    /// `telegram.me/...`, `telegram.dog/...`, `tx.me/...`).
    static func isTelegramLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "tg" {
            return true
        }
        guard scheme == "http" || scheme == "https",
              let rawHost = url.host?.lowercased(),
              !rawHost.isEmpty
        else {
            return false
        }

        if exactHosts.contains(rawHost) {
            // Bare https://t.me/ with no path and no query is just the Telegram homepage.
            let cleanedPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let hasQuery = !(url.query ?? "").isEmpty
            return !cleanedPath.isEmpty || hasQuery
        }

        // Subdomain links such as https://botfather.t.me or https://swiftlang.t.me/123
        if rawHost.hasSuffix(".t.me") {
            let sub = String(rawHost.dropLast(".t.me".count))
            return !sub.isEmpty && !sub.contains(".") && sub != "www"
        }

        return false
    }

    static func isTelegramLinkString(_ raw: String) -> Bool {
        guard let url = normalizedURL(from: raw) else { return false }
        return isTelegramLink(url)
    }

    /// Best-effort local parser used strictly as a fallback when TDLib's `getInternalLinkType`
    /// returns an error for a `t.me` or `tg://` link.
    static func localFallback(for url: URL) -> LocalTelegramLinkFallback? {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        func queryValue(_ name: String) -> String? {
            queryItems.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value
        }

        if scheme == "tg" {
            let host = url.host?.lowercased() ?? ""
            switch host {
            case "resolve":
                guard let domain = queryValue("domain")?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !domain.isEmpty
                else {
                    return nil
                }
                if let post = queryValue("post"), Int(post) != nil {
                    return .messageLink(url: url.absoluteString)
                }
                if let start = queryValue("start") {
                    return .botStart(username: domain, parameter: start)
                }
                if let startGroup = queryValue("startgroup") {
                    return .botStartInGroup(username: domain, parameter: startGroup)
                }
                return .publicChat(username: domain, draftText: queryValue("text") ?? "")

            case "join":
                if let invite = queryValue("invite"), !invite.isEmpty {
                    return .chatInvite(link: url.absoluteString)
                }
                return nil

            case "privatepost":
                return .messageLink(url: url.absoluteString)

            default:
                return nil
            }
        }

        guard scheme == "http" || scheme == "https",
              let rawHost = url.host?.lowercased()
        else {
            return nil
        }

        let segments = url.path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }

        // Handle username.t.me[/postId]
        if rawHost.hasSuffix(".t.me") && !exactHosts.contains(rawHost) {
            let username = String(rawHost.dropLast(".t.me".count))
            guard !username.isEmpty, !username.contains(".") else { return nil }
            if let first = segments.first, Int(first) != nil {
                return .messageLink(url: url.absoluteString)
            }
            if let start = queryValue("start") {
                return .botStart(username: username, parameter: start)
            }
            if let startGroup = queryValue("startgroup") {
                return .botStartInGroup(username: username, parameter: startGroup)
            }
            return .publicChat(username: username, draftText: queryValue("text") ?? "")
        }

        guard exactHosts.contains(rawHost), let first = segments.first else {
            return nil
        }

        let lowerFirst = first.lowercased()

        // Private invite: t.me/+hash or t.me/joinchat/hash
        if first.hasPrefix("+") {
            let suffix = String(first.dropFirst())
            // Phone number links are all digits; invite hashes contain letters/symbols.
            if suffix.contains(where: { !$0.isNumber }) {
                return .chatInvite(link: url.absoluteString)
            }
            return nil
        }
        if lowerFirst == "joinchat", segments.count >= 2 {
            return .chatInvite(link: url.absoluteString)
        }

        // Private supergroup message link: t.me/c/<channelId>/<messageId>
        if lowerFirst == "c", segments.count >= 3 {
            return .messageLink(url: url.absoluteString)
        }

        // Web preview path: t.me/s/<username>[/<messageId>]
        if lowerFirst == "s", segments.count >= 2 {
            let username = segments[1]
            if segments.count >= 3, Int(segments[2]) != nil {
                return .messageLink(url: url.absoluteString)
            }
            return .publicChat(username: username, draftText: queryValue("text") ?? "")
        }

        guard !reservedRootSegments.contains(lowerFirst) else {
            return nil
        }

        // Public message link: t.me/<username>/<messageId>
        if segments.count >= 2, Int(segments[1]) != nil {
            return .messageLink(url: url.absoluteString)
        }

        // Bot start link: t.me/<bot>?start=<param> or ?startgroup=<param>
        if let start = queryValue("start") {
            return .botStart(username: first, parameter: start)
        }
        if let startGroup = queryValue("startgroup") {
            return .botStartInGroup(username: first, parameter: startGroup)
        }

        // Standard public chat / bot / channel username link
        if segments.count == 1 {
            return .publicChat(username: first, draftText: queryValue("text") ?? "")
        }

        return nil
    }
}
