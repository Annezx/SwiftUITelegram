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

enum MessageOriginInfo: Equatable, Hashable, Sendable {
    case user(userId: Int64)
    case hiddenUser(senderName: String)
    case chat(chatId: Int64, authorSignature: String)
    case channel(chatId: Int64, messageId: Int64, authorSignature: String)

    init(from tdOrigin: MessageOrigin) {
        switch tdOrigin {
        case .messageOriginUser(let value):
            self = .user(userId: value.senderUserId)
        case .messageOriginHiddenUser(let value):
            self = .hiddenUser(senderName: value.senderName)
        case .messageOriginChat(let value):
            self = .chat(chatId: value.senderChatId, authorSignature: value.authorSignature)
        case .messageOriginChannel(let value):
            self = .channel(
                chatId: value.chatId,
                messageId: value.messageId,
                authorSignature: value.authorSignature
            )
        }
    }
}

struct MessageForwardMetadata: Equatable, Hashable, Sendable {
    let date: Foundation.Date
    let origin: MessageOriginInfo

    init(date: Foundation.Date, origin: MessageOriginInfo) {
        self.date = date
        self.origin = origin
    }

    init(from tdForwardInfo: MessageForwardInfo) {
        self.date = Foundation.Date(timeIntervalSince1970: TimeInterval(tdForwardInfo.date))
        self.origin = MessageOriginInfo(from: tdForwardInfo.origin)
    }
}

struct MessageReplyReference: Equatable, Hashable, Sendable {
    let chatId: Int64
    let messageId: Int64
    let quoteText: FormattedTextContent?
    let origin: MessageOriginInfo?
    let externalPreviewText: String?
    let isStoryReply: Bool

    init(
        chatId: Int64,
        messageId: Int64,
        quoteText: FormattedTextContent? = nil,
        origin: MessageOriginInfo? = nil,
        externalPreviewText: String? = nil,
        isStoryReply: Bool = false
    ) {
        self.chatId = chatId
        self.messageId = messageId
        self.quoteText = quoteText
        self.origin = origin
        self.externalPreviewText = externalPreviewText
        self.isStoryReply = isStoryReply
    }

    init(from tdReplyTo: MessageReplyTo) {
        switch tdReplyTo {
        case .messageReplyToMessage(let value):
            self.chatId = value.chatId
            self.messageId = value.messageId
            if let quote = value.quote, !quote.text.text.isEmpty {
                self.quoteText = FormattedTextContent(tdFormattedText: quote.text)
            } else {
                self.quoteText = nil
            }
            self.origin = value.origin.map(MessageOriginInfo.init(from:))
            self.externalPreviewText = value.content.map { MessageDisplayContent(from: $0).previewText }
            self.isStoryReply = false

        case .messageReplyToStory(let value):
            self.chatId = value.storyPosterChatId
            self.messageId = 0
            self.quoteText = nil
            self.origin = nil
            self.externalPreviewText = "[动态]"
            self.isStoryReply = true
        }
    }
}

struct MessagePermissions: Equatable, Hashable, Sendable {
    let canBeReplied: Bool
    let canBeEdited: Bool
    let canBeDeletedOnlyForSelf: Bool
    let canBeDeletedForAllUsers: Bool
    let canBeForwarded: Bool
    let canBeCopied: Bool
    let canBePinned: Bool
    let canGetLink: Bool

    var canBeDeleted: Bool {
        canBeDeletedOnlyForSelf || canBeDeletedForAllUsers
    }

    init(
        canBeReplied: Bool,
        canBeEdited: Bool,
        canBeDeletedOnlyForSelf: Bool,
        canBeDeletedForAllUsers: Bool,
        canBeForwarded: Bool,
        canBeCopied: Bool,
        canBePinned: Bool = false,
        canGetLink: Bool = false
    ) {
        self.canBeReplied = canBeReplied
        self.canBeEdited = canBeEdited
        self.canBeDeletedOnlyForSelf = canBeDeletedOnlyForSelf
        self.canBeDeletedForAllUsers = canBeDeletedForAllUsers
        self.canBeForwarded = canBeForwarded
        self.canBeCopied = canBeCopied
        self.canBePinned = canBePinned
        self.canGetLink = canGetLink
    }

