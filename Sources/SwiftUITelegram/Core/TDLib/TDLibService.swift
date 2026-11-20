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

/// Owns the process-wide `TDLibClientManager` singleton and exposes an async/await facade
/// plus an `AsyncStream<Update>` for reactive stores.
final class TDLibService {
    private let manager: TDLibClientManager
    private let lock = NSLock()
    private var client: TDLibClient?
    private var updateContinuation: AsyncStream<Update>.Continuation?

    let updates: AsyncStream<Update>

    init() {
        var capturedContinuation: AsyncStream<Update>.Continuation?
        self.updates = AsyncStream<Update>(bufferingPolicy: .unbounded) { continuation in
            capturedContinuation = continuation
        }
        self.updateContinuation = capturedContinuation
        self.manager = TDLibClientManager()
    }

    /// Starts (or restarts after logout/close) the underlying TDLib client.
    func startClient() {
        lock.lock()
        defer { lock.unlock() }

        let newClient = manager.createClient { [weak self] data, client in
            do {
                let update = try client.decoder.decode(Update.self, from: data)
                self?.updateContinuation?.yield(update)
            } catch {
                // Ignore unknown or non-Update responses cleanly.
            }
        }

        // Keep TDLib's internal C++ stdout logging quiet (1 = errors only).
        let verbosity = SetLogVerbosityLevel(newVerbosityLevel: 1)
        _ = try? newClient.execute(query: DTO(verbosity, encoder: newClient.encoder))

        self.client = newClient
    }

    /// Gracefully closes all active TDLib clients on app termination to protect local SQLite integrity.
    func closeAllClients() {
        lock.lock()
        self.client = nil
        lock.unlock()

        manager.closeClients()
        updateContinuation?.finish()
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
            databaseDirectory: AppConfiguration.tdlibDatabaseDirectory,
            databaseEncryptionKey: Data(),
            deviceModel: AppConfiguration.deviceModel,
            filesDirectory: AppConfiguration.tdlibFilesDirectory,
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

    func requestQrCodeAuthentication() async throws {
        let client = try requireClient()
        _ = try await client.requestQrCodeAuthentication(otherUserIds: [])
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

    func openChat(chatId: Int64) async throws {
        let client = try requireClient()
        _ = try await client.openChat(chatId: chatId)
    }

    func closeChat(chatId: Int64) async throws {
        let client = try requireClient()
        _ = try await client.closeChat(chatId: chatId)
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

    func sendTextMessage(chatId: Int64, text: String) async throws -> Message {
        let client = try requireClient()
        let content = InputMessageContent.inputMessageText(
            InputMessageText(
                clearDraft: true,
                linkPreviewOptions: nil,
                text: FormattedText(entities: [], text: text)
            )
        )
        return try await client.sendMessage(
            chatId: chatId,
            inputMessageContent: content,
            options: nil,
            replyMarkup: nil,
            replyTo: nil,
            topicId: nil
        )
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
}
