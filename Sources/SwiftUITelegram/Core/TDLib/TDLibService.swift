import Foundation
import TDLibKit

enum TDLibServiceError: LocalizedError {
    case clientNotStarted

    var errorDescription: String? {
        switch self {
        case .clientNotStarted:
            return "TDLib client is not running."
        }
    }
}

/// Exposes an async/await facade plus an `AsyncStream<Update>` for a single Telegram account's
/// `TDLibClient` instance, backed by the process-wide `TDLibClientHub`.
final class TDLibService {
    private let hub: TDLibClientHub
    private let databaseDirectory: String
    private let filesDirectory: String
    private let lock = NSLock()
    private var client: TDLibClient?
    private var updateContinuation: AsyncStream<Update>.Continuation?

    let updates: AsyncStream<Update>

    init(
        hub: TDLibClientHub = TDLibClientHub(),
        databaseDirectory: String = AppConfiguration.tdlibDatabaseDirectory,
        filesDirectory: String = AppConfiguration.tdlibFilesDirectory
    ) {
        self.hub = hub
        self.databaseDirectory = databaseDirectory
        self.filesDirectory = filesDirectory

        var capturedContinuation: AsyncStream<Update>.Continuation?
        self.updates = AsyncStream<Update>(bufferingPolicy: .unbounded) { continuation in
            capturedContinuation = continuation
        }
        self.updateContinuation = capturedContinuation
    }

    /// Starts (or restarts after logout/close) this account's underlying TDLib client.
    func startClient() {
        lock.lock()
        defer { lock.unlock() }

        let newClient = hub.createClient { [weak self] data, client in
            do {
                let update = try client.decoder.decode(Update.self, from: data)
                self?.updateContinuation?.yield(update)
            } catch {
                // Ignore unknown or non-Update responses cleanly.
            }
        }

        self.client = newClient
    }

    /// Gracefully closes only this account's TDLib client instance without affecting other accounts.
    func closeClient() async throws {
        let activeClient: TDLibClient?
        lock.lock()
        activeClient = client
        lock.unlock()

        guard let activeClient else { return }
        _ = try await activeClient.close()
    }

    /// Marks this service's update stream finished once the account session is permanently removed.
    func finishUpdates() {
        lock.lock()
        self.client = nil
        let continuation = updateContinuation
        updateContinuation = nil
        lock.unlock()

        continuation?.finish()
    }

    private func requireClient() throws -> TDLibClient {
        lock.lock()
        defer { lock.unlock() }
        guard let client else {
            throw TDLibServiceError.clientNotStarted
        }
        return client
    }

    // MARK: - Initialization & Auth

    func setTdlibParameters(credentials: TelegramAPICredentials) async throws {
        let client = try requireClient()
        _ = try await client.setTdlibParameters(
            apiHash: credentials.apiHash,
            apiId: credentials.apiId,
            applicationVersion: AppConfiguration.applicationVersion,
            databaseDirectory: databaseDirectory,
            databaseEncryptionKey: Data(),
            deviceModel: AppConfiguration.deviceModel,
            filesDirectory: filesDirectory,
            systemLanguageCode: AppConfiguration.systemLanguageCode,
            systemVersion: AppConfiguration.systemVersion,
            useChatInfoDatabase: true,
            useFileDatabase: true,
            useMessageDatabase: true,
            useSecretChats: false,
            useTestDc: false
        )
    }

    func setAuthenticationPhoneNumber(_ phoneNumber: String) async throws {
        let client = try requireClient()
        _ = try await client.setAuthenticationPhoneNumber(
            phoneNumber: phoneNumber,
            settings: nil
        )
    }

    func requestQrCodeAuthentication(otherUserIds: [Int64] = []) async throws {
        let client = try requireClient()
        _ = try await client.requestQrCodeAuthentication(otherUserIds: otherUserIds)
    }

    func checkAuthenticationCode(_ code: String) async throws {
        let client = try requireClient()
        _ = try await client.checkAuthenticationCode(code: code)
    }

    func checkAuthenticationPassword(_ password: String) async throws {
        let client = try requireClient()
        _ = try await client.checkAuthenticationPassword(password: password)
    }