    init(from properties: MessageProperties) {
        self.canBeReplied = properties.canBeReplied
        self.canBeEdited = properties.canBeEdited
        self.canBeDeletedOnlyForSelf = properties.canBeDeletedOnlyForSelf
        self.canBeDeletedForAllUsers = properties.canBeDeletedForAllUsers
        self.canBeForwarded = properties.canBeForwarded
        self.canBeCopied = properties.canBeCopied
        self.canBePinned = properties.canBePinned
        self.canGetLink = properties.canGetLink
    }
}

enum MessageDisplayContent: Equatable, Hashable, Sendable {
    case text(FormattedTextContent)
    case photo(PhotoMedia)
    case video(VideoMedia)
    case videoNote(VideoNoteMedia)
    case animation(AnimationMedia)
    case document(DocumentMedia)
    case voice(VoiceNoteMedia)
    case audio(AudioMedia)
    case sticker(StickerMedia)
    case location(LocationMedia)
    case contact(ContactMedia)
    case unsupported(String)

    init(from content: MessageContent) {
        switch content {
        case .messageText(let value):
            self = .text(FormattedTextContent(tdFormattedText: value.text))

        case .messagePhoto(let value):
            let sortedSizes = value.photo.sizes.sorted { ($0.width * $0.height) < ($1.width * $1.height) }
            if let best = sortedSizes.last {
                let medium = sortedSizes.first { size in
                    size.photo.id != best.photo.id && max(size.width, size.height) >= 240
                }
                self = .photo(
                    PhotoMedia(
                        file: MediaFileDescriptor(tdFile: best.photo),
                        previewFile: medium.map { MediaFileDescriptor(tdFile: $0.photo) },
                        minithumbnailData: value.photo.minithumbnail?.data,
                        width: max(best.width, 1),
                        height: max(best.height, 1),
                        formattedCaption: FormattedTextContent(tdFormattedText: value.caption),
                        hasSpoiler: value.hasSpoiler,
                        showCaptionAboveMedia: value.showCaptionAboveMedia
                    )
                )
            } else {
                self = .unsupported("图片不可用")
            }

        case .messageVideo(let value):
            let thumbnail: ThumbnailInfo?
            if let tdThumb = value.video.thumbnail {
                thumbnail = ThumbnailInfo(tdThumbnail: tdThumb)
            } else if let coverSize = value.cover?.sizes.last {
                thumbnail = ThumbnailInfo(
                    file: MediaFileDescriptor(tdFile: coverSize.photo),
                    width: coverSize.width,
                    height: coverSize.height,
                    format: .jpeg
                )
            } else {
                thumbnail = nil
            }

            self = .video(
                VideoMedia(
                    file: MediaFileDescriptor(tdFile: value.video.video),
                    thumbnail: thumbnail,
                    minithumbnailData: value.video.minithumbnail?.data ?? value.cover?.minithumbnail?.data,
                    width: value.video.width,
                    height: value.video.height,
                    duration: value.video.duration,
                    fileName: value.video.fileName,
                    mimeType: value.video.mimeType,
                    supportsStreaming: value.video.supportsStreaming,
                    formattedCaption: FormattedTextContent(tdFormattedText: value.caption),
                    hasSpoiler: value.hasSpoiler,
                    showCaptionAboveMedia: value.showCaptionAboveMedia
                )
            )

        case .messageVideoNote(let value):
            self = .videoNote(
                VideoNoteMedia(
                    file: MediaFileDescriptor(tdFile: value.videoNote.video),
                    thumbnail: value.videoNote.thumbnail.map(ThumbnailInfo.init(tdThumbnail:)),
                    minithumbnailData: value.videoNote.minithumbnail?.data,
                    length: value.videoNote.length,
                    duration: value.videoNote.duration,
                    isViewed: value.isViewed
                )
            )

        case .messageAnimation(let value):
            self = .animation(
                AnimationMedia(
                    file: MediaFileDescriptor(tdFile: value.animation.animation),
                    thumbnail: value.animation.thumbnail.map(ThumbnailInfo.init(tdThumbnail:)),
                    minithumbnailData: value.animation.minithumbnail?.data,
                    width: value.animation.width,
                    height: value.animation.height,
                    duration: value.animation.duration,
                    fileName: value.animation.fileName,
                    mimeType: value.animation.mimeType,
                    formattedCaption: FormattedTextContent(tdFormattedText: value.caption),
                    hasSpoiler: value.hasSpoiler,
                    showCaptionAboveMedia: value.showCaptionAboveMedia
                )
            )

        case .messageDocument(let value):
            self = .document(
                DocumentMedia(
                    file: MediaFileDescriptor(tdFile: value.document.document),
                    thumbnail: value.document.thumbnail.map(ThumbnailInfo.init(tdThumbnail:)),
                    minithumbnailData: value.document.minithumbnail?.data,
                    fileName: value.document.fileName,
                    mimeType: value.document.mimeType,
                    formattedCaption: FormattedTextContent(tdFormattedText: value.caption)
                )
            )

        case .messageVoiceNote(let value):
            self = .voice(
                VoiceNoteMedia(
                    file: MediaFileDescriptor(tdFile: value.voiceNote.voice),
                    duration: value.voiceNote.duration,
                    mimeType: value.voiceNote.mimeType,
                    waveformLevels: WaveformCodec.decode(value.voiceNote.waveform, targetBars: 36),
                    isListened: value.isListened,
                    formattedCaption: FormattedTextContent(tdFormattedText: value.caption)
                )
            )

        case .messageAudio(let value):
            self = .audio(
                AudioMedia(
                    file: MediaFileDescriptor(tdFile: value.audio.audio),
                    albumCoverThumbnail: value.audio.albumCoverThumbnail.map(ThumbnailInfo.init(tdThumbnail:)),
                    albumCoverMinithumbnailData: value.audio.albumCoverMinithumbnail?.data,
                    duration: value.audio.duration,
                    title: value.audio.title,
                    performer: value.audio.performer,
                    fileName: value.audio.fileName,
                    mimeType: value.audio.mimeType,
                    formattedCaption: FormattedTextContent(tdFormattedText: value.caption)
                )
            )

        case .messageSticker(let value):
            self = .sticker(
                StickerMedia(
                    file: MediaFileDescriptor(tdFile: value.sticker.sticker),
                    thumbnail: value.sticker.thumbnail.map(ThumbnailInfo.init(tdThumbnail:)),
                    emoji: value.sticker.emoji,
                    width: value.sticker.width,
                    height: value.sticker.height,
                    format: StickerMediaFormat(tdFormat: value.sticker.format)
                )
            )

        case .messageAnimatedEmoji(let value):
            if let sticker = value.animatedEmoji.sticker {
                self = .sticker(
                    StickerMedia(
                        file: MediaFileDescriptor(tdFile: sticker.sticker),
                        thumbnail: sticker.thumbnail.map(ThumbnailInfo.init(tdThumbnail:)),
                        emoji: value.emoji.isEmpty ? sticker.emoji : value.emoji,
                        width: value.animatedEmoji.stickerWidth > 0 ? value.animatedEmoji.stickerWidth : sticker.width,
                        height: value.animatedEmoji.stickerHeight > 0 ? value.animatedEmoji.stickerHeight : sticker.height,
                        format: StickerMediaFormat(tdFormat: sticker.format)
                    )
                )
            } else {
                self = .text(FormattedTextContent(text: value.emoji))
            }

        case .messageLocation(let value):
            self = .location(
                LocationMedia(
                    latitude: value.location.latitude,
                    longitude: value.location.longitude
                )
            )

        case .messageContact(let value):
            self = .contact(
                ContactMedia(
                    firstName: value.contact.firstName,
                    lastName: value.contact.lastName,
                    phoneNumber: value.contact.phoneNumber
                )
            )

        default:
            self = .unsupported("暂不支持的消息类型")
        }
    }

