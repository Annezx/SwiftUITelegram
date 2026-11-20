import Foundation
import TDLibKit

enum MessageSenderKind: Equatable, Hashable, Sendable {
    case user(Int64)
    case chat(Int64)

    init(from sender: MessageSender) {
        switch sender {
        case .messageSenderUser(let user):
            self = .user(user.userId)
        case .messageSenderChat(let chat):
            self = .chat(chat.chatId)
        }
    }
}

enum MessageDeliveryStatus: Equatable, Hashable, Sendable {
    case pending
    case failed(String)
    case sent

    init(from state: MessageSendingState?) {
        guard let state else {
            self = .sent
            return
        }
        switch state {
        case .messageSendingStatePending:
            self = .pending
        case .messageSendingStateFailed(let failed):
            self = .failed(failed.error.message)
        }
    }
}

enum MessageDisplayContent: Equatable, Hashable, Sendable {
    case text(String)
    case photo(fileId: Int?, localPath: String?, width: Int, height: Int, caption: String)
    case video(caption: String, duration: Int)
    case document(fileName: String, caption: String)
    case voice(duration: Int)
    case sticker(emoji: String)
    case animation(caption: String)
    case audio(caption: String)
    case unsupported(String)

    init(from content: MessageContent) {
        switch content {
        case .messageText(let value):
            self = .text(value.text.text)
        case .messagePhoto(let value):
            let chosen = value.photo.sizes.last
            let localPath: String?
            if let local = chosen?.photo.local, local.isDownloadingCompleted, !local.path.isEmpty {
                localPath = local.path
            } else {
                localPath = nil
            }
            self = .photo(
                fileId: chosen?.photo.id,
                localPath: localPath,
                width: chosen?.width ?? 320,
                height: chosen?.height ?? 240,
                caption: value.caption.text
            )
        case .messageVideo(let value):
            self = .video(caption: value.caption.text, duration: value.video.duration)
        case .messageDocument(let value):
            self = .document(fileName: value.document.fileName, caption: value.caption.text)
        case .messageVoiceNote(let value):
            self = .voice(duration: value.voiceNote.duration)
        case .messageSticker(let value):
            self = .sticker(emoji: value.sticker.emoji)
        case .messageAnimation(let value):
            self = .animation(caption: value.caption.text)
        case .messageAudio(let value):
            self = .audio(caption: value.caption.text)
        default:
            self = .unsupported("暂不支持的消息类型")
        }
    }

    var previewText: String {
        switch self {
        case .text(let text):
            return text.replacingOccurrences(of: "\n", with: " ")
        case .photo(_, _, _, _, let caption):
            return caption.isEmpty ? "[图片]" : "[图片] \(caption)"
        case .video(let caption, _):
            return caption.isEmpty ? "[视频]" : "[视频] \(caption)"
        case .document(let fileName, let caption):
            if !caption.isEmpty { return "[文件] \(caption)" }
            return fileName.isEmpty ? "[文件]" : "[文件] \(fileName)"
        case .voice(let duration):
            return "[语音 \(duration)s]"
        case .sticker(let emoji):
            return emoji.isEmpty ? "[贴纸]" : "\(emoji) 贴纸"
        case .animation(let caption):
            return caption.isEmpty ? "[GIF]" : "[GIF] \(caption)"
        case .audio(let caption):
            return caption.isEmpty ? "[音频]" : "[音频] \(caption)"
        case .unsupported(let label):
            return "[\(label)]"
        }
    }
}

struct MessageItem: Identifiable, Equatable, Hashable, Sendable {
    let id: Int64
    let chatId: Int64
    let date: Date
    var editDate: Date?
    let isOutgoing: Bool
    let sender: MessageSenderKind
    var content: MessageDisplayContent
    var deliveryStatus: MessageDeliveryStatus

    init(
        id: Int64,
        chatId: Int64,
        date: Date,
        editDate: Date? = nil,
        isOutgoing: Bool,
        sender: MessageSenderKind,
        content: MessageDisplayContent,
        deliveryStatus: MessageDeliveryStatus = .sent
    ) {
        self.id = id
        self.chatId = chatId
        self.date = date
        self.editDate = editDate
        self.isOutgoing = isOutgoing
        self.sender = sender
        self.content = content
        self.deliveryStatus = deliveryStatus
    }

    init(tdMessage: Message) {
        self.id = tdMessage.id
        self.chatId = tdMessage.chatId
        self.date = Date(timeIntervalSince1970: TimeInterval(tdMessage.date))
        self.editDate = tdMessage.editDate > 0 ? Date(timeIntervalSince1970: TimeInterval(tdMessage.editDate)) : nil
        self.isOutgoing = tdMessage.isOutgoing
        self.sender = MessageSenderKind(from: tdMessage.senderId)
        self.content = MessageDisplayContent(from: tdMessage.content)
        self.deliveryStatus = MessageDeliveryStatus(from: tdMessage.sendingState)
    }

    var previewText: String {
        content.previewText
    }
}