    func registerUser(firstName: String, lastName: String) async throws {
        let client = try requireClient()
        _ = try await client.registerUser(
            disableNotification: false,
            firstName: firstName,
            lastName: lastName
        )
    }

    func logOut() async throws {
        let client = try requireClient()
        _ = try await client.logOut()
    }

    // MARK: - Account & Users

    func getMe() async throws -> User {
        let client = try requireClient()
        return try await client.getMe()
    }

    func getUser(userId: Int64) async throws -> User {
        let client = try requireClient()
        return try await client.getUser(userId: userId)
    }

    func getUserFullInfo(userId: Int64) async throws -> UserFullInfo {
        let client = try requireClient()
        return try await client.getUserFullInfo(userId: userId)
    }

    func getBasicGroupFullInfo(basicGroupId: Int64) async throws -> BasicGroupFullInfo {
        let client = try requireClient()
        return try await client.getBasicGroupFullInfo(basicGroupId: basicGroupId)
    }

    func getSupergroupFullInfo(supergroupId: Int64) async throws -> SupergroupFullInfo {
        let client = try requireClient()
        return try await client.getSupergroupFullInfo(supergroupId: supergroupId)
    }

    // MARK: - Bot Interactions

    func getCallbackQueryAnswer(
        chatId: Int64,
        messageId: Int64,
        payload: CallbackQueryPayload
    ) async throws -> CallbackQueryAnswer {
        let client = try requireClient()
        return try await client.getCallbackQueryAnswer(
            chatId: chatId,
            messageId: messageId,
            payload: payload
        )
    }

    func getLoginUrl(
        chatId: Int64,
        messageId: Int64,
        buttonId: Int64,
        allowWriteAccess: Bool = false
    ) async throws -> HttpUrl {
        let client = try requireClient()
        return try await client.getLoginUrl(
            allowWriteAccess: allowWriteAccess,
            buttonId: buttonId,
            chatId: chatId,
            messageId: messageId
        )
    }

    func getWebAppUrl(botUserId: Int64, url: String) async throws -> WebAppUrl {
        let client = try requireClient()
        let params = WebAppOpenParameters(
            applicationName: "SwiftUITelegram",
            mode: nil,
            theme: nil
        )
        return try await client.getWebAppUrl(
            botUserId: botUserId,
            parameters: params,
            url: url
        )
    }

    func openWebApp(
        chatId: Int64,
        botUserId: Int64,
        url: String,
        replyTo: InputMessageReplyTo? = nil
    ) async throws -> WebAppInfo {
        let client = try requireClient()
        let params = WebAppOpenParameters(
            applicationName: "SwiftUITelegram",
            mode: nil,
            theme: nil
        )
        return try await client.openWebApp(
            botUserId: botUserId,
            chatId: chatId,
            parameters: params,
            replyTo: replyTo,
            topicId: nil,
            url: url
        )
    }

    func sendBotStartMessage(
        botUserId: Int64,
        chatId: Int64,
        parameter: String = ""
    ) async throws -> Message {
        let client = try requireClient()
        return try await client.sendBotStartMessage(
            botUserId: botUserId,
            chatId: chatId,
            parameter: parameter
        )
    }

    // MARK: - Chats

    func loadChats(list: ChatList, limit: Int = 40) async throws {
        let client = try requireClient()
        _ = try await client.loadChats(chatList: list, limit: limit)
    }

    func getChats(list: ChatList, limit: Int = 100) async throws -> [Int64] {
        let client = try requireClient()
        let result = try await client.getChats(chatList: list, limit: limit)
        return result.chatIds
    }

    func getChat(chatId: Int64) async throws -> Chat {
        let client = try requireClient()
        return try await client.getChat(chatId: chatId)
    }

    func searchChats(query: String, limit: Int = 30) async throws -> [Int64] {
        let client = try requireClient()
        let result = try await client.searchChats(limit: limit, query: query, typeFilter: nil)
        return result.chatIds
    }

    func searchPublicChat(username: String) async throws -> Chat {
        let client = try requireClient()
        return try await client.searchPublicChat(username: username)
    }

