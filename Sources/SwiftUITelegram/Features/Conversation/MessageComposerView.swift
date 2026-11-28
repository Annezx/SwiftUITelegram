import AppKit
import SwiftUI

struct MessageComposerView: View {
    @Environment(AppStore.self) private var appStore

    @Binding var text: String
    let pendingAttachments: [PendingAttachment]
    @Binding var sendAsDocument: Bool
    @Binding var sendWithSpoiler: Bool
    let hasToggleableOriginalMedia: Bool
    let hasSpoilerCapableMedia: Bool
    let isPreparingAttachments: Bool
    let isSending: Bool
    let composerMode: ComposerMode
    let composerContextTitle: String?
    let composerContextSubtitle: String?
    let composerContextThumbnail: MediaFileDescriptor?
    let focusTrigger: Int
    let recorder: VoiceRecorderManager
    let isBotChat: Bool
    let botCommands: [BotCommandItem]
    let botMenuButton: BotMenuButtonItem?
    let activeReplyKeyboard: ReplyKeyboardMarkup?
    let isReplyKeyboardVisible: Bool
    let customInputPlaceholder: String?
    let chatId: Int64?
    let suggestedStickers: [StickerItem]
    let suggestedStickerEmoji: String
    let botUsernameProvider: (Int64) -> String?

    let onPickMedia: () -> Void
    let onPickDocuments: () -> Void
    let onPasteClipboardImage: () -> Void
    let onRemoveAttachment: (UUID) -> Void
    let onClearAttachments: () -> Void
    let onCancelComposerMode: () -> Void
    let onTapComposerContext: () -> Void
    let onSend: () -> Void
    let onSendVoiceNote: (RecordedVoiceNote) -> Void
    let onInsertEmoji: (String) -> Void
    let onSendSticker: (StickerItem, Bool) -> Void
    let onOpenStickerPack: (Int64) -> Void
    let onDismissStickerSuggestions: () -> Void
    let onSendBotCommand: (BotCommandItem, Bool) -> Void
    let onFillBotCommand: (BotCommandItem) -> Void
    let onSendBuiltInBotCommand: (String) -> Void
    let onOpenBotMenuWebApp: () -> Void
    let onTapReplyKeyboardButton: (ReplyKeyboardButtonItem) -> Void
    let onToggleReplyKeyboard: () -> Void

    @FocusState private var isTextFieldFocused: Bool
    @State private var isShowingStickerEmojiPicker: Bool = false

    private var canSend: Bool {
        if case .editing(let target) = composerMode {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if target.content.isTextMessage {
                return !trimmed.isEmpty && !isSending
            }
            return !isSending
        }
        return (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty)
            && !isSending
            && !isPreparingAttachments
    }

    private var shouldShowBotMenuControl: Bool {
        !composerMode.isEditing && (isBotChat || !botCommands.isEmpty || botMenuButton != nil)
    }

    private var slashCommandSuggestions: [BotCommandItem] {
        guard !recorder.isRecording,
              !composerMode.isEditing,
              !botCommands.isEmpty,
              text.hasPrefix("/"),
              !text.contains(" "),
              !text.contains("\n")
        else {
            return []
        }

        let query = String(text.dropFirst()).lowercased()
        if query.isEmpty {
            return botCommands
        }
        return botCommands.filter { item in
            item.command.lowercased().contains(query)
                || item.description.lowercased().contains(query)
        }
    }

    private var placeholderText: String {
        switch composerMode {
        case .editing(let target):
            return target.content.isTextMessage
                ? "编辑消息…（Enter 保存，Esc 取消）"
                : "编辑说明文字…（留空可清除，Enter 保存）"
        case .replying:
            if pendingAttachments.isEmpty, let custom = customInputPlaceholder, !custom.isEmpty {
                return custom
            }
            return pendingAttachments.isEmpty
                ? "输入回复内容…（Enter 发送，Esc 取消）"
                : "添加回复说明文字…（Enter 发送）"
        case .normal:
            if pendingAttachments.isEmpty, let custom = customInputPlaceholder, !custom.isEmpty {
                return custom
            }
            return pendingAttachments.isEmpty
                ? "输入消息…（Enter 发送，Option+Enter 换行）"
                : "添加说明文字…（Enter 发送，Option+Enter 换行）"
        }
    }

