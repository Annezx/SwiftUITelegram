import Darwin
import Foundation

struct TelegramAPICredentials: Equatable, Sendable {
    let apiId: Int
    let apiHash: String

    var isValid: Bool {
        apiId > 0 && !apiHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum AppConfiguration {
    private static let apiIdDefaultsKey = "swiftuitelegram.api_id"
    private static let apiHashDefaultsKey = "swiftuitelegram.api_hash"

    /// Loads Telegram API credentials in priority order:
    /// 1. Process environment variables (`TELEGRAM_API_ID`, `TELEGRAM_API_HASH`)
    /// 2. Bundle `Info.plist` (populated from `Config/Secrets.xcconfig`)
    /// 3. Local `UserDefaults` (entered via the in-app setup view)
    static func loadCredentials() -> TelegramAPICredentials? {
        if let env = credentialsFromEnvironment() {
            return env
        }
        if let plist = credentialsFromInfoPlist() {
            return plist
        }
        return credentialsFromUserDefaults()
    }

    static func saveUserCredentials(_ credentials: TelegramAPICredentials) {
        let defaults = UserDefaults.standard
        defaults.set(credentials.apiId, forKey: apiIdDefaultsKey)
        defaults.set(credentials.apiHash.trimmingCharacters(in: .whitespacesAndNewlines), forKey: apiHashDefaultsKey)
    }

    static func clearUserCredentials() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: apiIdDefaultsKey)
        defaults.removeObject(forKey: apiHashDefaultsKey)
    }

    static var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("SwiftUITelegram", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static let defaultAccountStorageKey = "default"

    static var accountsRegistryURL: URL {
        appSupportDirectory.appendingPathComponent("accounts.json", isDirectory: false)
    }

    static var tdlibDatabaseDirectory: String {
        tdlibDatabaseDirectory(for: defaultAccountStorageKey)
    }

    static var tdlibFilesDirectory: String {
        tdlibFilesDirectory(for: defaultAccountStorageKey)
    }

    static func tdlibDatabaseDirectory(for storageKey: String) -> String {
        let dir: URL
        if storageKey == defaultAccountStorageKey {
            dir = appSupportDirectory.appendingPathComponent("tdlib/db", isDirectory: true)
        } else {
            dir = appSupportDirectory.appendingPathComponent("tdlib/accounts/\(storageKey)/db", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    static func tdlibFilesDirectory(for storageKey: String) -> String {
        let dir: URL
        if storageKey == defaultAccountStorageKey {
            dir = appSupportDirectory.appendingPathComponent("tdlib/files", isDirectory: true)
        } else {
            dir = appSupportDirectory.appendingPathComponent("tdlib/accounts/\(storageKey)/files", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    static func removeAccountStorage(for storageKey: String) {
        let fm = FileManager.default
        if storageKey == defaultAccountStorageKey {
            let dbDir = appSupportDirectory.appendingPathComponent("tdlib/db", isDirectory: true)
            let filesDir = appSupportDirectory.appendingPathComponent("tdlib/files", isDirectory: true)
            try? fm.removeItem(at: dbDir)
            try? fm.removeItem(at: filesDir)
        } else {
            let rootDir = appSupportDirectory.appendingPathComponent("tdlib/accounts/\(storageKey)", isDirectory: true)
            try? fm.removeItem(at: rootDir)
        }
    }

    static var mediaCacheDirectory: URL {
        let dir = appSupportDirectory.appendingPathComponent("media-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var outgoingStagingDirectory: URL {
        let dir = mediaCacheDirectory.appendingPathComponent("outgoing", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var quickLookStagingDirectory: URL {
        let dir = mediaCacheDirectory.appendingPathComponent("quicklook", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var audioTranscodeCacheDirectory: URL {
        let dir = mediaCacheDirectory.appendingPathComponent("audio-caf", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func clearMediaCache() {
        let fm = FileManager.default
        try? fm.removeItem(at: mediaCacheDirectory)
        _ = mediaCacheDirectory
    }

    static func pruneStaleOutgoingStaging(olderThan interval: TimeInterval = 24 * 60 * 60) {
        let fm = FileManager.default
        let cutoff = Foundation.Date().addingTimeInterval(-interval)
        guard let items = try? fm.contentsOfDirectory(
            at: outgoingStagingDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for url in items {
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if modDate < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }

    static var applicationVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "1.4.0"
    }

    static var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    static var systemLanguageCode: String {
        Locale.preferredLanguages.first?.components(separatedBy: "-").first ?? "en"
    }

    static var deviceModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let str = String(cString: model)
        return str.isEmpty ? "Mac" : str
    }

    // MARK: - Private

    private static func credentialsFromEnvironment() -> TelegramAPICredentials? {
        let env = ProcessInfo.processInfo.environment
        guard
            let idStr = env["TELEGRAM_API_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            let apiId = Int(idStr),
            let hash = env["TELEGRAM_API_HASH"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return nil
        }
        let creds = TelegramAPICredentials(apiId: apiId, apiHash: hash)
        return creds.isValid ? creds : nil
    }

    private static func credentialsFromInfoPlist() -> TelegramAPICredentials? {
        guard
            let rawId = Bundle.main.object(forInfoDictionaryKey: "TELEGRAM_API_ID") as? String,
            let rawHash = Bundle.main.object(forInfoDictionaryKey: "TELEGRAM_API_HASH") as? String
        else {
            return nil
        }
        let cleanId = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanHash = rawHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.hasPrefix("$("), !cleanHash.hasPrefix("$("), let apiId = Int(cleanId) else {
            return nil
        }
        let creds = TelegramAPICredentials(apiId: apiId, apiHash: cleanHash)
        return creds.isValid ? creds : nil
    }

    private static func credentialsFromUserDefaults() -> TelegramAPICredentials? {
        let defaults = UserDefaults.standard
        let apiId = defaults.integer(forKey: apiIdDefaultsKey)
        guard let hash = defaults.string(forKey: apiHashDefaultsKey) else {
            return nil
        }
        let creds = TelegramAPICredentials(apiId: apiId, apiHash: hash)
        return creds.isValid ? creds : nil
    }
}