    func createPrivateChat(userId: Int64, force: Bool = false) async throws -> Chat {
        let client = try requireClient()
        return try await client.createPrivateChat(force: force, userId: userId)
    }

    func openChat(chatId: Int64) async throws {
        let client = try requireClient()
        _ = try await client.openChat(chatId: chatId)
    }

    func closeChat(chatId: Int64) async throws {
        let client = try requireClient()
        _ = try await client.closeChat(chatId: chatId)
    }

    func toggleChatIsPinned(chatList: ChatList, chatId: Int64, isPinned: Bool) async throws {
        let client = try requireClient()
        _ = try await client.toggleChatIsPinned(
            chatId: chatId,
            chatList: chatList,
            isPinned: isPinned
        )
    }

    func toggleChatIsMarkedAsUnread(chatId: Int64, isMarkedAsUnread: Bool) async throws {
        let client = try requireClient()
        _ = try await client.toggleChatIsMarkedAsUnread(
            chatId: chatId,
            isMarkedAsUnread: isMarkedAsUnread
        )
    }

    func addChatToList(chatId: Int64, chatList: ChatList) async throws {
        let client = try requireClient()
        _ = try await client.addChatToList(
            chatId: chatId,
            chatList: chatList
        )
    }

    func setChatMuteFor(chatId: Int64, muteFor: Int) async throws {
        let client = try requireClient()
        let chat = try await client.getChat(chatId: chatId)
        let current = chat.notificationSettings
        let updated = ChatNotificationSettings(
            disableMentionNotifications: current.disableMentionNotifications,
            disablePinnedMessageNotifications: current.disablePinnedMessageNotifications,
            muteFor: max(0, muteFor),
            muteStories: current.muteStories,
            showPreview: current.showPreview,
            showStoryPoster: current.showStoryPoster,
            soundId: current.soundId,
            storySoundId: current.storySoundId,
            useDefaultDisableMentionNotifications: current.useDefaultDisableMentionNotifications,
            useDefaultDisablePinnedMessageNotifications: current.useDefaultDisablePinnedMessageNotifications,
            useDefaultMuteFor: false,
            useDefaultMuteStories: current.useDefaultMuteStories,
            useDefaultShowPreview: current.useDefaultShowPreview,
            useDefaultShowStoryPoster: current.useDefaultShowStoryPoster,
            useDefaultSound: current.useDefaultSound,
            useDefaultStorySound: current.useDefaultStorySound
        )
        _ = try await client.setChatNotificationSettings(
            chatId: chatId,
            notificationSettings: updated
        )
    }

    func deleteChatHistory(chatId: Int64, removeFromChatList: Bool, revoke: Bool) async throws {
        let client = try requireClient()
        _ = try await client.deleteChatHistory(
            chatId: chatId,
            removeFromChatList: removeFromChatList,
            revoke: revoke
        )
    }

    func leaveChat(chatId: Int64) async throws {
        let client = try requireClient()
        _ = try await client.leaveChat(chatId: chatId)
    }

    func deleteChat(chatId: Int64) async throws {
        let client = try requireClient()
        _ = try await client.deleteChat(chatId: chatId)
    }

    // MARK: - Chat Folders

    func getChatFolder(chatFolderId: Int) async throws -> ChatFolder {
        let client = try requireClient()
        return try await client.getChatFolder(chatFolderId: chatFolderId)
    }

    func createChatFolder(_ folder: ChatFolder) async throws -> ChatFolderInfo {
        let client = try requireClient()
        return try await client.createChatFolder(folder: folder)
    }

    func editChatFolder(chatFolderId: Int, folder: ChatFolder) async throws -> ChatFolderInfo {
        let client = try requireClient()
        return try await client.editChatFolder(chatFolderId: chatFolderId, folder: folder)
    }

    func deleteChatFolder(chatFolderId: Int, leaveChatIds: [Int64] = []) async throws {
        let client = try requireClient()
        _ = try await client.deleteChatFolder(
            chatFolderId: chatFolderId,
            leaveChatIds: leaveChatIds
        )
    }