    var formattedCaption: FormattedTextContent {
        switch self {
        case .photo(let media): return media.formattedCaption
        case .video(let media): return media.formattedCaption
        case .animation(let media): return media.formattedCaption
        case .document(let media): return media.formattedCaption
        case .voice(let media): return media.formattedCaption
        case .audio(let media): return media.formattedCaption
        case .text, .videoNote, .sticker, .location, .contact, .unsupported:
            return .empty
        }
    }

    var captionText: String {
        formattedCaption.text
    }

    var isTextMessage: Bool {
        if case .text = self { return true }
        return false
    }

    var isEditableInComposer: Bool {
        switch self {
        case .text, .photo, .video, .animation, .document, .voice, .audio:
            return true
        case .videoNote, .sticker, .location, .contact, .unsupported:
            return false
        }
    }

    var editableText: String {
        switch self {
        case .text(let formatted):
            return formatted.text
        default:
            return captionText
        }
    }

    var showCaptionAboveMedia: Bool {
        switch self {
        case .photo(let media): return media.showCaptionAboveMedia
        case .video(let media): return media.showCaptionAboveMedia
        case .animation(let media): return media.showCaptionAboveMedia
        default: return false
        }
    }

    var replyThumbnailFile: MediaFileDescriptor? {
        switch self {
        case .photo(let media):
            return media.previewFile ?? media.file
        case .video(let media):
            return media.thumbnail?.format.isStaticImage == true ? media.thumbnail?.file : nil
        case .animation(let media):
            return media.thumbnail?.format.isStaticImage == true ? media.thumbnail?.file : nil
        case .sticker(let media):
            if media.format == .webp { return media.file }
            return media.thumbnail?.format.isStaticImage == true ? media.thumbnail?.file : nil
        default:
            return nil
        }
    }

