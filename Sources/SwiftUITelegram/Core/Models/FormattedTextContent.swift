import Foundation
import TDLibKit

enum MessageTextEntityKind: Equatable, Hashable, Sendable {
    case bold
    case italic
    case underline
    case strikethrough
    case spoiler
    case code
    case pre
    case preCode(language: String)
    case url
    case textUrl(url: String)
    case mention
    case mentionName(userId: Int64)
    case hashtag
    case cashtag
    case botCommand
    case emailAddress
    case phoneNumber
    case blockQuote(expandable: Bool)
    case bankCardNumber
    case tonAddress
    case customEmoji(id: Int64)
    case mediaTimestamp(seconds: Int)
    case dateTime(unixTime: Int)

    init(from tdType: TextEntityType) {
        switch tdType {
        case .textEntityTypeMention:
            self = .mention
        case .textEntityTypeHashtag:
            self = .hashtag
        case .textEntityTypeCashtag:
            self = .cashtag
        case .textEntityTypeBotCommand:
            self = .botCommand
        case .textEntityTypeUrl:
            self = .url
        case .textEntityTypeEmailAddress:
            self = .emailAddress
        case .textEntityTypePhoneNumber:
            self = .phoneNumber
        case .textEntityTypeBankCardNumber:
            self = .bankCardNumber
        case .textEntityTypeTonAddress:
            self = .tonAddress
        case .textEntityTypeBold:
            self = .bold
        case .textEntityTypeItalic:
            self = .italic
        case .textEntityTypeUnderline:
            self = .underline
        case .textEntityTypeStrikethrough:
            self = .strikethrough
        case .textEntityTypeSpoiler:
            self = .spoiler
        case .textEntityTypeCode:
            self = .code
        case .textEntityTypePre:
            self = .pre
        case .textEntityTypePreCode(let value):
            self = .preCode(language: value.language)
        case .textEntityTypeBlockQuote:
            self = .blockQuote(expandable: false)
        case .textEntityTypeExpandableBlockQuote:
            self = .blockQuote(expandable: true)
        case .textEntityTypeTextUrl(let value):
            self = .textUrl(url: value.url)
        case .textEntityTypeMentionName(let value):
            self = .mentionName(userId: value.userId)
        case .textEntityTypeCustomEmoji(let value):
            self = .customEmoji(id: value.customEmojiId.rawValue)
        case .textEntityTypeMediaTimestamp(let value):
            self = .mediaTimestamp(seconds: value.mediaTimestamp)
        case .textEntityTypeDateTime(let value):
            self = .dateTime(unixTime: value.unixTime)
        }
    }
}

struct MessageTextEntity: Equatable, Hashable, Sendable {
    /// Start offset in UTF-16 code units, matching TDLib's `TextEntity.offset`.
    let offset: Int
    /// Length in UTF-16 code units, matching TDLib's `TextEntity.length`.
    let length: Int
    let kind: MessageTextEntityKind

    var endOffset: Int {
        offset + length
    }

    init(offset: Int, length: Int, kind: MessageTextEntityKind) {
        self.offset = offset
        self.length = length
        self.kind = kind
    }

    init(tdEntity: TextEntity) {
        self.offset = tdEntity.offset
        self.length = tdEntity.length
        self.kind = MessageTextEntityKind(from: tdEntity.type)
    }
}

struct FormattedTextContent: Equatable, Hashable, Sendable {
    let text: String
    let entities: [MessageTextEntity]

    static let empty = FormattedTextContent(text: "", entities: [])

    init(text: String, entities: [MessageTextEntity] = []) {
        self.text = text
        self.entities = entities
    }

    init(tdFormattedText: FormattedText) {
        self.text = tdFormattedText.text
        self.entities = tdFormattedText.entities.compactMap { entity in
            guard entity.offset >= 0, entity.length > 0 else { return nil }
            return MessageTextEntity(tdEntity: entity)
        }
    }

    var isEmpty: Bool {
        text.isEmpty
    }

    var hasSpoiler: Bool {
        entities.contains { $0.kind == .spoiler }
    }

    var hasStructuredBlocks: Bool {
        entities.contains { entity in
            switch entity.kind {
            case .pre, .preCode, .blockQuote:
                return true
            default:
                return false
            }
        }
    }
}