    func reorderChatFolders(chatFolderIds: [Int], mainChatListPosition: Int) async throws {
        let client = try requireClient()
        _ = try await client.reorderChatFolders(
            chatFolderIds: chatFolderIds,
            mainChatListPosition: mainChatListPosition
        )
    }

    func getChatListsToAddChat(chatId: Int64) async throws -> [ChatList] {
        let client = try requireClient()
        let result = try await client.getChatListsToAddChat(chatId: chatId)
        return result.chatLists
    }

    func readChatList(_ chatList: ChatList) async throws {
        let client = try requireClient()
        _ = try await client.readChatList(chatList: chatList)
    }

    func getChatFolderDefaultIconName(folder: ChatFolder) async throws -> String {
        let client = try requireClient()
        let icon = try await client.getChatFolderDefaultIconName(folder: folder)
        return icon.name
    }

    // MARK: - Messages

    func getChatHistory(
        chatId: Int64,
        fromMessageId: Int64 = 0,
        limit: Int = 40,
        offset: Int = 0,
        onlyLocal: Bool = false
    ) async throws -> [Message] {
        let client = try requireClient()
        let result = try await client.getChatHistory(
            chatId: chatId,
            fromMessageId: fromMessageId,
            limit: limit,
            offset: offset,
            onlyLocal: onlyLocal
        )
        return result.messages ?? []
    }

    func getMessage(chatId: Int64, messageId: Int64) async throws -> Message {
        let client = try requireClient()
        return try await client.getMessage(chatId: chatId, messageId: messageId)
    }

    func getRepliedMessage(chatId: Int64, messageId: Int64) async throws -> Message {
        let client = try requireClient()
        return try await client.getRepliedMessage(chatId: chatId, messageId: messageId)
    }

    func getMessageProperties(chatId: Int64, messageId: Int64) async throws -> MessageProperties {
        let client = try requireClient()
        return try await client.getMessageProperties(chatId: chatId, messageId: messageId)
    }

    static func makeReplyToMessage(messageId: Int64) -> InputMessageReplyTo {
        .inputMessageReplyToMessage(
            InputMessageReplyToMessage(
                checklistTaskId: 0,
                messageId: messageId,
                pollOptionId: "",
                quote: nil
            )
        )
    }

    func sendTextMessage(
        chatId: Int64,
        text: String,
        replyTo: InputMessageReplyTo? = nil
    ) async throws -> Message {
        let content = InputMessageContent.inputMessageText(
            InputMessageText(
                clearDraft: true,
                linkPreviewOptions: nil,
                text: FormattedText(entities: [], text: text)
            )
        )
        return try await sendMessage(chatId: chatId, content: content, replyTo: replyTo)
    }

    func sendMessage(
        chatId: Int64,
        content: InputMessageContent,
        replyTo: InputMessageReplyTo? = nil
    ) async throws -> Message {
        let client = try requireClient()
        return try await client.sendMessage(
            chatId: chatId,
            inputMessageContent: content,
            options: nil,
            replyMarkup: nil,
            replyTo: replyTo,
            topicId: nil
        )
    }

    func sendMessageAlbum(
        chatId: Int64,
        contents: [InputMessageContent],
        replyTo: InputMessageReplyTo? = nil
    ) async throws -> [Message] {
        guard !contents.isEmpty else { return [] }
        if contents.count == 1 {
            let msg = try await sendMessage(chatId: chatId, content: contents[0], replyTo: replyTo)
            return [msg]
        }
        let client = try requireClient()
        let result = try await client.sendMessageAlbum(
            chatId: chatId,
            inputMessageContents: contents,
            options: nil,
            replyTo: replyTo,
            topicId: nil
        )
        return result.messages ?? []
    }

