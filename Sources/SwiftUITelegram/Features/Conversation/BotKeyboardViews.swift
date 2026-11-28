import SwiftUI

// MARK: - Button Style Palette

private struct BotButtonPalette {
    let background: Color
    let hoverBackground: Color
    let border: Color
    let foreground: Color

    static func resolve(for style: BotButtonStyle, isDisabled: Bool = false) -> BotButtonPalette {
        if isDisabled {
            return BotButtonPalette(
                background: Color(nsColor: .controlBackgroundColor).opacity(0.45),
                hoverBackground: Color(nsColor: .controlBackgroundColor).opacity(0.45),
                border: Color(nsColor: .separatorColor).opacity(0.3),
                foreground: .secondary.opacity(0.55)
            )
        }

        switch style {
        case .default:
            return BotButtonPalette(
                background: Color(nsColor: .controlBackgroundColor).opacity(0.88),
                hoverBackground: Color(nsColor: .selectedControlColor).opacity(0.22),
                border: Color(nsColor: .separatorColor).opacity(0.55),
                foreground: .primary
            )
        case .primary:
            return BotButtonPalette(
                background: Color.accentColor.opacity(0.16),
                hoverBackground: Color.accentColor.opacity(0.26),
                border: Color.accentColor.opacity(0.42),
                foreground: Color.accentColor
            )
        case .danger:
            return BotButtonPalette(
                background: Color.red.opacity(0.14),
                hoverBackground: Color.red.opacity(0.24),
                border: Color.red.opacity(0.38),
                foreground: Color.red
            )
        case .success:
            return BotButtonPalette(
                background: Color.green.opacity(0.15),
                hoverBackground: Color.green.opacity(0.25),
                border: Color.green.opacity(0.4),
                foreground: Color.green
            )
        case .link:
            return BotButtonPalette(
                background: Color(nsColor: .controlBackgroundColor).opacity(0.82),
                hoverBackground: Color.accentColor.opacity(0.14),
                border: Color(nsColor: .separatorColor).opacity(0.48),
                foreground: Color.accentColor
            )
        }
    }
}

// MARK: - Inline Keyboard View (Attached Under Bot Messages)

/// Renders a bot message's `replyMarkupInlineKeyboard` button grid directly beneath the message bubble.
struct InlineKeyboardView: View {
    let messageId: Int64
    let rows: [[InlineKeyboardButtonItem]]
    let inFlightButtonKey: String?
    let onTapButton: (InlineKeyboardButtonItem) -> Void

    @State private var hoveredButtonId: String?

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(row) { button in
                        inlineButtonView(button)
                    }
                }
            }
        }
        .frame(minWidth: 200, maxWidth: 380)
    }

    private func inlineButtonView(_ button: InlineKeyboardButtonItem) -> some View {
        let key = "\(messageId):\(button.id)"
        let isLoading = inFlightButtonKey == key
        let isDisabled = button.action.isDisabled || (inFlightButtonKey != nil && !isLoading)
        let isHovered = hoveredButtonId == button.id && !button.action.isDisabled
        let palette = BotButtonPalette.resolve(for: button.style, isDisabled: button.action.isDisabled)

        return Button {
            onTapButton(button)
        } label: {
            ZStack {
                HStack(spacing: 4) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.mini)
                    }

                    Text(button.text)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(palette.foreground)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, button.action.trailingSymbolName == nil ? 10 : 18)

                if let symbol = button.action.trailingSymbolName, !isLoading {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: symbol)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(palette.foreground.opacity(0.62))
                        }
                        Spacer()
                    }
                    .padding(5)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(
                isHovered ? palette.hoverBackground : palette.background,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 0.6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            if hovering {
                hoveredButtonId = button.id
            } else if hoveredButtonId == button.id {
                hoveredButtonId = nil
            }
        }
        .help(buttonTooltip(for: button))
    }

    private func buttonTooltip(for button: InlineKeyboardButtonItem) -> String {
        switch button.action {
        case .url(let url):
            return "\(button.text)\n\(url)"
        case .loginUrl(_, let url, _):
            return "\(button.text)\n\(url)"
        case .webApp(let url):
            return "\(button.text)（Web App）\n\(url)"
        case .copyText:
            return "点击复制：\(button.text)"
        default:
            return button.text
        }
    }
}

