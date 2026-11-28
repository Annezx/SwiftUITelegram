import Foundation
import Observation
import TDLibKit

/// Self-contained runtime session for a single Telegram account.
/// Each session owns an isolated `TDLibService` (with its own SQLite database & files directory),
/// `FileCacheStore` (avoiding cross-account `fileId` collisions), `ChatListStore`, and `ConversationStore`.
@MainActor
@Observable
final class AccountSession: Identifiable {
    let id: UUID
    let storageKey: String
    let databaseDirectory: String
    let filesDirectory: String

    let service: TDLibService
    let fileCache: FileCacheStore
    let chatList: ChatListStore
    let conversation: ConversationStore

    private var updatesTask: Task<Void, Never>?
    private var hasStarted = false
    private var awaitingTdlibParameters = false
    private var isClosingForRemoval = false
    private var shouldDeleteStorageOnClose = false
    private var hasNotifiedRemoval = false

    var profile: StoredAccountProfile
    var isTemporaryAddFlow: Bool

    private(set) var authStep: AuthStep = .configuring
    private(set) var connectionStatus: ConnectionStatus = .connecting
    private(set) var currentUser: UserSummary?
    private(set) var isSubmittingAuth: Bool = false
    private(set) var unreadMessageCount: Int = 0
    private(set) var unreadChatCount: Int = 0
    var authErrorMessage: String?
    var pendingChatInvite: PendingChatInvitePreview?

    var credentialsProvider: () -> TelegramAPICredentials? = { nil }
    var onAuthorized: ((AccountSession, UserSummary) async -> Void)?
    var onProfileUpdated: ((AccountSession) -> Void)?
    var onClosedForRemoval: ((AccountSession, Bool) -> Void)?
    var onSearchRequested: (() -> Void)?
    var onLinkNotice: ((String) -> Void)?

    init(
        profile: StoredAccountProfile,
        hub: TDLibClientHub,
        isTemporaryAddFlow: Bool = false
    ) {
        self.id = profile.id
        self.storageKey = profile.storageKey
        self.profile = profile
        self.isTemporaryAddFlow = isTemporaryAddFlow

        let dbDir = AppConfiguration.tdlibDatabaseDirectory(for: profile.storageKey)
        let filesDir = AppConfiguration.tdlibFilesDirectory(for: profile.storageKey)
        self.databaseDirectory = dbDir
        self.filesDirectory = filesDir

        let service = TDLibService(
            hub: hub,
            databaseDirectory: dbDir,
            filesDirectory: filesDir
        )
        self.service = service
        self.fileCache = FileCacheStore(service: service)
        self.chatList = ChatListStore(service: service)
        self.conversation = ConversationStore(service: service)

        self.conversation.onOpenTelegramURL = { [weak self] url in
            await self?.openTelegramURL(url)
        }
    }

    // MARK: - Display Metadata

    var isReady: Bool {
        authStep == .ready
    }

    var displayName: String {
        currentUser?.displayName ?? profile.fallbackDisplayName
    }

    var username: String? {
        currentUser?.username ?? profile.username
    }

    var phoneNumber: String {
        currentUser?.phoneNumber ?? profile.phoneNumber
    }

    var accentColorId: Int {
        if let user = currentUser {
            return Int(abs(user.id) % 7)
        }
        return profile.accentColorId
    }

    var avatarInitials: String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var smallPhotoFileId: Int? {
        currentUser?.smallPhotoFileId
    }

    var smallPhotoLocalPath: String? {
        currentUser?.smallPhotoLocalPath
    }

