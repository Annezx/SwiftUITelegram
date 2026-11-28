import Foundation
import TDLibKit

/// Visual emphasis style mapped from TDLib's `ButtonStyle` (Telegram Bot API button colors).
enum BotButtonStyle: Equatable, Hashable, Sendable {
    case `default`
    case primary
    case danger
    case success
    case link

    init(from tdStyle: ButtonStyle) {
        switch tdStyle {
        case .buttonStyleDefault:
            self = .default
        case .buttonStylePrimary:
            self = .primary
        case .buttonStyleDanger:
            self = .danger
        case .buttonStyleSuccess:
            self = .success
        case .buttonStyleLink:
            self = .link
        }
    }
}

/// Interactive action triggered by a bot message's inline keyboard button.
enum InlineKeyboardButtonAction: Equatable, Hashable, Sendable {
    case callback(Data)
    case callbackWithPassword(Data)
    case url(String)
    case loginUrl(id: Int64, url: String, forwardText: String)
    case webApp(url: String)
    case switchInline(query: String, inCurrentChat: Bool)
    case copyText(String)
    case user(userId: Int64)
    case callbackGame
    case buy
    case disabled

    init(from tdType: InlineKeyboardButtonType) {
        switch tdType {
        case .inlineKeyboardButtonTypeUrl(let info):
            self = .url(info.url)
        case .inlineKeyboardButtonTypeLoginUrl(let info):
            self = .loginUrl(id: info.id, url: info.url, forwardText: info.forwardText)
        case .inlineKeyboardButtonTypeWebApp(let info):
            self = .webApp(url: info.url)
        case .inlineKeyboardButtonTypeCallback(let info):
            self = .callback(info.data)
        case .inlineKeyboardButtonTypeCallbackWithPassword(let info):
            self = .callbackWithPassword(info.data)
        case .inlineKeyboardButtonTypeCallbackGame:
            self = .callbackGame
        case .inlineKeyboardButtonTypeSwitchInline(let info):
            let inCurrentChat: Bool
            if case .targetChatCurrent = info.targetChat {
                inCurrentChat = true
            } else {
                inCurrentChat = false
            }
            self = .switchInline(query: info.query, inCurrentChat: inCurrentChat)
        case .inlineKeyboardButtonTypeBuy:
            self = .buy
        case .inlineKeyboardButtonTypeUser(let info):
            self = .user(userId: info.userId)
        case .inlineKeyboardButtonTypeCopyText(let info):
            self = .copyText(info.text)
        case .inlineKeyboardButtonTypeDisabled:
            self = .disabled
        }
    }

    var isDisabled: Bool {
        if case .disabled = self { return true }
        return false
    }

    var trailingSymbolName: String? {
        switch self {
        case .url, .loginUrl:
            return "arrow.up.right"
        case .webApp:
            return "safari"
        case .copyText:
            return "doc.on.doc"
        case .switchInline:
            return "arrowshape.turn.up.right"
        case .user:
            return "person"
        case .callbackWithPassword:
            return "lock.fill"
        case .callback, .callbackGame, .buy, .disabled:
            return nil
        }
    }
}

/// Single button inside a bot message's `replyMarkupInlineKeyboard`.
struct InlineKeyboardButtonItem: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let text: String
    let style: BotButtonStyle
    let action: InlineKeyboardButtonAction

    init(id: String, text: String, style: BotButtonStyle = .default, action: InlineKeyboardButtonAction) {
        self.id = id
        self.text = text
        self.style = style
        self.action = action
    }

    init(row: Int, column: Int, tdButton: InlineKeyboardButton) {
        self.id = "r\(row)c\(column)"
        self.text = tdButton.text
        self.style = BotButtonStyle(from: tdButton.style)
        self.action = InlineKeyboardButtonAction(from: tdButton.type)
    }
}

/// Action triggered by a bot reply keyboard button (`replyMarkupShowKeyboard`).
enum ReplyKeyboardButtonAction: Equatable, Hashable, Sendable {
    case text
    case requestPhoneNumber
    case requestLocation
    case requestPoll
    case requestUsers
    case requestChat
    case requestManagedBot
    case webApp(url: String)

    init(from tdType: KeyboardButtonType) {
        switch tdType {
        case .keyboardButtonTypeText:
            self = .text
        case .keyboardButtonTypeRequestPhoneNumber:
            self = .requestPhoneNumber
        case .keyboardButtonTypeRequestLocation:
            self = .requestLocation
        case .keyboardButtonTypeRequestPoll:
            self = .requestPoll
        case .keyboardButtonTypeRequestUsers:
            self = .requestUsers
        case .keyboardButtonTypeRequestChat:
            self = .requestChat
        case .keyboardButtonTypeRequestManagedBot:
            self = .requestManagedBot
        case .keyboardButtonTypeWebApp(let info):
            self = .webApp(url: info.url)
        }
    }

    var trailingSymbolName: String? {
        switch self {
        case .text:
            return nil
        case .requestPhoneNumber:
            return "phone"
        case .requestLocation:
            return "location"
        case .requestPoll:
            return "chart.bar"
        case .requestUsers:
            return "person.2"
        case .requestChat:
            return "bubble.left.and.bubble.right"
        case .requestManagedBot:
            return "cpu"
        case .webApp:
            return "safari"
        }
    }
}