    var isAlbumGroupableVisualMedia: Bool {
        switch self {
        case .photo, .video:
            return true
        default:
            return false
        }
    }

    var isBorderlessStyle: Bool {
        switch self {
        case .sticker, .videoNote:
            return true
        default:
            return false
        }
    }

    var primaryFileDescriptor: MediaFileDescriptor? {
        switch self {
        case .photo(let media): return media.file
        case .video(let media): return media.file
        case .videoNote(let media): return media.file
        case .animation(let media): return media.file
        case .document(let media): return media.file
        case .voice(let media): return media.file
        case .audio(let media): return media.file
        case .sticker(let media): return media.file
        case .text, .location, .contact, .unsupported:
            return nil
        }
    }

    var previewText: String {
        switch self {
        case .text(let formatted):
            return formatted.text.replacingOccurrences(of: "\n", with: " ")
        case .photo(let media):
            return media.caption.isEmpty ? "[图片]" : "[图片] \(media.caption)"
        case .video(let media):
            return media.caption.isEmpty ? "[视频 \(MediaFormatters.formatDuration(media.duration))]" : "[视频] \(media.caption)"
        case .videoNote(let media):
            return "[视频消息 \(MediaFormatters.formatDuration(media.duration))]"
        case .animation(let media):
            return media.caption.isEmpty ? "[GIF]" : "[GIF] \(media.caption)"
        case .document(let media):
            if !media.caption.isEmpty { return "[文件] \(media.caption)" }
            return "[文件] \(media.displayFileName)"
        case .voice(let media):
            return "[语音 \(MediaFormatters.formatDuration(media.duration))]"
        case .audio(let media):
            if !media.caption.isEmpty { return "[音频] \(media.caption)" }
            if !media.performer.isEmpty && !media.title.isEmpty {
                return "[音频] \(media.performer) - \(media.title)"
            }
            return "[音频] \(media.displayTitle)"
        case .sticker(let media):
            return media.emoji.isEmpty ? "[贴纸]" : "\(media.emoji) 贴纸"
        case .location:
            return "[位置]"
        case .contact(let media):
            return "[联系人] \(media.displayName)"
        case .unsupported(let label):
            return "[\(label)]"
        }
    }
}

struct MessageItem: Identifiable, Equatable, Hashable, Sendable {
    let id: Int64
    let chatId: Int64
    let date: Foundation.Date
    var editDate: Foundation.Date?
    let isOutgoing: Bool
    var isPinned: Bool
    let sender: MessageSenderKind
    let mediaAlbumId: Int64
    var replyTo: MessageReplyReference?
    var forwardInfo: MessageForwardMetadata?
    var replyMarkup: MessageReplyMarkup?
    var content: MessageDisplayContent
    var deliveryStatus: MessageDeliveryStatus

    init(
        id: Int64,
        chatId: Int64,
        date: Foundation.Date,
        editDate: Foundation.Date? = nil,
        isOutgoing: Bool,
        isPinned: Bool = false,
        sender: MessageSenderKind,
        mediaAlbumId: Int64 = 0,
        replyTo: MessageReplyReference? = nil,
        forwardInfo: MessageForwardMetadata? = nil,
        replyMarkup: MessageReplyMarkup? = nil,
        content: MessageDisplayContent,
        deliveryStatus: MessageDeliveryStatus = .sent
    ) {
        self.id = id
        self.chatId = chatId
        self.date = date
        self.editDate = editDate
        self.isOutgoing = isOutgoing
        self.isPinned = isPinned
        self.sender = sender
        self.mediaAlbumId = mediaAlbumId
        self.replyTo = replyTo
        self.forwardInfo = forwardInfo
        self.replyMarkup = replyMarkup
        self.content = content
        self.deliveryStatus = deliveryStatus
    }

