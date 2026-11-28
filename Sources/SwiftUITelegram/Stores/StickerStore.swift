import Foundation
import Observation
import TDLibKit

/// Per-account reactive store managing Telegram sticker packs, favorite & recent stickers,
/// trending discovery, sticker/emoji search, and persisted recent emojis.
@MainActor
@Observable
final class StickerStore {
    private let service: TDLibService
    private let recentEmojisDefaultsKey: String

    private var hasLoadedInitial = false
    private var hasLoadedTrending = false
    private var inFlightSetLoads: Set<Int64> = []
    private var stickerSearchTask: Task<Void, Never>?
    private var emojiSearchTask: Task<Void, Never>?
    private var quickSuggestionTask: Task<Void, Never>?

    private(set) var favoriteStickers: [StickerItem] = []
    private(set) var recentStickers: [StickerItem] = []
    private(set) var installedSets: [StickerPackSummary] = []
    private(set) var trendingSets: [StickerPackSummary] = []
    private(set) var loadedSetDetails: [Int64: StickerPackDetail] = [:]
    private(set) var loadingSetIds: Set<Int64> = []
    private(set) var mutatingSetIds: Set<Int64> = []

    private(set) var isLoadingInitial: Bool = false
    private(set) var isLoadingTrending: Bool = false
    private(set) var isSearchingStickers: Bool = false
    private(set) var searchedStickers: [StickerItem] = []
    private(set) var searchedSets: [StickerPackSummary] = []
    private(set) var activeStickerSearchQuery: String = ""

    private(set) var recentEmojis: [String] = []
    private(set) var searchedEmojis: [EmojiEntry] = []
    private(set) var isSearchingEmojis: Bool = false
    private(set) var activeEmojiSearchQuery: String = ""

    private(set) var quickSuggestedStickers: [StickerItem] = []
    private(set) var quickSuggestionEmoji: String = ""

    var errorMessage: String?

    init(service: TDLibService, storageKey: String = AppConfiguration.defaultAccountStorageKey) {
        self.service = service
        self.recentEmojisDefaultsKey = "swiftuitelegram.recent_emojis.\(storageKey)"
        self.recentEmojis = UserDefaults.standard.stringArray(forKey: recentEmojisDefaultsKey) ?? []
    }

    // MARK: - Queries

    private var favoriteFileIds: Set<Int> {
        Set(favoriteStickers.map(\.file.fileId))
    }

    private var favoriteRemoteUniqueIds: Set<String> {
        Set(favoriteStickers.map(\.remoteUniqueId).filter { !$0.isEmpty })
    }

    func isFavorite(_ sticker: StickerItem) -> Bool {
        if favoriteFileIds.contains(sticker.file.fileId) {
            return true
        }
        if !sticker.remoteUniqueId.isEmpty && favoriteRemoteUniqueIds.contains(sticker.remoteUniqueId) {
            return true
        }
        return false
    }

    func isFavorite(_ media: StickerMedia) -> Bool {
        favoriteFileIds.contains(media.file.fileId)
    }

    func isSetInstalled(_ setId: Int64) -> Bool {
        if installedSets.contains(where: { $0.id == setId }) {
            return true
        }
        return loadedSetDetails[setId]?.isInstalled == true
    }

    // MARK: - Initial & On-Demand Loading

    func ensureInitialLoaded() async {
        guard !hasLoadedInitial, !isLoadingInitial else { return }
        isLoadingInitial = true
        defer { isLoadingInitial = false }

        async let favTask = fetchFavoritesSilently()
        async let recentTask = fetchRecentsSilently()
        async let installedTask = fetchInstalledSetsSilently()

        let (favs, recents, sets) = await (favTask, recentTask, installedTask)
        favoriteStickers = favs
        recentStickers = recents
        installedSets = sets
        hasLoadedInitial = true

        // Preload the first installed set so the stickers view populates immediately.
        if let firstSet = sets.first {
            await loadStickerSet(id: firstSet.id)
        }
    }

    func refreshAll() async {
        hasLoadedInitial = false
        await ensureInitialLoaded()
    }

