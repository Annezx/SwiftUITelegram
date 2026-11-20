import Foundation
import Observation
import TDLibKit

/// Root application store that coordinates TDLib lifecycle, authentication flow,
/// connection state, and dispatches updates to child stores on the main actor.
@MainActor
@Observable
final class AppStore {
    let service: TDLibService
    let fileCache: FileCacheStore
    let chatList: ChatListStore
    let conversation: ConversationStore

    private var updatesTask: Task<Void, Never>?
    private var hasBootstrapped = false
    private var awaitingTdlibParameters = false

    private(set) var authStep: AuthStep = .configuring
    private(set) var connectionStatus: ConnectionStatus = .connecting
    private(set) var currentUser: UserSummary?
    private(set) var credentials: TelegramAPICredentials?
    private(set) var isSubmittingAuth: Bool = false

    var authErrorMessage: String?
    var searchFocusTrigger: Int = 0

    init(service: TDLibService = TDLibService()) {
        self.service = service
        self.fileCache = FileCacheStore(service: service)
        self.chatList = ChatListStore(service: service)
        self.conversation = ConversationStore(service: service)
    }

    func bootstrap() {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        credentials = AppConfiguration.loadCredentials()
        startUpdateLoop()
        service.startClient()
    }

    func shutdown() {
        updatesTask?.cancel()
        updatesTask = nil
        service.closeAllClients()
    }

    // MARK: - API Credentials

    func submitCredentials(apiIdText: String, apiHash: String) async {
        authErrorMessage = nil
        let cleanId = apiIdText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanHash = apiHash.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let apiId = Int(cleanId), apiId > 0, !cleanHash.isEmpty else {
            authErrorMessage = "请输入有效的 API ID（纯数字）和 API Hash。"
            return
        }

        let newCredentials = TelegramAPICredentials(apiId: apiId, apiHash: cleanHash)
        AppConfiguration.saveUserCredentials(newCredentials)
        credentials = newCredentials

        if awaitingTdlibParameters {
            await applyTdlibParameters(newCredentials)
        }
    }

    func clearSavedCredentials() {
        AppConfiguration.clearUserCredentials()
        credentials = AppConfiguration.loadCredentials()
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

    func requestQRCodeLogin() async {
        await performAuthAction {
            try await self.service.requestQrCodeAuthentication()
        }
    }

    func switchBackToPhoneLogin() async {
        // Per TDLib spec, setAuthenticationPhoneNumber cannot be called directly from
        // authorizationStateWaitOtherDeviceConfirmation; logging out cleanly resets the session.
        await logOut()
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

    func logOut() async {
        await performAuthAction {
            try await self.service.logOut()
        }
    }

    func triggerSearchFocus() {
        searchFocusTrigger += 1
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
            if let credentials, credentials.isValid {
                authStep = .configuring
                await applyTdlibParameters(credentials)
            } else {
                authStep = .needsCredentials
            }

        case .authorizationStateReady:
            awaitingTdlibParameters = false
            authStep = .ready
            await onAuthorized()

        case .authorizationStateClosed:
            awaitingTdlibParameters = false
            currentUser = nil
            chatList.reset()
            conversation.reset()
            fileCache.reset()
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

    private func onAuthorized() async {
        if let me = try? await service.getMe() {
            currentUser = UserSummary(tdUser: me)
        }
        await chatList.loadMoreChats(for: .main)
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