    // MARK: - Lifecycle

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        startUpdateLoop()
        service.startClient()
    }

    func applyCredentialsIfAwaiting(_ credentials: TelegramAPICredentials) async {
        guard awaitingTdlibParameters else { return }
        await applyTdlibParameters(credentials)
    }

    /// Closes this single account's TDLib client (optionally logging out server-side first)
    /// and invokes `onClosedForRemoval` once TDLib confirms `authorizationStateClosed`.
    func closeForRemoval(logOutFirst: Bool, deleteStorage: Bool) {
        guard !isClosingForRemoval else { return }
        isClosingForRemoval = true
        shouldDeleteStorageOnClose = deleteStorage

        guard hasStarted else {
            finishRemoval()
            return
        }

        Task { [weak self] in
            guard let self else { return }
            if logOutFirst {
                do {
                    try await self.service.logOut()
                } catch {
                    _ = try? await self.service.closeClient()
                }
            } else {
                _ = try? await self.service.closeClient()
            }

            // Safety fallback in case the client had already closed or never initialized.
            try? await Task.sleep(for: .seconds(5))
            if !self.hasNotifiedRemoval {
                self.finishRemoval()
            }
        }
    }

    /// Stops this session's Swift update loop before `TDLibClientHub.closeAllClients()` runs at app exit.
    func stopForAppShutdown() {
        updatesTask?.cancel()
        updatesTask = nil
        service.finishUpdates()
    }

    // MARK: - Authentication Actions

    func submitPhoneNumber(_ phoneNumber: String) async {
        let cleaned = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            authErrorMessage = "请输入包含国家区号的手机号（例如 +8613800138000）。"
            return
        }
        await performAuthAction {
            try await self.service.setAuthenticationPhoneNumber(cleaned)
        }
    }

    func requestQRCodeLogin(otherUserIds: [Int64]) async {
        await performAuthAction {
            try await self.service.requestQrCodeAuthentication(otherUserIds: otherUserIds)
        }
    }

    func switchBackToPhoneLogin() async {
        // Per TDLib spec, setAuthenticationPhoneNumber cannot be called directly from
        // authorizationStateWaitOtherDeviceConfirmation; logging out cleanly resets this client.
        await logOutInPlace()
    }

    func submitAuthCode(_ code: String) async {
        let cleaned = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            authErrorMessage = "请输入验证码。"
            return
        }
        await performAuthAction {
            try await self.service.checkAuthenticationCode(cleaned)
        }
    }

    func submitPassword(_ password: String) async {
        guard !password.isEmpty else {
            authErrorMessage = "请输入两步验证密码。"
            return
        }
        await performAuthAction {
            try await self.service.checkAuthenticationPassword(password)
        }
    }

    func submitRegistration(firstName: String, lastName: String) async {
        let cleanFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanFirst.isEmpty else {
            authErrorMessage = "请输入名字。"
            return
        }
        await performAuthAction {
            try await self.service.registerUser(firstName: cleanFirst, lastName: cleanLast)
        }
    }

    func logOutInPlace() async {
        await performAuthAction {
            try await self.service.logOut()
        }
    }

    // MARK: - Update Dispatching

    private func startUpdateLoop() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            guard let self else { return }
            for await update in self.service.updates {
                if Task.isCancelled { break }
                await self.handleUpdate(update)
            }
        }
    }

    private func handleUpdate(_ update: Update) async {
        switch update {
        case .updateAuthorizationState(let info):
            await handleAuthorizationState(info.authorizationState)

        case .updateConnectionState(let info):
            connectionStatus = ConnectionStatus(from: info.state)

        case .updateFile(let info):
            fileCache.handleFileUpdate(info.file)

        case .updateUnreadMessageCount(let info):
            if case .chatListMain = info.chatList {
                unreadMessageCount = max(0, info.unreadCount)
            }
            chatList.handleUpdate(update)

        case .updateUnreadChatCount(let info):
            if case .chatListMain = info.chatList {
                unreadChatCount = max(0, info.unreadCount)
            }
            chatList.handleUpdate(update)

        case .updateUser(let info):
            chatList.handleUpdate(update)
            if info.user.id == currentUser?.id {
                let updated = UserSummary(tdUser: info.user)
                currentUser = updated
                syncProfile(from: updated)
                onProfileUpdated?(self)
            }

        default:
            chatList.handleUpdate(update)
            conversation.handleUpdate(update)
        }
    }

    private func handleAuthorizationState(_ state: AuthorizationState) async {
        authErrorMessage = nil

        switch state {
        case .authorizationStateWaitTdlibParameters:
            awaitingTdlibParameters = true
            if let credentials = credentialsProvider(), credentials.isValid {
                authStep = .configuring
                await applyTdlibParameters(credentials)
            } else {
                authStep = .needsCredentials
            }

        case .authorizationStateReady:
            awaitingTdlibParameters = false
            authStep = .ready
            await handleAuthorized()

        case .authorizationStateClosed:
            awaitingTdlibParameters = false
            unreadMessageCount = 0
            unreadChatCount = 0
            currentUser = nil
            pendingChatInvite = nil
            chatList.reset()
            conversation.reset()
            fileCache.reset()

            if isClosingForRemoval {
                finishRemoval()
                return
            }

            // Reset profile identity when logging out of the sole remaining slot.
            profile.userId = nil
            profile.displayName = ""
            profile.username = nil
            profile.phoneNumber = ""
            onProfileUpdated?(self)

            authStep = .configuring
            // Recreate a fresh TDLib client so the user can sign in again without restarting the app.
            service.startClient()

        default:
            awaitingTdlibParameters = false
            authStep = AuthStep.from(state)
        }
    }

    private func applyTdlibParameters(_ credentials: TelegramAPICredentials) async {
        isSubmittingAuth = true
        defer { isSubmittingAuth = false }

        do {
            try await service.setTdlibParameters(credentials: credentials)
            awaitingTdlibParameters = false
        } catch {
            authErrorMessage = TDLibErrorHelper.userFacingMessage(for: error)
            authStep = .needsCredentials
        }
    }

    private func handleAuthorized() async {
        if let me = try? await service.getMe() {
            let summary = UserSummary(tdUser: me)
            currentUser = summary
            syncProfile(from: summary)

            if let photoFileId = summary.smallPhotoFileId {
                fileCache.ensureDownloaded(fileId: photoFileId, priority: 14)
            }

            if let onAuthorized {
                await onAuthorized(self, summary)
            }
        }

        guard !isClosingForRemoval else { return }
        await chatList.loadMoreChats(for: .main)
    }

    private func syncProfile(from user: UserSummary) {
        profile.userId = user.id
        profile.displayName = user.displayName
        profile.username = user.username
        profile.phoneNumber = user.phoneNumber
        profile.accentColorId = Int(abs(user.id) % 7)
    }

    private func finishRemoval() {
        guard !hasNotifiedRemoval else { return }
        hasNotifiedRemoval = true
        updatesTask?.cancel()
        updatesTask = nil
        service.finishUpdates()
        pendingChatInvite = nil
        chatList.reset()
        conversation.reset()
        fileCache.reset()
        onClosedForRemoval?(self, shouldDeleteStorageOnClose)
    }

    private func performAuthAction(_ action: @escaping () async throws -> Void) async {
        authErrorMessage = nil
        isSubmittingAuth = true
        defer { isSubmittingAuth = false }

        do {
            try await action()
        } catch {
            authErrorMessage = TDLibErrorHelper.userFacingMessage(for: error)
        }
    }
}
