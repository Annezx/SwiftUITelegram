import Foundation
import SwiftUI

struct FormattedTextStyle: Equatable {
    let isOutgoing: Bool
    let baseFont: Font
    let primaryColor: Color
    let linkColor: Color
    let mentionColor: Color
    let inlineCodeBackground: Color
    let mentionPillBackground: Color?
    let spoilerHiddenForeground: Color
    let spoilerHiddenBackground: Color
    let spoilerRevealedBackground: Color

    static func bubble(isOutgoing: Bool, baseFont: Font = .body) -> FormattedTextStyle {
        FormattedTextStyle(
            isOutgoing: isOutgoing,
            baseFont: baseFont,
            primaryColor: isOutgoing ? .white : .primary,
            linkColor: isOutgoing ? .white : .accentColor,
            mentionColor: isOutgoing ? .white : .accentColor,
            inlineCodeBackground: isOutgoing ? Color.white.opacity(0.20) : Color.primary.opacity(0.08),
            mentionPillBackground: isOutgoing ? Color.white.opacity(0.16) : nil,
            spoilerHiddenForeground: isOutgoing ? Color.white.opacity(0.45) : Color.secondary.opacity(0.55),
            spoilerHiddenBackground: isOutgoing ? Color.white.opacity(0.24) : Color.secondary.opacity(0.22),
            spoilerRevealedBackground: isOutgoing ? Color.white.opacity(0.12) : Color.secondary.opacity(0.09)
        )
    }

    static var neutral: FormattedTextStyle {
        .bubble(isOutgoing: false)
    }
}

enum FormattedTextBlock: Identifiable, Equatable {
    case richText(id: Int, content: FormattedTextContent)
    case codeBlock(id: Int, code: String, language: String)
    case blockQuote(id: Int, content: FormattedTextContent, expandable: Bool)

    var id: Int {
        switch self {
        case .richText(let id, _): return id
        case .codeBlock(let id, _, _): return id
        case .blockQuote(let id, _, _): return id
        }
    }
}

enum FormattedTextAction: Equatable {
    case openExternalURL(URL)
    case openTelegramLink(URL)
    case openMention(username: String)
    case openUser(userId: Int64)
    case revealSpoilers
    case searchHashtag(String)
    case insertBotCommand(String)
}

enum FormattedTextParser {
    static let internalScheme = "swiftuitelegram"
    static let spoilerRevealURL = URL(string: "swiftuitelegram://spoiler/reveal")!