    func ensureTrendingLoaded() async {
        guard !hasLoadedTrending, !isLoadingTrending else { return }
        isLoadingTrending = true
        defer { isLoadingTrending = false }

        do {
            let tdSets = try await service.getTrendingStickerSets(offset: 0, limit: 24, stickerType: .stickerTypeRegular)
            trendingSets = tdSets.map(StickerPackSummary.init(tdInfo:))
            hasLoadedTrending = true
        } catch {
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
        }
    }

    @discardableResult
    func loadStickerSet(id setId: Int64, forceRefresh: Bool = false) async -> StickerPackDetail? {
        guard setId != 0 else { return nil }
        if !forceRefresh, let cached = loadedSetDetails[setId] {
            return cached
        }
        guard !inFlightSetLoads.contains(setId) else {
            return loadedSetDetails[setId]
        }

        inFlightSetLoads.insert(setId)
        loadingSetIds.insert(setId)
        defer {
            inFlightSetLoads.remove(setId)
            loadingSetIds.remove(setId)
        }

        do {
            let tdSet = try await service.getStickerSet(setId: setId)
            let detail = StickerPackDetail(tdSet: tdSet)
            loadedSetDetails[setId] = detail
            syncPackInstallationState(setId: setId, isInstalled: detail.isInstalled, detail: detail)
            return detail
        } catch {
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
            return loadedSetDetails[setId]
        }
    }

    // MARK: - Favorites, Recents & Pack Installation

    func toggleFavorite(_ sticker: StickerItem) async -> Bool {
        await toggleFavorite(fileId: sticker.file.fileId, remoteFileId: sticker.remoteFileId)
    }

    func toggleFavorite(fileId: Int, remoteFileId: String = "") async -> Bool {
        let currentlyFavorite = favoriteFileIds.contains(fileId)
        errorMessage = nil
        do {
            if currentlyFavorite {
                try await service.removeFavoriteSticker(fileId: fileId, remoteFileId: remoteFileId)
            } else {
                try await service.addFavoriteSticker(fileId: fileId, remoteFileId: remoteFileId)
            }
            favoriteStickers = await fetchFavoritesSilently()
            return !currentlyFavorite
        } catch {
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
            return currentlyFavorite
        }
    }

    func removeRecent(_ sticker: StickerItem) async {
        errorMessage = nil
        do {
            try await service.removeRecentSticker(
                fileId: sticker.file.fileId,
                remoteFileId: sticker.remoteFileId,
                isAttached: false
            )
            recentStickers.removeAll { $0.file.fileId == sticker.file.fileId }
        } catch {
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
        }
    }

    @discardableResult
    func setStickerSetInstalled(setId: Int64, installed: Bool) async -> Bool {
        guard setId != 0, !mutatingSetIds.contains(setId) else { return false }
        mutatingSetIds.insert(setId)
        defer { mutatingSetIds.remove(setId) }
        errorMessage = nil

        do {
            try await service.changeStickerSet(setId: setId, isInstalled: installed, isArchived: false)
            syncPackInstallationState(setId: setId, isInstalled: installed, detail: loadedSetDetails[setId])
            installedSets = await fetchInstalledSetsSilently()
            return true
        } catch {
            errorMessage = TDLibErrorHelper.userFacingMessage(for: error)
            return false
        }
    }

    // MARK: - Sticker Search

    func updateStickerSearch(query: String, chatId: Int64?) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        activeStickerSearchQuery = trimmed
        stickerSearchTask?.cancel()

        guard !trimmed.isEmpty else {
            searchedStickers = []
            searchedSets = []
            isSearchingStickers = false
            return
        }

        isSearchingStickers = true
        let languageCodes = Self.preferredLanguageCodes

        stickerSearchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard let self, !Task.isCancelled, self.activeStickerSearchQuery == trimmed else { return }

            let isEmojiInput = EmojiCatalog.isSingleEmojiQuery(trimmed)

            async let installedMatches: [Sticker] = {
                (try? await self.service.getStickers(
                    chatId: chatId ?? 0,
                    query: trimmed,
                    limit: 36,
                    stickerType: .stickerTypeRegular
                )) ?? []
            }()

            async let publicMatches: [Sticker] = {
                (try? await self.service.searchStickers(
                    emojis: isEmojiInput ? trimmed : "",
                    query: isEmojiInput ? "" : trimmed,
                    inputLanguageCodes: languageCodes,
                    offset: 0,
                    limit: 36,
                    stickerType: .stickerTypeRegular
                )) ?? []
            }()

