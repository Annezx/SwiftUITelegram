import AppKit
import Foundation
import TDLibKit

extension AccountSession {
    /// Resolves any Telegram link (`t.me/...`, `*.t.me`, `telegram.me/...`, `telegram.dog/...`, `tg://...`)
    /// natively through TDLib so clicking links jumps directly to the bot, group, channel, user, or message
    /// inside the app instead of opening a web browser.
    func openTelegramURL(_ url: URL) async {
        guard isReady else {
            openInBrowserIfHTTP(url)
            return
        }

        do {
            let linkType = try await service.getInternalLinkType(link: url.absoluteString)
            await handleInternalLinkType(linkType, originalURL: url)
        } catch {
            if let fallback = TelegramLinkDetector.localFallback(for: url) {
                await handleLocalFallback(fallback, originalURL: url)
            } else if !openInBrowserIfHTTP(url) {
                reportLinkFeedback(
                    TDLibErrorHelper.userFacingMessage(for: error) ?? "无法打开该 Telegram 链接",
                    isError: true
                )
            }
        }
    }

    /// Joins the currently previewed private invite link (`PendingChatInvitePreview`) and navigates into the chat.
    func confirmJoinPendingInvite() async -> String? {
        guard let invite = pendingChatInvite else { return nil }

        do {
            let result = try await service.joinChatByInviteLink(inviteLink: invite.inviteLink)
            switch result {
            case .chatJoinResultSuccess(let joined):
                pendingChatInvite = nil
                if let tdChat = try? await service.getChat(chatId: joined.chatId) {
                    navigateToChat(tdChat)
                    conversation.showTransientNotice(invite.isChannel ? "已加入频道「\(tdChat.title)」" : "已加入群组「\(tdChat.title)」")
                } else if await chatList.openChat(byId: joined.chatId) != nil {
                    conversation.selectChat(joined.chatId)
                    conversation.showTransientNotice(invite.isChannel ? "已加入频道" : "已加入群组")
                }
                return nil

            case .chatJoinResultRequestSent:
                pendingChatInvite = nil
                reportLinkFeedback("已提交加入「\(invite.title)」的申请，请等待管理员审批", isError: false)
                return nil

            case .chatJoinResultGuardBotApprovalRequired:
                return "该群组需要通过验证机器人完成入群验证，请点击下方在浏览器中打开或前往官方客户端完成验证。"

            case .chatJoinResultDeclined:
                return "加入「\(invite.title)」的申请已被拒绝。"
            }
        } catch {
            return TDLibErrorHelper.userFacingMessage(for: error) ?? "无法加入该群组或频道"
        }
    }

    // MARK: - Internal Link Dispatch

    private func handleInternalLinkType(_ linkType: InternalLinkType, originalURL: URL) async {
        switch linkType {
        case .internalLinkTypePublicChat(let info):
            await openPublicChat(
                username: info.chatUsername,
                draftText: info.draftText,
                unpaidMessagesToken: info.unpaidMessagesToken
            )

        case .internalLinkTypeBotStart(let info):
            await openBotStart(
                username: info.botUsername,
                parameter: info.startParameter,
                autostart: info.autostart
            )

        case .internalLinkTypeBotStartInGroup(let info):
            await openBotChatWithNotice(
                username: info.botUsername,
                notice: "已跳转到机器人 @\(info.botUsername)（邀请入群请前往官方客户端选择群组）"
            )

        case .internalLinkTypeBotAddToChannel(let info):
            await openBotChatWithNotice(
                username: info.botUsername,
                notice: "已跳转到机器人 @\(info.botUsername)（添加至频道请前往官方客户端配置权限）"
            )

        case .internalLinkTypeChatInvite(let info):
            await openChatInvite(inviteLink: info.inviteLink, originalURL: originalURL)

        case .internalLinkTypeMessage(let info):
            await openMessageLink(urlString: info.url)

        case .internalLinkTypeSavedMessages:
            await openSavedMessages()

        case .internalLinkTypeUserPhoneNumber(let info):
            await openUserByPhoneNumber(
                phoneNumber: info.phoneNumber,
                draftText: info.draftText,
                unpaidMessagesToken: info.unpaidMessagesToken
            )

        case .internalLinkTypeUserToken(let info):
            await openUserByToken(
                token: info.token,
                unpaidMessagesToken: info.unpaidMessagesToken
            )

        case .internalLinkTypeDirectMessagesChat(let info):
            await openPublicChat(
                username: info.channelUsername,
                draftText: "",
                unpaidMessagesToken: ""
            )

        case .internalLinkTypeWebApp(let info):
            await openBotChatWithNotice(
                username: info.botUsername,
                notice: "已跳转到机器人 @\(info.botUsername)"
            )

        case .internalLinkTypeMainWebApp(let info):
            await openBotChatWithNotice(
                username: info.botUsername,
                notice: "已跳转到机器人 @\(info.botUsername)"
            )

        case .internalLinkTypeGame(let info):
            await openBotChatWithNotice(
                username: info.botUsername,
                notice: "已跳转到机器人 @\(info.botUsername)"
            )

        case .internalLinkTypeSearch:
            onSearchRequested?()

        default:
            if !openInBrowserIfHTTP(originalURL) {
                reportLinkFeedback("暂不支持在应用内打开此类 Telegram 链接", isError: false)
            }
        }
    }