/// Single button inside a bot reply keyboard (`replyMarkupShowKeyboard`).
struct ReplyKeyboardButtonItem: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let text: String
    let style: BotButtonStyle
    let action: ReplyKeyboardButtonAction

    init(id: String, text: String, style: BotButtonStyle = .default, action: ReplyKeyboardButtonAction) {
        self.id = id
        self.text = text
        self.style = style
        self.action = action
    }

    init(row: Int, column: Int, tdButton: KeyboardButton) {
        self.id = "kr\(row)c\(column)"
        self.text = tdButton.text
        self.style = BotButtonStyle(from: tdButton.style)
        self.action = ReplyKeyboardButtonAction(from: tdButton.type)
    }
}

/// Custom bot reply keyboard layout attached to a chat via `replyMarkupShowKeyboard`.
struct ReplyKeyboardMarkup: Equatable, Hashable, Sendable {
    let messageId: Int64
    let rows: [[ReplyKeyboardButtonItem]]
    let isPersistent: Bool
    let resizeKeyboard: Bool
    let oneTime: Bool
    let forceReply: Bool
    let inputFieldPlaceholder: String

    var isEmpty: Bool {
        rows.allSatisfy(\.isEmpty)
    }
}

/// Domain representation of TDLib's `ReplyMarkup` on a message.
enum MessageReplyMarkup: Equatable, Hashable, Sendable {
    case inlineKeyboard(rows: [[InlineKeyboardButtonItem]], forceReply: Bool)
    case showKeyboard(ReplyKeyboardMarkup)
    case removeKeyboard(isPersonal: Bool)
    case forceReply(inputFieldPlaceholder: String, isPersonal: Bool)

    init(from tdMarkup: ReplyMarkup, messageId: Int64) {
        switch tdMarkup {
        case .replyMarkupInlineKeyboard(let info):
            let mappedRows = info.rows.enumerated().compactMap { rowIndex, row -> [InlineKeyboardButtonItem]? in
                let buttons = row.enumerated().map { colIndex, btn in
                    InlineKeyboardButtonItem(row: rowIndex, column: colIndex, tdButton: btn)
                }
                return buttons.isEmpty ? nil : buttons
            }
            self = .inlineKeyboard(rows: mappedRows, forceReply: info.forceReply)

        case .replyMarkupShowKeyboard(let info):
            let mappedRows = info.rows.enumerated().compactMap { rowIndex, row -> [ReplyKeyboardButtonItem]? in
                let buttons = row.enumerated().map { colIndex, btn in
                    ReplyKeyboardButtonItem(row: rowIndex, column: colIndex, tdButton: btn)
                }
                return buttons.isEmpty ? nil : buttons
            }
            self = .showKeyboard(
                ReplyKeyboardMarkup(
                    messageId: messageId,
                    rows: mappedRows,
                    isPersistent: info.isPersistent,
                    resizeKeyboard: info.resizeKeyboard,
                    oneTime: info.oneTime,
                    forceReply: info.forceReply,
                    inputFieldPlaceholder: info.inputFieldPlaceholder
                )
            )

        case .replyMarkupRemoveKeyboard(let info):
            self = .removeKeyboard(isPersonal: info.isPersonal)

        case .replyMarkupForceReply(let info):
            self = .forceReply(
                inputFieldPlaceholder: info.inputFieldPlaceholder,
                isPersonal: info.isPersonal
            )
        }
    }

    var inlineKeyboardRows: [[InlineKeyboardButtonItem]]? {
        if case .inlineKeyboard(let rows, _) = self, !rows.isEmpty {
            return rows
        }
        return nil
    }
}

/// Bot slash command metadata sourced from `BotInfo.commands` or group `BotCommands`.
struct BotCommandItem: Identifiable, Equatable, Hashable, Sendable {
    let command: String
    let description: String
    let botUserId: Int64?
    let isEphemeral: Bool

    var id: String {
        "\(botUserId ?? 0)_\(command)"
    }

    var slashCommand: String {
        command.hasPrefix("/") ? command : "/\(command)"
    }

    init(
        command: String,
        description: String,
        botUserId: Int64? = nil,
        isEphemeral: Bool = false
    ) {
        let cleaned = command.trimmingCharacters(in: .whitespacesAndNewlines)
        self.command = cleaned.hasPrefix("/") ? String(cleaned.dropFirst()) : cleaned
        self.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        self.botUserId = botUserId
        self.isEphemeral = isEphemeral
    }

    init(tdCommand: BotCommand, botUserId: Int64? = nil) {
        self.init(
            command: tdCommand.command,
            description: tdCommand.description,
            botUserId: botUserId,
            isEphemeral: tdCommand.isEphemeral
        )
    }
}

/// Custom bot Web App menu button mapped from `BotInfo.menuButton`.
struct BotMenuButtonItem: Equatable, Hashable, Sendable {
    let text: String
    let url: String

    init(tdMenuButton: BotMenuButton) {
        self.text = tdMenuButton.text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.url = tdMenuButton.url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasCustomWebApp: Bool {
        !url.isEmpty
    }

    var displayText: String {
        text.isEmpty ? "菜单" : text
    }
}

/// Modal alert requested by a bot via `CallbackQueryAnswer(showAlert: true)`.
struct BotCallbackAlert: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let message: String
}

/// Prompt payload when a bot inline button requires the user's 2FA password.
struct BotCallbackPasswordRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let chatId: Int64
    let messageId: Int64
    let buttonId: String
    let buttonText: String
    let payloadData: Data
}

/// Avatar & color metadata for a message sender in group chats (supports both users and anonymous/channel chat senders).
struct SenderAvatarInfo: Equatable, Hashable, Sendable {
    let title: String
    let initials: String
    let accentColorId: Int
    let smallPhotoFileId: Int?
    let smallPhotoLocalPath: String?
    let userId: Int64?
}
