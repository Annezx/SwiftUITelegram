import Foundation
import Observation

/// Root application store that coordinates multiple concurrent Telegram `AccountSession`s,
/// shared API credentials, account switching/addition/logout, and global audio playback.
@MainActor
@Observable
final class AppStore {
    let hub: TDLibClientHub
    let audioPlayer: AudioPlaybackManager

    private var hasBootstrapped = false
    private var closingSessions: [UUID: AccountSession] = [:]
    private var previousActiveAccountIdBeforeAdd: UUID?

    private(set) var accounts: [AccountSession] = []
    private(set) var activeAccountId: UUID
    private(set) var credentials: TelegramAPICredentials?

    var noticeMessage: String?
    var searchFocusTrigger: Int = 0
    var createFolderTrigger: Int = 0
    var manageFoldersTrigger: Int = 0

    init(hub: TDLibClientHub = TDLibClientHub()) {
        self.hub = hub
        self.audioPlayer = AudioPlaybackManager()

        let snapshot = AccountRegistry.load()
        var loadedSessions: [AccountSession] = []
        for profile in snapshot.accounts {
            let session = AccountSession(profile: profile, hub: hub, isTemporaryAddFlow: false)
            loadedSessions.append(session)
        }

        if loadedSessions.isEmpty {
            let fallback = StoredAccountProfile(storageKey: AppConfiguration.defaultAccountStorageKey)
            loadedSessions.append(AccountSession(profile: fallback, hub: hub, isTemporaryAddFlow: false))
        }

        self.accounts = loadedSessions
        if let savedActiveId = snapshot.activeAccountId,
           loadedSessions.contains(where: { $0.id == savedActiveId })
        {
            self.activeAccountId = savedActiveId
        } else {
            self.activeAccountId = loadedSessions[0].id
        }

        for session in loadedSessions {
            wireCallbacks(for: session)
        }
    }

    // MARK: - Active Account Forwarding

    var activeAccount: AccountSession {
        if let match = accounts.first(where: { $0.id == activeAccountId }) {
            return match
        }
        return accounts[0]
    }

    var service: TDLibService { activeAccount.service }
    var fileCache: FileCacheStore { activeAccount.fileCache }
    var chatList: ChatListStore { activeAccount.chatList }
    var conversation: ConversationStore { activeAccount.conversation }
    var stickers: StickerStore { activeAccount.stickers }

    var authStep: AuthStep { activeAccount.authStep }
    var connectionStatus: ConnectionStatus { activeAccount.connectionStatus }
    var currentUser: UserSummary? { activeAccount.currentUser }
    var isSubmittingAuth: Bool { activeAccount.isSubmittingAuth }

    var authErrorMessage: String? {
        get { activeAccount.authErrorMessage }
        set { activeAccount.authErrorMessage = newValue }
    }

    var pendingChatInvite: PendingChatInvitePreview? {
        get { activeAccount.pendingChatInvite }
        set { activeAccount.pendingChatInvite = newValue }
    }

    // MARK: - Multi-Account Queries

    var readyAccounts: [AccountSession] {
        accounts.filter { $0.isReady }
    }

    /// Accounts displayed in the switcher and Settings (excludes unfinished temporary add-account slots).
    var persistedAccounts: [AccountSession] {
        accounts.filter { !$0.isTemporaryAddFlow }
    }

    var hasOtherReadyAccounts: Bool {
        accounts.contains { $0.id != activeAccountId && $0.isReady }
    }

    var otherAccountsUnreadCount: Int {
        accounts.reduce(0) { sum, session in
            guard session.id != activeAccountId, session.isReady else { return sum }
            return sum + session.unreadMessageCount
        }
    }

    func otherReadyUserIds(excluding accountId: UUID) -> [Int64] {
        accounts.compactMap { session in
            guard session.id != accountId, session.isReady else { return nil }
            return session.currentUser?.id ?? session.profile.userId
        }
    }

    // MARK: - App Lifecycle

    func bootstrap() {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        AppConfiguration.pruneStaleOutgoingStaging()
        credentials = AppConfiguration.loadCredentials()

        for session in accounts {
            session.start()
        }
    }