    func sendVoiceNote(
        chatId: Int64,
        filePath: String,
        duration: Int,
        waveform: Data,
        caption: String = "",
        replyTo: InputMessageReplyTo? = nil
    ) async throws -> Message {
        let formattedCaption = caption.isEmpty ? nil : FormattedText(entities: [], text: caption)
        let inputVoice = InputVoiceNote(
            duration: max(duration, 1),
            voiceNote: .inputFileLocal(InputFileLocal(path: filePath)),
            waveform: waveform
        )
        let content = InputMessageContent.inputMessageVoiceNote(
            InputMessageVoiceNote(
                caption: formattedCaption,
                selfDestructType: nil,
                voiceNote: inputVoice
            )
        )
        return try await sendMessage(chatId: chatId, content: content, replyTo: replyTo)
    }

    func editMessageText(chatId: Int64, messageId: Int64, text: String) async throws -> Message {
        let client = try requireClient()
        let content = InputMessageContent.inputMessageText(
            InputMessageText(
                clearDraft: false,
                linkPreviewOptions: nil,
                text: FormattedText(entities: [], text: text)
            )
        )
        return try await client.editMessageText(
            chatId: chatId,
            inputMessageContent: content,
            messageId: messageId,
            replyMarkup: nil
        )
    }

    func editMessageCaption(
        chatId: Int64,
        messageId: Int64,
        caption: String,
        showCaptionAboveMedia: Bool = false
    ) async throws -> Message {
        let client = try requireClient()
        let formattedCaption = caption.isEmpty ? nil : FormattedText(entities: [], text: caption)
        return try await client.editMessageCaption(
            caption: formattedCaption,
            chatId: chatId,
            messageId: messageId,
            replyMarkup: nil,
            showCaptionAboveMedia: showCaptionAboveMedia
        )
    }

    func deleteMessages(chatId: Int64, messageIds: [Int64], revoke: Bool) async throws {
        guard !messageIds.isEmpty else { return }
        let client = try requireClient()
        _ = try await client.deleteMessages(
            chatId: chatId,
            messageIds: messageIds,
            revoke: revoke
        )
    }

    func forwardMessages(
        toChatId: Int64,
        fromChatId: Int64,
        messageIds: [Int64],
        sendCopy: Bool = false,
        removeCaption: Bool = false
    ) async throws -> [Message] {
        guard !messageIds.isEmpty else { return [] }
        let client = try requireClient()
        let sortedIds = Array(Set(messageIds)).sorted()
        let result = try await client.forwardMessages(
            chatId: toChatId,
            fromChatId: fromChatId,
            messageIds: sortedIds,
            options: nil,
            removeCaption: sendCopy ? removeCaption : false,
            sendCopy: sendCopy,
            topicId: nil
        )
        return result.messages ?? []
    }

    func pinChatMessage(
        chatId: Int64,
        messageId: Int64,
        disableNotification: Bool = false,
        onlyForSelf: Bool = false
    ) async throws {
        let client = try requireClient()
        _ = try await client.pinChatMessage(
            chatId: chatId,
            disableNotification: disableNotification,
            messageId: messageId,
            onlyForSelf: onlyForSelf
        )
    }

    func unpinChatMessage(chatId: Int64, messageId: Int64) async throws {
        let client = try requireClient()
        _ = try await client.unpinChatMessage(
            chatId: chatId,
            messageId: messageId
        )
    }

    func getMessageLink(chatId: Int64, messageId: Int64, forAlbum: Bool = false) async throws -> MessageLink {
        let client = try requireClient()
        return try await client.getMessageLink(
            chatId: chatId,
            checklistTaskId: 0,
            forAlbum: forAlbum,
            inMessageThread: false,
            mediaTimestamp: 0,
            messageId: messageId,
            pollOptionId: ""
        )
    }

