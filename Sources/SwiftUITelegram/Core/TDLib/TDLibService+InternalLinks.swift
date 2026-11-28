import Foundation
import TDLibKit

extension TDLibService {
    // MARK: - Internal Telegram Links & Group/Channel Join

    func getInternalLinkType(link: String) async throws -> InternalLinkType {
        let client = try requireClient()
        return try await client.getInternalLinkType(link: link)
    }

    func checkChatInviteLink(inviteLink: String) async throws -> ChatInviteLinkInfo {
        let client = try requireClient()
        return try await client.checkChatInviteLink(inviteLink: inviteLink)
    }

    func joinChatByInviteLink(inviteLink: String) async throws -> ChatJoinResult {
        let client = try requireClient()
        return try await client.joinChatByInviteLink(inviteLink: inviteLink)
    }

    func joinChat(chatId: Int64) async throws -> ChatJoinResult {
        let client = try requireClient()
        return try await client.joinChat(chatId: chatId)
    }

    func getMessageLinkInfo(url: String) async throws -> MessageLinkInfo {
        let client = try requireClient()
        return try await client.getMessageLinkInfo(url: url)
    }

    func getSupergroup(supergroupId: Int64) async throws -> Supergroup {
        let client = try requireClient()
        return try await client.getSupergroup(supergroupId: supergroupId)
    }

    func searchUserByPhoneNumber(phoneNumber: String, onlyLocal: Bool = false) async throws -> User {
        let client = try requireClient()
        return try await client.searchUserByPhoneNumber(onlyLocal: onlyLocal, phoneNumber: phoneNumber)
    }

    func searchUserByToken(token: String) async throws -> User {
        let client = try requireClient()
        return try await client.searchUserByToken(token: token)
    }

    func applyUnpaidMessagesToken(userId: Int64, token: String) async throws {
        let client = try requireClient()
        _ = try await client.applyUnpaidMessagesToken(token: token, userId: userId)
    }
}
