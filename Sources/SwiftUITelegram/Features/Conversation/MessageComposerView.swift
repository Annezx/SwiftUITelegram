import AppKit
import SwiftUI

struct MessageComposerView: View {
    @Binding var text: String
    let pendingAttachments: [PendingAttachment]
    @Binding var sendAsDocument: Bool
    @Binding var sendWithSpoiler: Bool
    let hasToggleableOriginalMedia: Bool
    let hasSpoilerCapableMedia: Bool
    let isPreparingAttachments: Bool
    let isSending: Bool
    let recorder: VoiceRecorderManager

    let onPickMedia: () -> Void
    let onPickDocuments: () -> Void
    let onPasteClipboardImage: () -> Void
    let onRemoveAttachment: (UUID) -> Void
    let onClearAttachments: () -> Void
    let onSend: () -> Void
    let onSendVoiceNote: (RecordedVoiceNote) -> Void

    private var canSend: Bool {
        (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty)
            && !isSending
            && !isPreparingAttachments
    }

    var body: some View {
        VStack(spacing: 0) {
            if !recorder.isRecording && (!pendingAttachments.isEmpty || isPreparingAttachments) {
                attachmentStagingBar
                Divider()
            }

            if recorder.isRecording {
                voiceRecordingBar
            } else {
                inputRow
            }
        }
        .background(.bar)
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
            Menu {
                Button {
                    onPickMedia()
                } label: {
                    Label("选择图片 / 视频 / 音频…", systemImage: "photo.on.rectangle.angled")
                }

                Button {
                    onPickDocuments()
                } label: {
                    Label("选择原文件…", systemImage: "doc")
                }

                Divider()

                Button {
                    onPasteClipboardImage()
                } label: {
                    Label("粘贴剪贴板图片或文件", systemImage: "doc.on.clipboard")
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(isSending)
            .help("发送图片、视频、音频或文件（也支持直接拖拽或 ⌘V 粘贴图片）")

            TextField(
                pendingAttachments.isEmpty
                    ? "输入消息…（Enter 发送，Option+Enter 换行）"
                    : "添加说明文字…（Enter 发送，Option+Enter 换行）",
                text: $text,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(1...6)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.separator.opacity(0.6), lineWidth: 1)
            )
            .onSubmit {
                if canSend {
                    onSend()
                }
            }

            if canSend || isSending {
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
                    .frame(width: 32, height: 32)
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
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(isPreparingAttachments)
                .help("录制语音消息")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
                    .frame(width: 32, height: 32)
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
            .padding(.vertical, 8)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .help("结束并发送语音")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var liveWaveformStrip: some View {
        let levels = recorder.liveLevels
        return HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<36, id: \.self) { index in
                let offset = levels.count - 36 + index
                let level: Float = offset >= 0 && offset < levels.count ? levels[offset] : 0.08
                Capsule()
                    .fill(offset >= 0 ? Color.red.opacity(0.85) : Color.secondary.opacity(0.25))
                    .frame(width: 3, height: max(4, CGFloat(level) * 20))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .frame(height: 22)
        .animation(.linear(duration: 0.06), value: recorder.liveLevels.count)
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