    /// Converts a `FormattedTextContent` (mapped from TDLib `FormattedText`) into a SwiftUI-ready
    /// `AttributedString`, accurately converting UTF-16 entity offsets and composing nested styles
    /// (bold, italic, underline, strikethrough, inline/block code, links, spoilers, and @mentions).
    static func attributedString(
        from content: FormattedTextContent,
        style: FormattedTextStyle,
        revealSpoilers: Bool = false
    ) -> AttributedString {
        let text = content.text
        guard !text.isEmpty else { return AttributedString() }

        let utf16Count = text.utf16.count
        let validEntities = content.entities.compactMap { entity -> MessageTextEntity? in
            guard entity.offset >= 0, entity.length > 0, entity.offset < utf16Count else { return nil }
            let clampedLength = min(entity.length, utf16Count - entity.offset)
            guard clampedLength > 0 else { return nil }
            return MessageTextEntity(offset: entity.offset, length: clampedLength, kind: entity.kind)
        }

        if validEntities.isEmpty {
            var plain = AttributedString(text)
            plain.font = style.baseFont
            plain.foregroundColor = style.primaryColor
            return plain
        }

        var boundarySet: Set<Int> = [0, utf16Count]
        boundarySet.reserveCapacity(validEntities.count * 2 + 2)
        for entity in validEntities {
            boundarySet.insert(entity.offset)
            boundarySet.insert(entity.endOffset)
        }
        let boundaries = boundarySet.sorted()

        var result = AttributedString()

        for index in 0..<(boundaries.count - 1) {
            let segStart = boundaries[index]
            let segEnd = boundaries[index + 1]
            guard segStart < segEnd else { continue }

            let lower = safeStringIndex(in: text, utf16Offset: segStart)
            let upper = safeStringIndex(in: text, utf16Offset: segEnd)
            guard lower < upper else { continue }

            let segmentText = String(text[lower..<upper])
            let activeEntities = validEntities.filter { $0.offset <= segStart && $0.endOffset >= segEnd }

            var isBold = false
            var isItalic = false
            var isUnderline = false
            var isStrikethrough = false
            var isCode = false
            var isSpoiler = false
            var isMention = false
            var isWebLink = false
            var isHighlightToken = false
            var resolvedLink: URL?

            for entity in activeEntities {
                switch entity.kind {
                case .bold:
                    isBold = true
                case .italic:
                    isItalic = true
                case .underline:
                    isUnderline = true
                case .strikethrough:
                    isStrikethrough = true
                case .spoiler:
                    isSpoiler = true
                case .code, .pre, .preCode:
                    isCode = true
                case .url:
                    isWebLink = true
                    if resolvedLink == nil {
                        let fullSubstring = substring(in: text, utf16Offset: entity.offset, utf16Length: entity.length)
                        resolvedLink = normalizeExternalURL(fullSubstring)
                    }
                case .textUrl(let urlString):
                    isWebLink = true
                    if resolvedLink == nil {
                        resolvedLink = normalizeExternalURL(urlString)
                    }
                case .emailAddress:
                    isWebLink = true
                    if resolvedLink == nil {
                        let email = substring(in: text, utf16Offset: entity.offset, utf16Length: entity.length)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !email.isEmpty {
                            resolvedLink = URL(string: "mailto:\(email)")
                        }
                    }
                case .phoneNumber:
                    isWebLink = true
                    if resolvedLink == nil {
                        let rawPhone = substring(in: text, utf16Offset: entity.offset, utf16Length: entity.length)
                        let cleaned = rawPhone.filter { $0.isNumber || $0 == "+" }
                        if !cleaned.isEmpty {
                            resolvedLink = URL(string: "tel:\(cleaned)")
                        }
                    }
                case .mention:
                    isMention = true
                    if resolvedLink == nil {
                        let rawMention = substring(in: text, utf16Offset: entity.offset, utf16Length: entity.length)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let username = rawMention.hasPrefix("@") ? String(rawMention.dropFirst()) : rawMention
                        if !username.isEmpty,
                           let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                        {
                            resolvedLink = URL(string: "\(internalScheme)://mention/\(encoded)")
                        }
                    }
                case .mentionName(let userId):
                    isMention = true
                    if resolvedLink == nil {
                        resolvedLink = URL(string: "\(internalScheme)://user/\(userId)")
                    }
                case .hashtag, .cashtag:
                    isHighlightToken = true
                    if resolvedLink == nil {
                        let tag = substring(in: text, utf16Offset: entity.offset, utf16Length: entity.length)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !tag.isEmpty,
                           let encoded = tag.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                        {
                            resolvedLink = URL(string: "\(internalScheme)://hashtag?q=\(encoded)")
                        }
                    }
                case .botCommand:
                    isHighlightToken = true
                    if resolvedLink == nil {
                        let cmd = substring(in: text, utf16Offset: entity.offset, utf16Length: entity.length)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cmd.isEmpty,
                           let encoded = cmd.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                        {
                            resolvedLink = URL(string: "\(internalScheme)://command?c=\(encoded)")
                        }
                    }
                case .blockQuote, .bankCardNumber, .tonAddress, .customEmoji, .mediaTimestamp, .dateTime:
                    break
                }
            }

            if isSpoiler && !revealSpoilers {
                var maskedChunk = AttributedString(maskSpoilerText(segmentText))
                maskedChunk.font = resolvedFont(
                    baseFont: style.baseFont,
                    isBold: isBold,
                    isItalic: isItalic,
                    isCode: isCode,
                    isMention: false
                )
                maskedChunk.foregroundColor = style.spoilerHiddenForeground
                maskedChunk.backgroundColor = style.spoilerHiddenBackground
                maskedChunk.link = spoilerRevealURL
                result.append(maskedChunk)
                continue
            }

            var chunk = AttributedString(segmentText)
            chunk.font = resolvedFont(
                baseFont: style.baseFont,
                isBold: isBold,
                isItalic: isItalic,
                isCode: isCode,
                isMention: isMention
            )

            if isMention {
                chunk.foregroundColor = style.mentionColor
            } else if isWebLink || isHighlightToken || resolvedLink != nil {
                chunk.foregroundColor = style.linkColor
            } else {
                chunk.foregroundColor = style.primaryColor
            }

            if isCode {
                chunk.backgroundColor = style.inlineCodeBackground
            } else if isSpoiler && revealSpoilers {
                chunk.backgroundColor = style.spoilerRevealedBackground
            } else if isMention, let pillBg = style.mentionPillBackground {
                chunk.backgroundColor = pillBg
            }

            if isUnderline || (isWebLink && resolvedLink != nil) {
                chunk.underlineStyle = .single
            }
            if isStrikethrough {
                chunk.strikethroughStyle = .single
            }
            if let resolvedLink {
                chunk.link = resolvedLink
            }

            result.append(chunk)
        }

        return result
    }