    private func handleLocalFallback(_ fallback: LocalTelegramLinkFallback, originalURL: URL) async {
        switch fallback {
        case .publicChat(let username, let draftText):
            await openPublicChat(username: username, draftText: draftText, unpaidMessagesToken: "")

        case .botStart(let username, let parameter):
            await openBotStart(username: username, parameter: parameter, autostart: false)

        case .botStartInGroup(let username, _):
            await openBotChatWithNotice(
                username: username,
                notice: "已跳转到机器人 @\(username)（邀请入群请前往官方客户端选择群组）"
            )

        case .chatInvite(let link):
            await openChatInvite(inviteLink: link, originalURL: originalURL)

        case .messageLink(let urlString):
            await openMessageLink(urlString: urlString)
        }
    }

    // MARK: - Target Resolution Helpers

    private func openPublicChat(
        username: String,
        draftText: String,
        unpaidMessagesToken: String
    ) async {
        let cleaned = username.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !cleaned.isEmpty else { return }

        do {
            let tdChat = try await service.searchPublicChat(username: cleaned)
            if !unpaidMessagesToken.isEmpty, case .chatTypePrivate(let privateInfo) = tdChat.type {
                try? await service.applyUnpaidMessagesToken(
                    userId: privateInfo.userId,
                    token: unpaidMessagesToken
                )
            }
            navigateToChat(tdChat, draftText: draftText)
        } catch {
            reportLinkFeedback(
                TDLibErrorHelper.userFacingMessage(for: error) ?? "无法打开 @\(cleaned)",
                isError: true
            )
        }
    }

    private func openBotStart(username: String, parameter: String, autostart: Bool) async {
        let cleaned = username.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !cleaned.isEmpty else { return }

        do {
            let tdChat = try await service.searchPublicChat(username: cleaned)
            let botUserId: Int64?
            if case .chatTypePrivate(let privateInfo) = tdChat.type {
                botUserId = privateInfo.userId
            } else {
                botUserId = nil
            }

            let pendingContext: PendingBotStartContext? = (!autostart && !parameter.isEmpty && botUserId != nil)
                ? PendingBotStartContext(
                    chatId: tdChat.id,
                    botUserId: botUserId!,
                    botUsername: cleaned,
                    parameter: parameter
                )
                : nil

            navigateToChat(tdChat, pendingBotStart: pendingContext)

            if autostart, let botUserId {
                await conversation.sendBotStart(parameter: parameter, botUserIdOverride: botUserId)
            }
        } catch {
            reportLinkFeedback(
                TDLibErrorHelper.userFacingMessage(for: error) ?? "无法打开机器人 @\(cleaned)",
                isError: true
            )
        }
    }

    private func openBotChatWithNotice(username: String, notice: String) async {
        let cleaned = username.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !cleaned.isEmpty else { return }

        do {
            let tdChat = try await service.searchPublicChat(username: cleaned)
            navigateToChat(tdChat)
            conversation.showTransientNotice(notice)
        } catch {
            reportLinkFeedback(
                TDLibErrorHelper.userFacingMessage(for: error) ?? "无法打开机器人 @\(cleaned)",
                isError: true
            )
        }
    }