    var body: some View {
        let suggestions = slashCommandSuggestions

        VStack(spacing: 0) {
            if !suggestions.isEmpty {
                SlashCommandSuggestionsBar(
                    isBotChat: isBotChat,
                    commands: suggestions,
                    botUsernameProvider: botUsernameProvider,
                    onSendCommand: { command in
                        onSendBotCommand(command, true)
                    },
                    onFillCommand: { command in
                        onFillBotCommand(command)
                    }
                )
                Divider()
            } else if !recorder.isRecording,
                      !composerMode.isEditing,
                      pendingAttachments.isEmpty,
                      !suggestedStickers.isEmpty
            {
                StickerSuggestionStrip(
                    emoji: suggestedStickerEmoji,
                    stickers: suggestedStickers,
                    onSendSticker: { sticker in
                        onSendSticker(sticker, true)
                    },
                    onDismiss: onDismissStickerSuggestions
                )
                Divider()
            }

            if !recorder.isRecording && composerMode != .normal {
                composerContextBar
                Divider()
            }

            if !recorder.isRecording && !composerMode.isEditing && (!pendingAttachments.isEmpty || isPreparingAttachments) {
                attachmentStagingBar
                Divider()
            }

            if recorder.isRecording {
                voiceRecordingBar
            } else {
                inputRow
            }

            if !recorder.isRecording,
               !composerMode.isEditing,
               isReplyKeyboardVisible,
               let keyboard = activeReplyKeyboard
            {
                Divider()
                ReplyKeyboardPanelView(
                    keyboard: keyboard,
                    onTapButton: onTapReplyKeyboardButton
                )
            }
        }
        .background(.bar)
        .onChange(of: focusTrigger) { _, _ in
            isTextFieldFocused = true
        }
        .onChange(of: chatId) { _, _ in
            isShowingStickerEmojiPicker = false
        }
        .onChange(of: recorder.isRecording) { _, recording in
            if recording {
                isShowingStickerEmojiPicker = false
            }
        }
    }

    // MARK: - Reply / Edit Context Banner