    static func makeInputContent(
        for attachment: PendingAttachment,
        caption: String,
        sendAsDocument: Bool,
        hasSpoiler: Bool
    ) -> InputMessageContent {
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let formattedCaption = trimmedCaption.isEmpty ? nil : FormattedText(entities: [], text: trimmedCaption)

        let inputThumbnail: InputThumbnail? = attachment.thumbnailURL.map { url in
            InputThumbnail(
                height: attachment.thumbnailHeight,
                thumbnail: .inputFileLocal(InputFileLocal(path: url.path)),
                width: attachment.thumbnailWidth
            )
        }

        if sendAsDocument {
            return .inputMessageDocument(
                InputMessageDocument(
                    caption: formattedCaption,
                    document: InputDocument(
                        disableContentTypeDetection: true,
                        document: .inputFileLocal(InputFileLocal(path: attachment.stagedOriginalURL.path)),
                        thumbnail: inputThumbnail
                    )
                )
            )
        }

        switch attachment.kind {
        case .photo:
            let photoPath = (attachment.preparedPhotoURL ?? attachment.stagedOriginalURL).path
            return .inputMessagePhoto(
                InputMessagePhoto(
                    caption: formattedCaption,
                    hasSpoiler: hasSpoiler,
                    photo: InputPhoto(
                        addedStickerFileIds: [],
                        height: attachment.height,
                        photo: .inputFileLocal(InputFileLocal(path: photoPath)),
                        thumbnail: inputThumbnail,
                        video: nil,
                        width: attachment.width
                    ),
                    selfDestructType: nil,
                    showCaptionAboveMedia: false
                )
            )

        case .video:
            return .inputMessageVideo(
                InputMessageVideo(
                    caption: formattedCaption,
                    hasSpoiler: hasSpoiler,
                    selfDestructType: nil,
                    showCaptionAboveMedia: false,
                    video: InputVideo(
                        addedStickerFileIds: [],
                        cover: nil,
                        duration: attachment.duration,
                        height: attachment.height,
                        startTimestamp: 0,
                        supportsStreaming: true,
                        thumbnail: inputThumbnail,
                        video: .inputFileLocal(InputFileLocal(path: attachment.stagedOriginalURL.path)),
                        width: attachment.width
                    )
                )
            )

        case .animation:
            return .inputMessageAnimation(
                InputMessageAnimation(
                    animation: InputAnimation(
                        addedStickerFileIds: [],
                        animation: .inputFileLocal(InputFileLocal(path: attachment.stagedOriginalURL.path)),
                        duration: attachment.duration,
                        height: attachment.height,
                        thumbnail: inputThumbnail,
                        width: attachment.width
                    ),
                    caption: formattedCaption,
                    hasSpoiler: hasSpoiler,
                    showCaptionAboveMedia: false
                )
            )

        case .audio:
            return .inputMessageAudio(
                InputMessageAudio(
                    audio: InputAudio(
                        albumCoverThumbnail: inputThumbnail,
                        audio: .inputFileLocal(InputFileLocal(path: attachment.stagedOriginalURL.path)),
                        duration: attachment.duration,
                        performer: attachment.audioPerformer,
                        title: attachment.audioTitle
                    ),
                    caption: formattedCaption
                )
            )

        case .document:
            return .inputMessageDocument(
                InputMessageDocument(
                    caption: formattedCaption,
                    document: InputDocument(
                        disableContentTypeDetection: false,
                        document: .inputFileLocal(InputFileLocal(path: attachment.stagedOriginalURL.path)),
                        thumbnail: inputThumbnail
                    )
                )
            )
        }
    }

    func viewMessages(chatId: Int64, messageIds: [Int64]) async throws {
        guard !messageIds.isEmpty else { return }
        let client = try requireClient()
        _ = try await client.viewMessages(
            chatId: chatId,
            forceRead: true,
            messageIds: messageIds,
            source: nil
        )
    }

    func openMessageContent(chatId: Int64, messageId: Int64) async throws {
        let client = try requireClient()
        _ = try await client.openMessageContent(chatId: chatId, messageId: messageId)
    }

    // MARK: - Files

    func downloadFile(fileId: Int, priority: Int = 16) async throws -> File {
        let client = try requireClient()
        return try await client.downloadFile(
            fileId: fileId,
            limit: 0,
            offset: 0,
            priority: priority,
            synchronous: false
        )
    }

    func cancelDownloadFile(fileId: Int, onlyIfPending: Bool = false) async throws {
        let client = try requireClient()
        _ = try await client.cancelDownloadFile(fileId: fileId, onlyIfPending: onlyIfPending)
    }

    func getFile(fileId: Int) async throws -> File {
        let client = try requireClient()
        return try await client.getFile(fileId: fileId)
    }
}