    /// Splits a `FormattedTextContent` into visual blocks so fenced code blocks (`.pre`/`.preCode`)
    /// and block quotes (`.blockQuote`) can render as dedicated native containers while preserving
    /// inline rich-text entities inside surrounding paragraphs and block quotes.
    static func blocks(from content: FormattedTextContent) -> [FormattedTextBlock] {
        let text = content.text
        guard !text.isEmpty else { return [] }

        let utf16Count = text.utf16.count
        let validEntities = content.entities.compactMap { entity -> MessageTextEntity? in
            guard entity.offset >= 0, entity.length > 0, entity.offset < utf16Count else { return nil }
            let clampedLength = min(entity.length, utf16Count - entity.offset)
            guard clampedLength > 0 else { return nil }
            return MessageTextEntity(offset: entity.offset, length: clampedLength, kind: entity.kind)
        }

        let spoilerRanges = validEntities.filter { $0.kind == .spoiler }

        // Only promote top-level pre/preCode/blockQuote entities that aren't wrapped inside a spoiler.
        let candidates = validEntities.filter { entity in
            switch entity.kind {
            case .pre, .preCode, .blockQuote:
                let wrappedInSpoiler = spoilerRanges.contains { spoiler in
                    spoiler.offset <= entity.offset && spoiler.endOffset >= entity.endOffset
                }
                return !wrappedInSpoiler
            default:
                return false
            }
        }

        let topLevelBlocks = candidates.filter { candidate in
            !candidates.contains { other in
                other != candidate
                    && other.offset <= candidate.offset
                    && other.endOffset >= candidate.endOffset
            }
        }
        .sorted { lhs, rhs in
            if lhs.offset != rhs.offset { return lhs.offset < rhs.offset }
            return lhs.length > rhs.length
        }

        guard !topLevelBlocks.isEmpty else {
            return [.richText(id: 0, content: content)]
        }

        var blocks: [FormattedTextBlock] = []
        var cursor = 0
        var nextId = 0

        for blockEntity in topLevelBlocks {
            guard blockEntity.offset >= cursor else { continue }

            if blockEntity.offset > cursor {
                let slice = sliceContent(
                    text: text,
                    entities: validEntities,
                    utf16Start: cursor,
                    utf16End: blockEntity.offset,
                    trimLeadingNewline: cursor > 0,
                    trimTrailingNewline: true,
                    excludingEntity: nil
                )
                if !slice.isEmpty {
                    blocks.append(.richText(id: nextId, content: slice))
                    nextId += 1
                }
            }

            switch blockEntity.kind {
            case .pre:
                let code = substring(in: text, utf16Offset: blockEntity.offset, utf16Length: blockEntity.length)
                blocks.append(.codeBlock(id: nextId, code: code, language: ""))
                nextId += 1

            case .preCode(let language):
                let code = substring(in: text, utf16Offset: blockEntity.offset, utf16Length: blockEntity.length)
                blocks.append(.codeBlock(id: nextId, code: code, language: language))
                nextId += 1

            case .blockQuote(let expandable):
                let quoteContent = sliceContent(
                    text: text,
                    entities: validEntities,
                    utf16Start: blockEntity.offset,
                    utf16End: blockEntity.endOffset,
                    trimLeadingNewline: false,
                    trimTrailingNewline: false,
                    excludingEntity: blockEntity
                )
                if !quoteContent.isEmpty {
                    blocks.append(.blockQuote(id: nextId, content: quoteContent, expandable: expandable))
                    nextId += 1
                }

            default:
                break
            }

            cursor = blockEntity.endOffset
        }

        if cursor < utf16Count {
            let tailSlice = sliceContent(
                text: text,
                entities: validEntities,
                utf16Start: cursor,
                utf16End: utf16Count,
                trimLeadingNewline: true,
                trimTrailingNewline: false,
                excludingEntity: nil
            )
            if !tailSlice.isEmpty {
                blocks.append(.richText(id: nextId, content: tailSlice))
            }
        }

        return blocks.isEmpty ? [.richText(id: 0, content: content)] : blocks
    }