    func shutdown() {
        audioPlayer.stop()
        for session in accounts {
            session.stopForAppShutdown()
        }
        for session in closingSessions.values {
            session.stopForAppShutdown()
        }
        hub.closeAllClients()
    }

    // MARK: - Multi-Account Management

    func switchAccount(to targetId: UUID) {
        guard targetId != activeAccountId,
              accounts.contains(where: { $0.id == targetId })
        else {
            return
        }

        audioPlayer.stop()
        noticeMessage = nil

        let previous = activeAccount
        activeAccountId = targetId
        previousActiveAccountIdBeforeAdd = nil

        // Clean up an abandoned temporary "Add Account" flow when switching away.
        if previous.isTemporaryAddFlow && !previous.isReady {
            detachAndClose(previous, logOutFirst: false, deleteStorage: true)
        }

        persistRegistry()
    }

    func beginAddingAccount() {
        noticeMessage = nil

        // Reuse an already-open temporary login slot if present.
        if let existingTemp = accounts.first(where: { $0.isTemporaryAddFlow && !$0.isReady }) {
            activeAccountId = existingTemp.id
            return
        }

        audioPlayer.stop()
        previousActiveAccountIdBeforeAdd = activeAccountId

        let newProfile = StoredAccountProfile(
            storageKey: UUID().uuidString.lowercased()
        )
        let newSession = AccountSession(
            profile: newProfile,
            hub: hub,
            isTemporaryAddFlow: true
        )
        wireCallbacks(for: newSession)
        accounts.append(newSession)
        activeAccountId = newSession.id

        if hasBootstrapped {
            newSession.start()
        }
    }

    func cancelAddingAccount() {
        let current = activeAccount
        guard current.isTemporaryAddFlow, accounts.count > 1 else { return }

        let fallbackId = preferredFallbackAccountId(excluding: current.id)
        activeAccountId = fallbackId
        previousActiveAccountIdBeforeAdd = nil
        noticeMessage = nil

        detachAndClose(current, logOutFirst: false, deleteStorage: true)
        persistRegistry()
    }

    func logOut(accountId: UUID? = nil) async {
        let targetId = accountId ?? activeAccountId
        guard let target = accounts.first(where: { $0.id == targetId }) else { return }

        if target.id == activeAccountId {
            audioPlayer.stop()
        }

        if accounts.count > 1 {
            if target.id == activeAccountId {
                activeAccountId = preferredFallbackAccountId(excluding: target.id)
            }
            detachAndClose(target, logOutFirst: target.isReady, deleteStorage: true)
            persistRegistry()
        } else {
            await target.logOutInPlace()
        }
    }

    func removeAccount(accountId: UUID) {
        guard accounts.count > 1,
              let target = accounts.first(where: { $0.id == accountId })
        else {
            return
        }

        if target.id == activeAccountId {
            audioPlayer.stop()
            activeAccountId = preferredFallbackAccountId(excluding: target.id)
        }

        detachAndClose(target, logOutFirst: target.isReady, deleteStorage: true)
        persistRegistry()
    }

    // MARK: - API Credentials

    func submitCredentials(apiIdText: String, apiHash: String) async {
        activeAccount.authErrorMessage = nil
        let cleanId = apiIdText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanHash = apiHash.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let apiId = Int(cleanId), apiId > 0, !cleanHash.isEmpty else {
            activeAccount.authErrorMessage = "请输入有效的 API ID（纯数字）和 API Hash。"
            return
        }

        let newCredentials = TelegramAPICredentials(apiId: apiId, apiHash: cleanHash)
        AppConfiguration.saveUserCredentials(newCredentials)
        credentials = newCredentials

        for session in accounts {
            await session.applyCredentialsIfAwaiting(newCredentials)
        }
    }

    func clearSavedCredentials() {
        AppConfiguration.clearUserCredentials()
        credentials = AppConfiguration.loadCredentials()
    }

    // MARK: - Active Account Auth Actions

    func submitPhoneNumber(_ phoneNumber: String) async {
        await activeAccount.submitPhoneNumber(phoneNumber)
    }

    func requestQRCodeLogin() async {
        let others = otherReadyUserIds(excluding: activeAccount.id)
        await activeAccount.requestQRCodeLogin(otherUserIds: others)
    }

    func switchBackToPhoneLogin() async {
        await activeAccount.switchBackToPhoneLogin()
    }

