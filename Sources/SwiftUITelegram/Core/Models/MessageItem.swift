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
            self = .text(value.text.text)

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
                        caption: value.caption.text,
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
                    caption: value.caption.text,
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
                    caption: value.caption.text,
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
                    caption: value.caption.text
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
                    caption: value.caption.text
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
                    caption: value.caption.text
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
                self = .text(value.emoji)
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

    var captionText: String {
        switch self {
        case .photo(let media): return media.caption
        case .video(let media): return media.caption
        case .animation(let media): return media.caption
        case .document(let media): return media.caption
        case .voice(let media): return media.caption
        case .audio(let media): return media.caption
        case .text, .videoNote, .sticker, .location, .contact, .unsupported:
            return ""
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
        case .text(let text):
            return text.replacingOccurrences(of: "\n", with: " ")
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
    let sender: MessageSenderKind
    let mediaAlbumId: Int64
    var content: MessageDisplayContent
    var deliveryStatus: MessageDeliveryStatus

    init(
        id: Int64,
        chatId: Int64,
        date: Foundation.Date,
        editDate: Foundation.Date? = nil,
        isOutgoing: Bool,
        sender: MessageSenderKind,
        mediaAlbumId: Int64 = 0,
        content: MessageDisplayContent,
        deliveryStatus: MessageDeliveryStatus = .sent
    ) {
        self.id = id
        self.chatId = chatId
        self.date = date
        self.editDate = editDate
        self.isOutgoing = isOutgoing
        self.sender = sender
        self.mediaAlbumId = mediaAlbumId
        self.content = content
        self.deliveryStatus = deliveryStatus
    }

    init(tdMessage: Message) {
        self.id = tdMessage.id
        self.chatId = tdMessage.chatId
        self.date = Foundation.Date(timeIntervalSince1970: TimeInterval(tdMessage.date))
        self.editDate = tdMessage.editDate > 0 ? Foundation.Date(timeIntervalSince1970: TimeInterval(tdMessage.editDate)) : nil
        self.isOutgoing = tdMessage.isOutgoing
        self.sender = MessageSenderKind(from: tdMessage.senderId)
        self.mediaAlbumId = tdMessage.mediaAlbumId.rawValue
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