    /// Parses a clicked URL from an `AttributedString` link into an in-app or external action.
    static func parseAction(for url: URL) -> FormattedTextAction {
        if url.scheme == internalScheme {
            switch url.host {
            case "spoiler":
                return .revealSpoilers
            case "mention":
                let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let decoded = raw.removingPercentEncoding ?? raw
                if !decoded.isEmpty {
                    return .openMention(username: decoded)
                }
            case "user":
                let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if let userId = Int64(raw) {
                    return .openUser(userId: userId)
                }
            case "hashtag":
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let tag = components.queryItems?.first(where: { $0.name == "q" })?.value,
                   !tag.isEmpty
                {
                    return .searchHashtag(tag)
                }
            case "command":
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let cmd = components.queryItems?.first(where: { $0.name == "c" })?.value,
                   !cmd.isEmpty
                {
                    return .insertBotCommand(cmd)
                }
            default:
                break
            }
        }

        if TelegramLinkDetector.isTelegramLink(url) {
            return .openTelegramLink(url)
        }

        return .openExternalURL(url)
    }

    // MARK: - Private Helpers

    private static func resolvedFont(
        baseFont: Font,
        isBold: Bool,
        isItalic: Bool,
        isCode: Bool,
        isMention: Bool
    ) -> Font {
        var font: Font = isCode ? Font.system(.callout, design: .monospaced) : baseFont
        if isBold {
            font = font.bold()
        } else if isMention && !isCode {
            font = font.weight(.medium)
        }
        if isItalic {
            font = font.italic()
        }
        return font
    }

    private static func maskSpoilerText(_ raw: String) -> String {
        var output = ""
        output.reserveCapacity(raw.count)
        for char in raw {
            if char.isNewline || char == " " || char == "\t" {
                output.append(char)
            } else {
                output.append("░")
            }
        }
        return output
    }

    private static func normalizeExternalURL(_ raw: String) -> URL? {
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

    private static func sliceContent(
        text: String,
        entities: [MessageTextEntity],
        utf16Start: Int,
        utf16End: Int,
        trimLeadingNewline: Bool,
        trimTrailingNewline: Bool,
        excludingEntity: MessageTextEntity?
    ) -> FormattedTextContent {
        let utf16 = text.utf16
        var start = max(0, min(utf16Start, utf16.count))
        var end = max(start, min(utf16End, utf16.count))

        if trimLeadingNewline && start < end {
            let startIdx = utf16.index(utf16.startIndex, offsetBy: start)
            if utf16[startIdx] == 0x000A { // '\n'
                start += 1
            }
        }
        if trimTrailingNewline && start < end {
            let lastIdx = utf16.index(utf16.startIndex, offsetBy: end - 1)
            if utf16[lastIdx] == 0x000A { // '\n'
                end -= 1
            }
        }

        guard start < end else { return .empty }

        let lower = safeStringIndex(in: text, utf16Offset: start)
        let upper = safeStringIndex(in: text, utf16Offset: end)
        guard lower < upper else { return .empty }

        let slicedText = String(text[lower..<upper])
        let rebasedEntities = entities.compactMap { entity -> MessageTextEntity? in
            if let excludingEntity, entity == excludingEntity {
                return nil
            }
            let clampedStart = max(entity.offset, start)
            let clampedEnd = min(entity.endOffset, end)
            guard clampedStart < clampedEnd else { return nil }
            return MessageTextEntity(
                offset: clampedStart - start,
                length: clampedEnd - clampedStart,
                kind: entity.kind
            )
        }

        return FormattedTextContent(text: slicedText, entities: rebasedEntities)
    }

    private static func substring(in text: String, utf16Offset: Int, utf16Length: Int) -> String {
        let lower = safeStringIndex(in: text, utf16Offset: utf16Offset)
        let upper = safeStringIndex(in: text, utf16Offset: utf16Offset + utf16Length)
        guard lower < upper else { return "" }
        return String(text[lower..<upper])
    }

    private static func safeStringIndex(in text: String, utf16Offset: Int) -> String.Index {
        let utf16 = text.utf16
        let clamped = max(0, min(utf16Offset, utf16.count))
        let utf16Idx = utf16.index(utf16.startIndex, offsetBy: clamped)
        if let scalarIdx = utf16Idx.samePosition(in: text.unicodeScalars) {
            return scalarIdx
        }
        if clamped > 0 {
            let prev = utf16.index(before: utf16Idx)
            if let scalarIdx = prev.samePosition(in: text.unicodeScalars) {
                return scalarIdx
            }
        }
        return text.startIndex
    }
}