    private var composerContextBar: some View {
        let accent: Color = composerMode.isEditing ? .orange : .accentColor

        return HStack(spacing: 10) {
            Image(systemName: composerMode.isEditing ? "pencil" : "arrowshape.turn.up.left")
                .font(.callout.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 20)

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(accent)
                .frame(width: 2.5, height: 30)

            if let thumb = composerContextThumbnail,
               let image = appStore.fileCache.image(for: thumb)
            {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 1.5) {
                Text(composerContextTitle ?? (composerMode.isEditing ? "编辑消息" : "回复消息"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)

                if let subtitle = composerContextSubtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                onTapComposerContext()
            }

            Button {
                onCancelComposerMode()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("取消 (Esc)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .task(id: composerContextThumbnail?.fileId) {
            if let thumb = composerContextThumbnail {
                appStore.fileCache.ensureDownloaded(thumb, priority: 14)
            }
        }
    }

    // MARK: - Attachment Staging Bar

    private var attachmentStagingBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label("待发送附件 (\(pendingAttachments.count))", systemImage: "paperclip")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if isPreparingAttachments {
                    HStack(spacing: 5) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("正在处理媒体…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if hasToggleableOriginalMedia {
                    Toggle("以原文件发送", isOn: $sendAsDocument)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .font(.caption)
                }

                if hasSpoilerCapableMedia {
                    Toggle("剧透模糊", isOn: $sendWithSpoiler)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .font(.caption)
                }

                if !pendingAttachments.isEmpty {
                    Button("清空") {
                        onClearAttachments()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(pendingAttachments) { item in
                            PendingAttachmentTile(
                                attachment: item,
                                sendAsDocument: sendAsDocument,
                                onRemove: { onRemoveAttachment(item.id) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Standard Input Row

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if shouldShowBotMenuControl {
                BotCommandMenuButton(
                    isBotChat: isBotChat,
                    commands: botCommands,
                    menuButton: botMenuButton,
                    botUsernameProvider: botUsernameProvider,
                    onSendCommand: { command in
                        onSendBotCommand(command, false)
                    },
                    onFillCommand: { command in
                        onFillBotCommand(command)
                    },
                    onOpenMenuWebApp: onOpenBotMenuWebApp,
                    onSendBuiltInCommand: onSendBuiltInBotCommand
                )
            }

            if !composerMode.isEditing {
                AttachmentMenuButton(
                    isDisabled: isSending,
                    onPickMedia: onPickMedia,
                    onPickDocuments: onPickDocuments,
                    onPasteClipboardImage: onPasteClipboardImage
                )
            }

            TextField(
                placeholderText,
                text: $text,
                axis: .vertical
            )
            .focused($isTextFieldFocused)
            .textFieldStyle(.plain)
            .lineLimit(1...6)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: LayoutMetrics.composerControlHeight)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: LayoutMetrics.composerControlHeight / 2, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LayoutMetrics.composerControlHeight / 2, style: .continuous)
                    .strokeBorder(
                        composerMode.isEditing ? Color.orange.opacity(0.55) : Color.secondary.opacity(0.25),
                        lineWidth: 1
                    )
            )
            .onSubmit {
                if canSend {
                    onSend()
                }
            }

            Button {
                isShowingStickerEmojiPicker.toggle()
            } label: {
                Image(systemName: isShowingStickerEmojiPicker ? "face.smiling.fill" : "face.smiling")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isShowingStickerEmojiPicker ? Color.accentColor : Color.secondary)
                    .frame(width: LayoutMetrics.composerControlHeight, height: LayoutMetrics.composerControlHeight)
                    .background(
                        isShowingStickerEmojiPicker
                            ? Color.accentColor.opacity(0.14)
                            : Color.clear,
                        in: Circle()
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(composerMode.isEditing ? "插入 Emoji 表情" : "贴纸与 Emoji 表情面板")
            .popover(isPresented: $isShowingStickerEmojiPicker, arrowEdge: .top) {
                StickerEmojiPickerView(
                    chatId: chatId,
                    allowStickers: !composerMode.isEditing,
                    onSelectEmoji: { emoji in
                        onInsertEmoji(emoji)
                    },
                    onSendSticker: { sticker, keepOpen in
                        if !keepOpen {
                            isShowingStickerEmojiPicker = false
                        }
                        onSendSticker(sticker, false)
                    },
                    onOpenStickerPack: { setId in
                        isShowingStickerEmojiPicker = false
                        onOpenStickerPack(setId)
                    }
                )
                .environment(appStore)
            }

            if !composerMode.isEditing && activeReplyKeyboard != nil {
                Button {
                    onToggleReplyKeyboard()
                } label: {
                    Image(systemName: isReplyKeyboardVisible ? "square.grid.2x2.fill" : "square.grid.2x2")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isReplyKeyboardVisible ? Color.accentColor : Color.secondary)
                        .frame(width: LayoutMetrics.composerControlHeight, height: LayoutMetrics.composerControlHeight)
                        .background(
                            isReplyKeyboardVisible
                                ? Color.accentColor.opacity(0.14)
                                : Color.clear,
                            in: Circle()
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(isReplyKeyboardVisible ? "收起机器人键盘" : "展开机器人键盘")
            }

            if composerMode.isEditing {
                Button {
                    onSend()
                } label: {
                    Group {
                        if isSending {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 26))
                        }
                    }
                    .frame(width: LayoutMetrics.composerControlHeight, height: LayoutMetrics.composerControlHeight)
                }
                .buttonStyle(.plain)
                .foregroundStyle(canSend ? Color.orange : Color.secondary.opacity(0.4))
                .disabled(!canSend)
                .help("保存修改 (Enter)")
            } else if canSend || isSending {
                Button {
                    onSend()
                } label: {
                    Group {
                        if isSending {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 26))
                        }
                    }
                    .frame(width: LayoutMetrics.composerControlHeight, height: LayoutMetrics.composerControlHeight)
                }
                .buttonStyle(.plain)
                .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.4))
                .disabled(!canSend)
                .help("发送消息 (Enter)")
            } else {
                Button {
                    Task { await recorder.startRecording() }
                } label: {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                        .frame(width: LayoutMetrics.composerControlHeight, height: LayoutMetrics.composerControlHeight)
                }
                .buttonStyle(.plain)
                .disabled(isPreparingAttachments)
                .help("录制语音消息")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, LayoutMetrics.composerVerticalPadding)
        .frame(minHeight: LayoutMetrics.bottomBarHeight)
    }

    // MARK: - Voice Recording Bar

    private var voiceRecordingBar: some View {
        HStack(spacing: 12) {
            Button {
                recorder.cancelRecording()
            } label: {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.red.opacity(0.85))
                    .frame(width: LayoutMetrics.composerControlHeight, height: LayoutMetrics.composerControlHeight)
            }
            .buttonStyle(.plain)
            .help("取消录音")

            HStack(spacing: 10) {
                Circle()
                    .fill(.red)
                    .frame(width: 9, height: 9)

                Text(MediaFormatters.formatDuration(recorder.elapsedDuration))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .frame(minWidth: 42, alignment: .leading)

                liveWaveformStrip
            }
            .padding(.horizontal, 14)
            .frame(height: LayoutMetrics.composerControlHeight)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: LayoutMetrics.composerControlHeight / 2, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LayoutMetrics.composerControlHeight / 2, style: .continuous)
                    .strokeBorder(Color.red.opacity(0.35), lineWidth: 1)
            )

