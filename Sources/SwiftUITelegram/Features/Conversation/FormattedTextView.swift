import AppKit
import SwiftUI

struct FormattedTextView: View {
    @Environment(AppStore.self) private var appStore

    let content: FormattedTextContent
    let isOutgoing: Bool
    var baseFont: Font = .body
    var lineLimit: Int? = nil
    var allowsStructuredBlocks: Bool = true
    var allowsTextSelection: Bool = true

    @State private var isSpoilerRevealed: Bool = false

    private var style: FormattedTextStyle {
        .bubble(isOutgoing: isOutgoing, baseFont: baseFont)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if allowsStructuredBlocks && content.hasStructuredBlocks {
                let blocks = FormattedTextParser.blocks(from: content)
                ForEach(blocks) { block in
                    switch block {
                    case .richText(_, let slice):
                        richTextLeaf(slice)
                    case .codeBlock(_, let code, let language):
                        CodeBlockCardView(
                            code: code,
                            language: language,
                            isOutgoing: isOutgoing
                        )
                    case .blockQuote(_, let quoteContent, let expandable):
                        BlockQuoteCardView(
                            content: quoteContent,
                            expandable: expandable,
                            isOutgoing: isOutgoing,
                            style: style,
                            isSpoilerRevealed: isSpoilerRevealed,
                            allowsTextSelection: allowsTextSelection,
                            onHandleURL: handleURL
                        )
                    }
                }
            } else {
                richTextLeaf(content)
            }

            if content.hasSpoiler && !isSpoilerRevealed && allowsStructuredBlocks {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isSpoilerRevealed = true
                    }
                } label: {
                    Label("显示剧透内容", systemImage: "eye")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isOutgoing ? Color.white.opacity(0.92) : Color.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            isOutgoing ? Color.white.opacity(0.18) : Color.primary.opacity(0.06),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func richTextLeaf(_ value: FormattedTextContent) -> some View {
        let attributed = FormattedTextParser.attributedString(
            from: value,
            style: style,
            revealSpoilers: isSpoilerRevealed
        )

        Group {
            if allowsTextSelection {
                Text(attributed)
                    .textSelection(.enabled)
            } else {
                Text(attributed)
            }
        }
        .lineLimit(lineLimit)
        .tint(style.linkColor)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.openURL, OpenURLAction { url in
            handleURL(url)
        })
    }

    private func handleURL(_ url: URL) -> OpenURLAction.Result {
        switch FormattedTextParser.parseAction(for: url) {
        case .revealSpoilers:
            withAnimation(.easeInOut(duration: 0.18)) {
                isSpoilerRevealed = true
            }
            return .handled

        case .openMention(let username):
            Task {
                if let err = await appStore.chatList.openChatByUsername(username) {
                    appStore.conversation.errorMessage = err
                }
            }
            return .handled

        case .openUser(let userId):
            Task {
                if let err = await appStore.chatList.openPrivateChat(userId: userId) {
                    appStore.conversation.errorMessage = err
                }
            }
            return .handled

        case .searchHashtag(let tag):
            appStore.chatList.updateSearchQuery(tag)
            appStore.triggerSearchFocus()
            return .handled

        case .insertBotCommand(let command):
            appStore.conversation.insertBotCommand(command)
            return .handled

        case .openTelegramLink(let telegramURL):
            Task {
                await appStore.openTelegramURL(telegramURL)
            }
            return .handled

        case .openExternalURL(let externalURL):
            NSWorkspace.shared.open(externalURL)
            return .handled
        }
    }
}

private struct CodeBlockCardView: View {
    let code: String
    let language: String
    let isOutgoing: Bool

    @State private var copiedFeedback: Bool = false

    private var headerTitle: String {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "代码" : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(headerTitle)
                    .font(.caption2.weight(.semibold).monospaced())
                    .foregroundStyle(isOutgoing ? Color.white.opacity(0.82) : Color.secondary)

                Spacer(minLength: 8)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copiedFeedback = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copiedFeedback = false
                    }
                } label: {
                    Label(
                        copiedFeedback ? "已复制" : "复制",
                        systemImage: copiedFeedback ? "checkmark" : "doc.on.doc"
                    )
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isOutgoing ? Color.white.opacity(0.92) : Color.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isOutgoing ? Color.black.opacity(0.16) : Color.primary.opacity(0.05))

            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(isOutgoing ? Color.white : Color.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 220, maxWidth: 460, alignment: .leading)
        }
        .background(
            isOutgoing ? Color.black.opacity(0.22) : Color(nsColor: .textBackgroundColor).opacity(0.82),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isOutgoing ? Color.white.opacity(0.18) : Color(nsColor: .separatorColor).opacity(0.45),
                    lineWidth: 0.75
                )
        )
    }
}

private struct BlockQuoteCardView: View {
    let content: FormattedTextContent
    let expandable: Bool
    let isOutgoing: Bool
    let style: FormattedTextStyle
    let isSpoilerRevealed: Bool
    let allowsTextSelection: Bool
    let onHandleURL: @MainActor (URL) -> OpenURLAction.Result

    @State private var isExpanded: Bool = false

    var body: some View {
        let attributed = FormattedTextParser.attributedString(
            from: content,
            style: style,
            revealSpoilers: isSpoilerRevealed
        )

        VStack(alignment: .leading, spacing: 4) {
            Group {
                if allowsTextSelection {
                    Text(attributed)
                        .textSelection(.enabled)
                } else {
                    Text(attributed)
                }
            }
            .lineLimit(expandable && !isExpanded ? 3 : nil)
            .tint(style.linkColor)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                onHandleURL(url)
            })

            if expandable {
                Button(isExpanded ? "收起引用" : "展开全部") {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isExpanded.toggle()
                    }
                }
                .buttonStyle(.plain)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isOutgoing ? Color.white.opacity(0.88) : Color.accentColor)
            }
        }
        .padding(.leading, 13)
        .padding(.trailing, 9)
        .padding(.vertical, 6)
        .background(
            isOutgoing ? Color.white.opacity(0.14) : Color.accentColor.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(isOutgoing ? Color.white.opacity(0.85) : Color.accentColor)
                .frame(width: 3)
                .padding(.vertical, 5)
                .padding(.leading, 5)
        }
    }
}