    init(tdMessage: Message) {
        self.id = tdMessage.id
        self.chatId = tdMessage.chatId
        self.date = Foundation.Date(timeIntervalSince1970: TimeInterval(tdMessage.date))
        self.editDate = tdMessage.editDate > 0 ? Foundation.Date(timeIntervalSince1970: TimeInterval(tdMessage.editDate)) : nil
        self.isOutgoing = tdMessage.isOutgoing
        self.isPinned = tdMessage.isPinned
        self.sender = MessageSenderKind(from: tdMessage.senderId)
        self.mediaAlbumId = tdMessage.mediaAlbumId.rawValue
        self.replyTo = tdMessage.replyTo.map(MessageReplyReference.init(from:))
        self.forwardInfo = tdMessage.forwardInfo.map(MessageForwardMetadata.init(from:))
        self.replyMarkup = tdMessage.replyMarkup.map { MessageReplyMarkup(from: $0, messageId: tdMessage.id) }
        self.content = MessageDisplayContent(from: tdMessage.content)
        self.deliveryStatus = MessageDeliveryStatus(from: tdMessage.sendingState)
    }

    mutating func markContentOpened() {
        switch content {
        case .voice(var voice):
            voice.isListened = true
            content = .voice(voice)
        case .videoNote(var videoNote):
            videoNote.isViewed = true
            content = .videoNote(videoNote)
        default:
            break
        }
    }

    var previewText: String {
        content.previewText
    }
}

/// Groups consecutive photo/video messages sharing a non-zero Telegram `mediaAlbumId`
/// so they render cleanly as a single media album grid in the conversation timeline.
enum ConversationTimelineEntry: Identifiable, Equatable, Hashable, Sendable {
    case single(MessageItem)
    case album(albumId: Int64, messages: [MessageItem])

    var id: Int64 {
        switch self {
        case .single(let message):
            return message.id
        case .album(_, let messages):
            return messages[0].id
        }
    }

    var date: Foundation.Date {
        leadMessage.date
    }

    var leadMessage: MessageItem {
        switch self {
        case .single(let message):
            return message
        case .album(_, let messages):
            return messages[0]
        }
    }

    var tailMessage: MessageItem {
        switch self {
        case .single(let message):
            return message
        case .album(_, let messages):
            return messages[messages.count - 1]
        }
    }

    var allMessages: [MessageItem] {
        switch self {
        case .single(let message):
            return [message]
        case .album(_, let messages):
            return messages
        }
    }

    var messageIds: [Int64] {
        allMessages.map(\.id)
    }

    /// Returns the message that carries editable text/caption for this timeline entry.
    var editableMessage: MessageItem {
        switch self {
        case .single(let message):
            return message
        case .album(_, let messages):
            return messages.first(where: { !$0.content.captionText.isEmpty }) ?? messages[0]
        }
    }

    /// Returns the message carrying an inline keyboard for this timeline entry, if any.
    var inlineKeyboardSourceMessage: MessageItem? {
        if tailMessage.replyMarkup?.inlineKeyboardRows != nil {
            return tailMessage
        }
        return allMessages.last(where: { $0.replyMarkup?.inlineKeyboardRows != nil })
    }

    func contains(messageId: Int64) -> Bool {
        allMessages.contains { $0.id == messageId }
    }

    static func group(_ messages: [MessageItem]) -> [ConversationTimelineEntry] {
        var entries: [ConversationTimelineEntry] = []
        entries.reserveCapacity(messages.count)

        var idx = 0
        while idx < messages.count {
            let current = messages[idx]
            if current.mediaAlbumId != 0 && current.content.isAlbumGroupableVisualMedia {
                var grouped = [current]
                var nextIdx = idx + 1
                while nextIdx < messages.count {
                    let candidate = messages[nextIdx]
                    if candidate.mediaAlbumId == current.mediaAlbumId,
                       candidate.isOutgoing == current.isOutgoing,
                       candidate.sender == current.sender,
                       candidate.content.isAlbumGroupableVisualMedia
                    {
                        grouped.append(candidate)
                        nextIdx += 1
                    } else {
                        break
                    }
                }

                if grouped.count >= 2 {
                    entries.append(.album(albumId: current.mediaAlbumId, messages: grouped))
                } else {
                    entries.append(.single(current))
                }
                idx = nextIdx
            } else {
                entries.append(.single(current))
                idx += 1
            }
        }

        return entries
    }
}