// MARK: - Reply Keyboard Panel (Attached Below Composer Input Row)

/// Renders a bot's custom reply keyboard (`replyMarkupShowKeyboard`) underneath the composer bar.
struct ReplyKeyboardPanelView: View {
    let keyboard: ReplyKeyboardMarkup
    let onTapButton: (ReplyKeyboardButtonItem) -> Void

    @State private var hoveredButtonId: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(Array(keyboard.rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 6) {
                        ForEach(row) { button in
                            replyButtonView(button)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(maxHeight: keyboard.resizeKeyboard ? 184 : 220)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.55))
    }

    private func replyButtonView(_ button: ReplyKeyboardButtonItem) -> some View {
        let isHovered = hoveredButtonId == button.id
        let palette = BotButtonPalette.resolve(for: button.style)

        return Button {
            onTapButton(button)
        } label: {
            HStack(spacing: 5) {
                if let symbol = button.action.trailingSymbolName {
                    Image(systemName: symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.foreground.opacity(0.8))
                }

                Text(button.text)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
                isHovered ? palette.hoverBackground : palette.background,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 0.6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredButtonId = button.id
            } else if hoveredButtonId == button.id {
                hoveredButtonId = nil
            }
        }
    }
}

// MARK: - Bot Menu Button & Commands Popover

/// Composer leading control providing the bot Menu button (`BotMenuButton` Web App or `/` commands popover).
struct BotCommandMenuButton: View {
    let isBotChat: Bool
    let commands: [BotCommandItem]
    let menuButton: BotMenuButtonItem?
    let botUsernameProvider: (Int64) -> String?
    let onSendCommand: (BotCommandItem) -> Void
    let onFillCommand: (BotCommandItem) -> Void
    let onOpenMenuWebApp: () -> Void
    let onSendBuiltInCommand: (String) -> Void

    @State private var isShowingCommandsPopover: Bool = false

    private var hasCustomWebAppMenu: Bool {
        menuButton?.hasCustomWebApp == true
    }

    var body: some View {
        HStack(spacing: 6) {
            if let menuButton, menuButton.hasCustomWebApp {
                Button {
                    onOpenMenuWebApp()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 11, weight: .semibold))
                        Text(menuButton.displayText)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .frame(height: LayoutMetrics.composerControlHeight)
                    .frame(maxWidth: 124)
                    .background(Color.accentColor, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("打开机器人菜单：\(menuButton.displayText)")
            }

            if !hasCustomWebAppMenu || !commands.isEmpty {
                Button {
                    isShowingCommandsPopover.toggle()
                } label: {
                    if isBotChat && !hasCustomWebAppMenu {
                        HStack(spacing: 5) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 11.5, weight: .semibold))
                            Text("菜单")
                                .font(.callout.weight(.medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .frame(height: LayoutMetrics.composerControlHeight)
                        .background(Color.accentColor, in: Capsule())
                        .contentShape(Capsule())
                    } else {
                        Text("/")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(isShowingCommandsPopover ? Color.accentColor : Color.secondary)
                            .frame(width: LayoutMetrics.composerControlHeight, height: LayoutMetrics.composerControlHeight)
                            .background(
                                isShowingCommandsPopover
                                    ? Color.accentColor.opacity(0.14)
                                    : Color.secondary.opacity(0.12),
                                in: Circle()
                            )
                            .contentShape(Circle())
                    }
                }
                .buttonStyle(.plain)
                .help(isBotChat ? "机器人命令菜单" : "群组机器人命令")
                .popover(isPresented: $isShowingCommandsPopover, arrowEdge: .top) {
                    commandsPopoverContent
                }
            }
        }
    }

