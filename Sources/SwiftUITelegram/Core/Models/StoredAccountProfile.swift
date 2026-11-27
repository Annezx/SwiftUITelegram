import Foundation

/// Persisted lightweight metadata for a Telegram account slot on this device.
/// Actual session credentials and SQLite caches remain managed by TDLib inside
/// each slot's isolated `db` and `files` directories.
struct StoredAccountProfile: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let storageKey: String
    var userId: Int64?
    var displayName: String
    var username: String?
    var phoneNumber: String
    var accentColorId: Int
    let createdAt: Foundation.Date

    init(
        id: UUID = UUID(),
        storageKey: String,
        userId: Int64? = nil,
        displayName: String = "",
        username: String? = nil,
        phoneNumber: String = "",
        accentColorId: Int = 0,
        createdAt: Foundation.Date = Foundation.Date()
    ) {
        self.id = id
        self.storageKey = storageKey
        self.userId = userId
        self.displayName = displayName
        self.username = username
        self.phoneNumber = phoneNumber
        self.accentColorId = accentColorId
        self.createdAt = createdAt
    }

    var fallbackDisplayName: String {
        if !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displayName
        }
        if !phoneNumber.isEmpty {
            return "+\(phoneNumber)"
        }
        return "新账号"
    }
}

struct StoredAccountsSnapshot: Codable, Equatable, Sendable {
    var accounts: [StoredAccountProfile]
    var activeAccountId: UUID?
}

/// Persists the list of configured Telegram account slots and active selection to `accounts.json`,
/// while seamlessly migrating any existing legacy single-account session (`tdlib/db`) to slot `"default"`.
enum AccountRegistry {
    static func load() -> StoredAccountsSnapshot {
        let url = AppConfiguration.accountsRegistryURL
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(StoredAccountsSnapshot.self, from: data),
           !decoded.accounts.isEmpty
        {
            return decoded
        }

        // First launch or seamless upgrade from legacy single-account storage.
        let defaultProfile = StoredAccountProfile(
            storageKey: AppConfiguration.defaultAccountStorageKey
        )
        let snapshot = StoredAccountsSnapshot(
            accounts: [defaultProfile],
            activeAccountId: defaultProfile.id
        )
        save(snapshot)
        return snapshot
    }

    static func save(_ snapshot: StoredAccountsSnapshot) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: AppConfiguration.accountsRegistryURL, options: .atomic)
    }
}