            async let matchingSets: [StickerSetInfo] = {
                guard !isEmojiInput else { return [] }
                return (try? await self.service.searchStickerSets(
                    query: trimmed,
                    stickerType: .stickerTypeRegular
                )) ?? []
            }()

            let (installed, publicStickers, sets) = await (installedMatches, publicMatches, matchingSets)
            guard !Task.isCancelled, self.activeStickerSearchQuery == trimmed else { return }

            let merged = Self.deduplicateStickers(
                installed.map(StickerItem.init(tdSticker:)) + publicStickers.map(StickerItem.init(tdSticker:))
            )

            self.searchedStickers = merged
            self.searchedSets = sets.map(StickerPackSummary.init(tdInfo:))
            self.isSearchingStickers = false
        }
    }

    // MARK: - Quick Inline Emoji-to-Sticker Suggestions

    func updateQuickSuggestions(forDraftText text: String, chatId: Int64?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard EmojiCatalog.isSingleEmojiQuery(trimmed) else {
            clearQuickSuggestions()
            return
        }

        guard trimmed != quickSuggestionEmoji else { return }
        quickSuggestionEmoji = trimmed
        quickSuggestionTask?.cancel()

        quickSuggestionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard let self, !Task.isCancelled, self.quickSuggestionEmoji == trimmed else { return }

            let tdStickers = (try? await self.service.getStickers(
                chatId: chatId ?? 0,
                query: trimmed,
                limit: 16,
                stickerType: .stickerTypeRegular
            )) ?? []

            guard !Task.isCancelled, self.quickSuggestionEmoji == trimmed else { return }
            self.quickSuggestedStickers = Self.deduplicateStickers(tdStickers.map(StickerItem.init(tdSticker:)))
        }
    }

    func clearQuickSuggestions() {
        quickSuggestionTask?.cancel()
        quickSuggestionTask = nil
        quickSuggestionEmoji = ""
        if !quickSuggestedStickers.isEmpty {
            quickSuggestedStickers = []
        }
    }

    // MARK: - Emoji Recents & Search

    func recordRecentEmoji(_ emoji: String) {
        let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = recentEmojis.filter { $0 != trimmed }
        updated.insert(trimmed, at: 0)
        if updated.count > 32 {
            updated = Array(updated.prefix(32))
        }
        recentEmojis = updated
        UserDefaults.standard.set(updated, forKey: recentEmojisDefaultsKey)
    }

    func updateEmojiSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        activeEmojiSearchQuery = trimmed
        emojiSearchTask?.cancel()

        guard !trimmed.isEmpty else {
            searchedEmojis = []
            isSearchingEmojis = false
            return
        }

        // Apply instant local bilingual matches first so UI responds on the very first keystroke.
        let localMatches = EmojiCatalog.searchLocal(query: trimmed)
        searchedEmojis = localMatches
        isSearchingEmojis = true

        let languageCodes = Self.preferredLanguageCodes

        emojiSearchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard let self, !Task.isCancelled, self.activeEmojiSearchQuery == trimmed else { return }

            let remoteKeywords = (try? await self.service.searchEmojis(
                text: trimmed,
                inputLanguageCodes: languageCodes
            )) ?? []

            guard !Task.isCancelled, self.activeEmojiSearchQuery == trimmed else { return }

            var merged = localMatches
            var seen = Set(localMatches.map(\.symbol))
            for item in remoteKeywords {
                let symbol = item.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !symbol.isEmpty, seen.insert(symbol).inserted else { continue }
                if let known = EmojiCatalog.entryBySymbol[symbol] {
                    merged.append(known)
                } else {
                    merged.append(EmojiEntry(symbol, item.keyword, item.keyword))
                }
            }

            self.searchedEmojis = merged
            self.isSearchingEmojis = false
        }
    }

    // MARK: - TDLib Live Updates

    func handleUpdate(_ update: Update) {
        switch update {
        case .updateInstalledStickerSets(let info):
            if case .stickerTypeRegular = info.stickerType {
                Task { [weak self] in
                    guard let self else { return }
                    self.installedSets = await self.fetchInstalledSetsSilently()
                }
            }

        case .updateRecentStickers(let info):
            if !info.isAttached {
                Task { [weak self] in
                    guard let self else { return }
                    self.recentStickers = await self.fetchRecentsSilently()
                }
            }

        case .updateFavoriteStickers:
            Task { [weak self] in
                guard let self else { return }
                self.favoriteStickers = await self.fetchFavoritesSilently()
            }

        case .updateTrendingStickerSets(let info):
            if case .stickerTypeRegular = info.stickerType {
                trendingSets = info.stickerSets.sets.map(StickerPackSummary.init(tdInfo:))
                hasLoadedTrending = true
            }

        case .updateStickerSet(let info):
            if case .stickerTypeRegular = info.stickerSet.stickerType {
                let detail = StickerPackDetail(tdSet: info.stickerSet)
                loadedSetDetails[detail.id] = detail
                syncPackInstallationState(setId: detail.id, isInstalled: detail.isInstalled, detail: detail)
            }

        default:
            break
        }
    }

    func reset() {
        stickerSearchTask?.cancel()
        emojiSearchTask?.cancel()
        quickSuggestionTask?.cancel()
        hasLoadedInitial = false
        hasLoadedTrending = false
        inFlightSetLoads.removeAll()
        loadingSetIds.removeAll()
        mutatingSetIds.removeAll()
        favoriteStickers = []
        recentStickers = []
        installedSets = []
        trendingSets = []
        loadedSetDetails = [:]
        searchedStickers = []
        searchedSets = []
        activeStickerSearchQuery = ""
        searchedEmojis = []
        activeEmojiSearchQuery = ""
        quickSuggestedStickers = []
        quickSuggestionEmoji = ""
        isLoadingInitial = false
        isLoadingTrending = false
        isSearchingStickers = false
        isSearchingEmojis = false
        errorMessage = nil
    }

    // MARK: - Private Helpers

    private func fetchFavoritesSilently() async -> [StickerItem] {
        guard let tdStickers = try? await service.getFavoriteStickers() else {
            return favoriteStickers
        }
        return tdStickers.map(StickerItem.init(tdSticker:))
    }

    private func fetchRecentsSilently() async -> [StickerItem] {
        guard let tdStickers = try? await service.getRecentStickers(isAttached: false) else {
            return recentStickers
        }
        return tdStickers.map(StickerItem.init(tdSticker:))
    }

    private func fetchInstalledSetsSilently() async -> [StickerPackSummary] {
        guard let tdSets = try? await service.getInstalledStickerSets(stickerType: .stickerTypeRegular) else {
            return installedSets
        }
        return tdSets.map(StickerPackSummary.init(tdInfo:))
    }

    private func syncPackInstallationState(setId: Int64, isInstalled: Bool, detail: StickerPackDetail?) {
        if var existingDetail = loadedSetDetails[setId] {
            existingDetail.isInstalled = isInstalled
            loadedSetDetails[setId] = existingDetail
        }
        if let idx = trendingSets.firstIndex(where: { $0.id == setId }) {
            trendingSets[idx].isInstalled = isInstalled
        }
        if let idx = searchedSets.firstIndex(where: { $0.id == setId }) {
            searchedSets[idx].isInstalled = isInstalled
        }
        if !isInstalled {
            installedSets.removeAll { $0.id == setId }
        } else if !installedSets.contains(where: { $0.id == setId }), let detail {
            installedSets.append(StickerPackSummary(from: detail))
        }
    }

    private static func deduplicateStickers(_ items: [StickerItem]) -> [StickerItem] {
        var seenUnique: Set<String> = []
        var seenFileIds: Set<Int> = []
        var result: [StickerItem] = []
        result.reserveCapacity(items.count)

        for item in items {
            if !item.remoteUniqueId.isEmpty {
                guard seenUnique.insert(item.remoteUniqueId).inserted else { continue }
            } else {
                guard seenFileIds.insert(item.file.fileId).inserted else { continue }
            }
            result.append(item)
        }
        return result
    }

    private static var preferredLanguageCodes: [String] {
        var codes: [String] = []
        let primary = AppConfiguration.systemLanguageCode
        if !primary.isEmpty {
            codes.append(primary)
        }
        if !codes.contains("zh") { codes.append("zh") }
        if !codes.contains("en") { codes.append("en") }
        return codes
    }
}