            Button {
                if let recorded = recorder.finishRecording() {
                    onSendVoiceNote(recorded)
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: LayoutMetrics.composerControlHeight, height: LayoutMetrics.composerControlHeight)
            }
            .buttonStyle(.plain)
            .help("结束并发送语音")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, LayoutMetrics.composerVerticalPadding)
        .frame(minHeight: LayoutMetrics.bottomBarHeight)
    }

    private var liveWaveformStrip: some View {
        let levels = recorder.liveLevels
        return HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<36, id: \.self) { index in
                let offset = levels.count - 36 + index
                let level: Float = offset >= 0 && offset < levels.count ? levels[offset] : 0.08
                Capsule()
                    .fill(offset >= 0 ? Color.red.opacity(0.85) : Color.secondary.opacity(0.25))
                    .frame(width: 3, height: max(4, CGFloat(level) * 18))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .frame(height: 20)
        .animation(.linear(duration: 0.06), value: recorder.liveLevels.count)
    }
}

/// Renders the attachment button as a plain SwiftUI Button so `paperclip.circle.fill`
/// keeps its exact 26pt size (matching the trailing mic/send button), while presenting
/// a native AppKit `NSMenu` on click instead of `SwiftUI.Menu`'s macOS `NSPopUpButton`
/// which shrinks SF Symbol labels to default control size.
private struct AttachmentMenuButton: View {
    let isDisabled: Bool
    let onPickMedia: () -> Void
    let onPickDocuments: () -> Void
    let onPasteClipboardImage: () -> Void

    @State private var anchorBox = AttachmentMenuAnchorBox()