    private var commandsPopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text(isBotChat ? "机器人菜单" : "可用机器人命令")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if !commands.isEmpty {
                    Text("\(commands.count) 项")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()

            if commands.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    builtInCommandRow(command: "/start", description: "启动或重置机器人对话")
                    builtInCommandRow(command: "/help", description: "向机器人请求帮助说明")

                    Text("该机器人未注册自定义命令列表，您也可以直接输入 / 命令发送。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                }
                .padding(8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(commands) { item in
                            commandRow(item)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 316)
    }

    private func commandRow(_ item: BotCommandItem) -> some View {
        let botUsername: String? = {
            guard !isBotChat, let botId = item.botUserId else { return nil }
            return botUsernameProvider(botId)
        }()

        return HStack(spacing: 8) {
            Button {
                isShowingCommandsPopover = false
                onSendCommand(item)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(item.slashCommand)
                            .font(.callout.weight(.semibold).monospaced())
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)

                        if let botUsername, !botUsername.isEmpty {
                            Text("@\(botUsername)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    if !item.description.isEmpty {
                        Text(item.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                isShowingCommandsPopover = false
                onFillCommand(item)
            } label: {
                Image(systemName: "arrow.up.left")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("填入输入框以补充参数")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func builtInCommandRow(command: String, description: String) -> some View {
        Button {
            isShowingCommandsPopover = false
            onSendBuiltInCommand(command)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(command)
                    .font(.callout.weight(.semibold).monospaced())
                    .foregroundStyle(Color.accentColor)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inline Slash Command Autocomplete Bar

/// Inline command suggestion bar displayed above the composer input when typing `/...`.
struct SlashCommandSuggestionsBar: View {
    let isBotChat: Bool
    let commands: [BotCommandItem]
    let botUsernameProvider: (Int64) -> String?
    let onSendCommand: (BotCommandItem) -> Void
    let onFillCommand: (BotCommandItem) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(commands) { item in
                    let botUsername: String? = {
                        guard !isBotChat, let botId = item.botUserId else { return nil }
                        return botUsernameProvider(botId)
                    }()

                    HStack(spacing: 8) {
                        Button {
                            onSendCommand(item)
                        } label: {
                            HStack(spacing: 8) {
                                Text(item.slashCommand)
                                    .font(.callout.weight(.semibold).monospaced())
                                    .foregroundStyle(Color.accentColor)
                                    .lineLimit(1)

                                if let botUsername, !botUsername.isEmpty {
                                    Text("@\(botUsername)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }

                                if !item.description.isEmpty {
                                    Text(item.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }

                                Spacer(minLength: 4)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            onFillCommand(item)
                        } label: {
                            Image(systemName: "arrow.up.left")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("填入输入框")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 168)
    }
}

// MARK: - 2FA Password Prompt for Password-Protected Callback Buttons

struct BotCallbackPasswordSheet: View {
    @Environment(\.dismiss) private var dismiss

    let request: BotCallbackPasswordRequest
    let onSubmit: (_ password: String) async -> String?

    @State private var password: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("需要两步验证密码")
                        .font(.headline)
                    Text("确认执行按钮「\(request.buttonText)」需要输入您的云端密码。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SecureField("请输入两步验证密码", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    submit()
                }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 10) {
                Spacer()

                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isSubmitting)

                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(minWidth: 56)
                    } else {
                        Text("确认")
                            .frame(minWidth: 56)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting || password.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func submit() {
        guard !isSubmitting, !password.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil
        let submittedPassword = password
        Task {
            let error = await onSubmit(submittedPassword)
            isSubmitting = false
            if let error {
                errorMessage = error
            } else {
                dismiss()
            }
        }
    }
}
