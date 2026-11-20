import AppKit
import SwiftUI

struct MessageBubbleView: View {
    @Environment(AppStore.self) private var appStore

    let message: MessageItem
    let senderName: String?
    let isReadByRecipient: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isOutgoing {
                Spacer(minLength: 72)
            }

            Grid(alignment: .leading, verticalSpacing: 4) {
                if let senderName, !senderName.isEmpty {
                    GridRow {
                        Text(senderName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }

                GridRow {
                    contentBody
                }

                GridRow {
                    HStack(spacing: 4) {
                        if message.editDate != nil {
                            Text("已编辑")
                                .font(.caption2)
                                .foregroundStyle(metaColor)
                        }

                        Text(Self.timeFormatter.string(from: message.date))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(metaColor)

                        if message.isOutgoing {
                            statusIcon
                        }
                    }
                    .gridCellAnchor(.trailing)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        message.isOutgoing ? Color.clear : Color(nsColor: .separatorColor).opacity(0.45),
                        lineWidth: 0.5
                    )
            )
            .frame(maxWidth: 520, alignment: message.isOutgoing ? .trailing : .leading)
            .contextMenu {
                if let copyable = copyableText {
                    Button("复制文本") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(copyable, forType: .string)
                    }
                }
            }

            if !message.isOutgoing {
                Spacer(minLength: 72)
            }
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        switch message.content {
        case .text(let text):
            Text(text)
                .font(.body)
                .foregroundStyle(primaryTextColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

        case .photo(let fileId, let localPath, let width, let height, let caption):
            VStack(alignment: .leading, spacing: 6) {
                photoPreview(fileId: fileId, localPath: localPath, width: width, height: height)
                if !caption.isEmpty {
                    Text(caption)
                        .font(.body)
                        .foregroundStyle(primaryTextColor)
                        .textSelection(.enabled)
                }
            }

        case .video(let caption, let duration):
            mediaPlaceholder(icon: "film", title: "视频 (\(duration)s)", caption: caption)

        case .document(let fileName, let caption):
            mediaPlaceholder(icon: "doc.fill", title: fileName.isEmpty ? "文件" : fileName, caption: caption)

        case .voice(let duration):
            mediaPlaceholder(icon: "waveform", title: "语音消息 (\(duration)s)", caption: "")

        case .sticker(let emoji):
            HStack(spacing: 6) {
                Text(emoji.isEmpty ? "🙂" : emoji)
                    .font(.largeTitle)
                Text("贴纸")
                    .font(.callout)
                    .foregroundStyle(metaColor)
            }

        case .animation(let caption):
            mediaPlaceholder(icon: "sparkles.tv", title: "GIF 动图", caption: caption)

        case .audio(let caption):
            mediaPlaceholder(icon: "music.note", title: "音频", caption: caption)

        case .unsupported(let label):
            Label(label, systemImage: "questionmark.circle")
                .font(.callout)
                .foregroundStyle(metaColor)
        }
    }

    @ViewBuilder
    private func photoPreview(fileId: Int?, localPath: String?, width: Int, height: Int) -> some View {
        let ratio = width > 0 && height > 0 ? CGFloat(width) / CGFloat(height) : 4.0 / 3.0
        let displayWidth: CGFloat = min(320, max(180, CGFloat(width)))
        let displayHeight: CGFloat = min(320, max(120, displayWidth / max(ratio, 0.4)))

        Group {
            if let fileId, let nsImage = appStore.fileCache.image(for: fileId, knownLocalPath: localPath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.quaternary.opacity(0.5))
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .frame(width: displayWidth, height: displayHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task(id: fileId) {
            if let fileId {
                appStore.fileCache.ensureDownloaded(fileId: fileId, priority: 24)
            }
        }
    }

    private func mediaPlaceholder(icon: String, title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.callout.weight(.medium))
                .foregroundStyle(primaryTextColor)
            if !caption.isEmpty {
                Text(caption)
                    .font(.body)
                    .foregroundStyle(primaryTextColor)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch message.deliveryStatus {
        case .pending:
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundStyle(metaColor)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.yellow)
        case .sent:
            Image(systemName: isReadByRecipient ? "checkmark.circle.fill" : "checkmark")
                .font(.caption2)
                .foregroundStyle(metaColor)
        }
    }

    private var bubbleBackground: Color {
        message.isOutgoing ? Color.accentColor : Color(nsColor: .controlBackgroundColor)
    }

    private var primaryTextColor: Color {
        message.isOutgoing ? .white : .primary
    }

    private var metaColor: Color {
        message.isOutgoing ? .white.opacity(0.78) : .secondary
    }

    private var copyableText: String? {
        switch message.content {
        case .text(let text):
            return text
        case .photo(_, _, _, _, let caption), .video(let caption, _), .document(_, let caption), .animation(let caption), .audio(let caption):
            return caption.isEmpty ? nil : caption
        default:
            return nil
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