    var body: some View {
        Button {
            presentMenu()
        } label: {
            Image(systemName: "paperclip.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
                .frame(width: LayoutMetrics.composerControlHeight, height: LayoutMetrics.composerControlHeight)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background(AttachmentMenuAnchorView(box: anchorBox))
        .disabled(isDisabled)
        .help("发送图片、视频、音频或文件（也支持直接拖拽或 ⌘V 粘贴图片）")
    }

    @MainActor
    private func presentMenu() {
        guard let anchorView = anchorBox.view else {
            onPickMedia()
            return
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        var targets: [AttachmentMenuActionTarget] = []

        func makeItem(title: String, symbolName: String, action: @escaping () -> Void) -> NSMenuItem {
            let target = AttachmentMenuActionTarget(handler: action)
            targets.append(target)

            let item = NSMenuItem(
                title: title,
                action: #selector(AttachmentMenuActionTarget.invoke(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.isEnabled = true
            item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            return item
        }

        menu.addItem(makeItem(title: "选择图片 / 视频 / 音频…", symbolName: "photo.on.rectangle.angled", action: onPickMedia))
        menu.addItem(makeItem(title: "选择原文件…", symbolName: "doc", action: onPickDocuments))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "粘贴剪贴板图片或文件", symbolName: "doc.on.clipboard", action: onPasteClipboardImage))

        anchorBox.retainedTargets = targets

        let origin = anchorView.isFlipped
            ? NSPoint(x: 0, y: anchorView.bounds.height + 4)
            : NSPoint(x: 0, y: -4)
        _ = menu.popUp(positioning: nil, at: origin, in: anchorView)
    }
}

@MainActor
private final class AttachmentMenuAnchorBox {
    weak var view: NSView?
    var retainedTargets: [AttachmentMenuActionTarget] = []

    nonisolated init() {}
}

@MainActor
private final class AttachmentMenuActionTarget: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func invoke(_ sender: Any?) {
        handler()
    }
}

private struct AttachmentMenuAnchorView: NSViewRepresentable {
    let box: AttachmentMenuAnchorBox

    func makeNSView(context: Context) -> PassThroughAnchorNSView {
        let view = PassThroughAnchorNSView()
        box.view = view
        return view
    }

    func updateNSView(_ nsView: PassThroughAnchorNSView, context: Context) {
        box.view = nsView
    }
}

private final class PassThroughAnchorNSView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct PendingAttachmentTile: View {
    let attachment: PendingAttachment
    let sendAsDocument: Bool
    let onRemove: () -> Void

    @State private var previewImage: NSImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = previewImage, !sendAsDocument || attachment.kind == .photo || attachment.kind == .video {
                ZStack(alignment: .bottomLeading) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 78, height: 78)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    HStack(spacing: 3) {
                        if sendAsDocument && attachment.supportsOriginalFileToggle {
                            Text("原文件")
                        } else if attachment.kind == .video {
                            Image(systemName: "play.fill")
                            Text(MediaFormatters.formatDuration(attachment.duration))
                                .monospacedDigit()
                        } else if attachment.kind == .animation {
                            Text("GIF")
                        } else if attachment.kind == .audio {
                            Image(systemName: "music.note")
                        }
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.62), in: Capsule())
                    .padding(4)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: attachment.kind.systemImage)
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                    Text(attachment.fileName)
                        .font(.caption2.weight(.medium))
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Text(MediaFormatters.formatFileSize(attachment.fileSize))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(width: 124, height: 78, alignment: .topLeading)
                .background(
                    Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.separator.opacity(0.6), lineWidth: 0.75)
                )
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.75))
            }
            .buttonStyle(.plain)
            .offset(x: 5, y: -5)
            .help("移除此附件")
        }
        .padding(.top, 5)
        .padding(.trailing, 5)
        .task(id: attachment.id) {
            if let url = attachment.previewImageURL {
                previewImage = NSImage(contentsOf: url)
            } else {
                previewImage = nil
            }
        }
    }
}