    private func openChatInvite(inviteLink: String, originalURL: URL) async {
        do {
            let inviteInfo = try await service.checkChatInviteLink(inviteLink: inviteLink)
            if inviteInfo.chatId != 0 {
                if let tdChat = try? await service.getChat(chatId: inviteInfo.chatId) {
                    navigateToChat(tdChat)
                    return
                }
                if await chatList.openChat(byId: inviteInfo.chatId) != nil {
                    conversation.selectChat(inviteInfo.chatId)
                    return
                }
            }

            let preview = PendingChatInvitePreview(
                inviteLink: inviteLink,
                originalURL: originalURL,
                tdInfo: inviteInfo
            )
            if let photoId = preview.smallPhotoFileId {
                fileCache.ensureDownloaded(fileId: photoId, priority: 20)
            }
            pendingChatInvite = preview
        } catch {
            reportLinkFeedback(
                TDLibErrorHelper.userFacingMessage(for: error) ?? "该邀请链接已失效或无法访问",
                isError: true
            )
        }
    }

    private func openMessageLink(urlString: String) async {
        do {
            let linkInfo = try await service.getMessageLinkInfo(url: urlString)
            guard linkInfo.chatId != 0 else {
                reportLinkFeedback("无法定位该消息（可能尚未加入对应私密群组或消息已删除）", isError: true)
                return
            }

            let targetMessageId = linkInfo.message?.id
            if let tdChat = try? await service.getChat(chatId: linkInfo.chatId) {
                navigateToChat(tdChat, jumpToMessageId: targetMessageId)
            } else if await chatList.openChat(byId: linkInfo.chatId) != nil {
                conversation.selectChat(linkInfo.chatId, jumpToMessageId: targetMessageId)
            } else {
                reportLinkFeedback("无法打开该消息所在的对话", isError: true)
            }
        } catch {
            reportLinkFeedback(
                TDLibErrorHelper.userFacingMessage(for: error) ?? "无法打开该消息链接",
                isError: true
            )
        }
    }

    private func openSavedMessages() async {
        guard let myUserId = currentUser?.id else { return }
        if let saved = await chatList.ensureSavedMessagesChat(currentUserId: myUserId) {
            chatList.selectedChatId = saved.id
            conversation.selectChat(saved.id)
        }
    }

    private func openUserByPhoneNumber(
        phoneNumber: String,
        draftText: String,
        unpaidMessagesToken: String
    ) async {
        do {
            let user = try await service.searchUserByPhoneNumber(phoneNumber: phoneNumber, onlyLocal: false)
            if !unpaidMessagesToken.isEmpty {
                try? await service.applyUnpaidMessagesToken(userId: user.id, token: unpaidMessagesToken)
            }
            let tdChat = try await service.createPrivateChat(userId: user.id, force: false)
            navigateToChat(tdChat, draftText: draftText)
        } catch {
            reportLinkFeedback(
                TDLibErrorHelper.userFacingMessage(for: error) ?? "未找到该手机号对应的 Telegram 用户",
                isError: true
            )
        }
    }

    private func openUserByToken(token: String, unpaidMessagesToken: String) async {
        do {
            let user = try await service.searchUserByToken(token: token)
            if !unpaidMessagesToken.isEmpty {
                try? await service.applyUnpaidMessagesToken(userId: user.id, token: unpaidMessagesToken)
            }
            let tdChat = try await service.createPrivateChat(userId: user.id, force: false)
            navigateToChat(tdChat)
        } catch {
            reportLinkFeedback(
                TDLibErrorHelper.userFacingMessage(for: error) ?? "该用户临时链接已失效",
                isError: true
            )
        }
    }

    // MARK: - Navigation & Feedback Helpers

    private func navigateToChat(
        _ tdChat: Chat,
        draftText: String = "",
        pendingBotStart: PendingBotStartContext? = nil,
        jumpToMessageId: Int64? = nil
    ) {
        let summary = chatList.cacheAndSelectChat(tdChat)
        conversation.selectChat(summary.id, jumpToMessageId: jumpToMessageId)
        if !draftText.isEmpty {
            conversation.prefillDraftText(draftText)
        }
        if let pendingBotStart {
            conversation.preparePendingBotStart(pendingBotStart)
        }
    }

    @discardableResult
    private func openInBrowserIfHTTP(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        NSWorkspace.shared.open(url)
        return true
    }

    private func reportLinkFeedback(_ message: String, isError: Bool) {
        if conversation.activeChatId != nil {
            if isError {
                conversation.errorMessage = message
            } else {
                conversation.showTransientNotice(message)
            }
        } else {
            onLinkNotice?(message)
        }
    }
}