    func submitAuthCode(_ code: String) async {
        await activeAccount.submitAuthCode(code)
    }

    func submitPassword(_ password: String) async {
        await activeAccount.submitPassword(password)
    }

    func submitRegistration(firstName: String, lastName: String) async {
        await activeAccount.submitRegistration(firstName: firstName, lastName: lastName)
    }

    func triggerSearchFocus() {
        searchFocusTrigger += 1
    }

    func triggerCreateFolder() {
        createFolderTrigger += 1
    }

    func triggerManageFolders() {
        manageFoldersTrigger += 1
    }

    // MARK: - In-App Telegram Links

    func openTelegramURL(_ url: URL) async {
        await activeAccount.openTelegramURL(url)
    }

    func confirmJoinPendingInvite() async -> String? {
        await activeAccount.confirmJoinPendingInvite()
    }

    // MARK: - Private Session Coordination

    private func wireCallbacks(for session: AccountSession) {
        session.credentialsProvider = { [weak self] in
            self?.credentials
        }

        session.onAuthorized = { [weak self] authorizedSession, user in
            await self?.handleSessionAuthorized(authorizedSession, user: user)
        }

        session.onProfileUpdated = { [weak self] _ in
            self?.persistRegistry()
        }

        session.onClosedForRemoval = { [weak self] closedSession, deleteStorage in
            self?.handleSessionClosedForRemoval(closedSession, deleteStorage: deleteStorage)
        }

        session.onSearchRequested = { [weak self, weak session] in
            guard let self, let session, session.id == self.activeAccountId else { return }
            self.triggerSearchFocus()
        }

        session.onLinkNotice = { [weak self, weak session] message in
            guard let self, let session, session.id == self.activeAccountId else { return }
            self.noticeMessage = message
        }
    }

    private func handleSessionAuthorized(_ session: AccountSession, user: UserSummary) async {
        // Detect duplicate login of an account that already exists under another slot.
        if let existing = accounts.first(where: { candidate in
            candidate.id != session.id
                && (candidate.currentUser?.id == user.id || candidate.profile.userId == user.id)
        }) {
            if existing.isReady {
                activeAccountId = existing.id
                previousActiveAccountIdBeforeAdd = nil
                detachAndClose(session, logOutFirst: true, deleteStorage: true)
                persistRegistry()
                noticeMessage = "账号「\(user.displayName)」已在列表中登录，已自动切换到该账号。"
                return
            } else {
                // Existing slot was logged out / expired; replace it with the newly authorized session.
                detachAndClose(existing, logOutFirst: false, deleteStorage: true)
            }
        }

        session.isTemporaryAddFlow = false
        previousActiveAccountIdBeforeAdd = nil
        persistRegistry()
    }

    private func detachAndClose(_ session: AccountSession, logOutFirst: Bool, deleteStorage: Bool) {
        accounts.removeAll { $0.id == session.id }
        closingSessions[session.id] = session
        session.closeForRemoval(logOutFirst: logOutFirst, deleteStorage: deleteStorage)
    }

    private func handleSessionClosedForRemoval(_ session: AccountSession, deleteStorage: Bool) {
        closingSessions.removeValue(forKey: session.id)
        if deleteStorage {
            AppConfiguration.removeAccountStorage(for: session.storageKey)
        }
    }

    private func preferredFallbackAccountId(excluding excludedId: UUID) -> UUID {
        if let prev = previousActiveAccountIdBeforeAdd,
           prev != excludedId,
           accounts.contains(where: { $0.id == prev })
        {
            return prev
        }
        if let ready = accounts.first(where: { $0.id != excludedId && $0.isReady }) {
            return ready.id
        }
        if let any = accounts.first(where: { $0.id != excludedId }) {
            return any.id
        }
        return excludedId
    }

    private func persistRegistry() {
        let toSave = accounts.filter { !$0.isTemporaryAddFlow || accounts.count == 1 }
        let profiles = toSave.map(\.profile)
        let savedActiveId = profiles.contains(where: { $0.id == activeAccountId })
            ? activeAccountId
            : profiles.first?.id

        AccountRegistry.save(
            StoredAccountsSnapshot(
                accounts: profiles,
                activeAccountId: savedActiveId
            )
        )
    }
}
