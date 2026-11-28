import AppKit
import SwiftUI

enum StickerEmojiPickerTab: String, CaseIterable, Identifiable {
    case emoji
    case stickers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .emoji: return "Emoji"
        case .stickers: return "贴纸"
        }
    }

    var systemImage: String {
        switch self {
        case .emoji: return "face.smiling"
        case .stickers: return "sparkles.rectangle.stack"
        }
    }
}

private enum StickerShelfSelection: Hashable {
    case favorites
    case recents
    case installedPack(Int64)
    case trending
}

/// Native macOS popover panel combining a bilingual searchable Unicode Emoji picker
/// and a full Telegram Sticker browser (favorites, recents, installed packs, search, and trending).
struct StickerEmojiPickerView: View {
    @Environment(AppStore.self) private var appStore

    let chatId: Int64?
    let allowStickers: Bool
    let onSelectEmoji: (String) -> Void
    let onSendSticker: (StickerItem, _ keepOpen: Bool) -> Void
    let onOpenStickerPack: (Int64) -> Void

    @State private var selectedTab: StickerEmojiPickerTab = .emoji
    @State private var emojiQuery: String = ""
    @State private var stickerQuery: String = ""
    @State private var selectedShelf: StickerShelfSelection = .recents
    @State private var hasPickedInitialShelf: Bool = false

    private let emojiColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 8)
    private let stickerColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        VStack(spacing: 0) {
            topTabBar
            Divider()
            searchBar
            Divider()

            if selectedTab == .emoji || !allowStickers {
                emojiTabContent
            } else {
                stickersTabContent
            }
        }
        .frame(width: 392, height: 452)
        .onAppear {
            if !allowStickers {
                selectedTab = .emoji
            }
        }
        .task {
            await appStore.stickers.ensureInitialLoaded()
            chooseDefaultShelfIfNeeded()
        }
        .onChange(of: allowStickers) { _, allowed in
            if !allowed {
                selectedTab = .emoji
            }
        }
        .onChange(of: emojiQuery) { _, newValue in
            appStore.stickers.updateEmojiSearch(query: newValue)
        }
        .onChange(of: stickerQuery) { _, newValue in
            appStore.stickers.updateStickerSearch(query: newValue, chatId: chatId)
        }
        .onChange(of: selectedShelf) { _, shelf in
            handleShelfSelectionChange(shelf)
        }
    }

    // MARK: - Top Tab Switcher & Search Bar

    private var topTabBar: some View {
        HStack(spacing: 6) {
            ForEach(StickerEmojiPickerTab.allCases) { tab in
                let isEnabled = tab == .emoji || allowStickers
                let isSelected = (selectedTab == tab) || (!allowStickers && tab == .emoji)

                Button {
                    guard isEnabled else { return }
                    selectedTab = tab
                    if tab == .stickers {
                        Task {
                            await appStore.stickers.ensureInitialLoaded()
                            chooseDefaultShelfIfNeeded()
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.systemImage)
                            .font(.caption.weight(.semibold))
                        Text(tab.title)
                            .font(.callout.weight(.medium))
                    }
                    .foregroundStyle(
                        isSelected
                            ? Color.accentColor
                            : (isEnabled ? Color.secondary : Color.secondary.opacity(0.4))
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        isSelected ? Color.accentColor.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .help(isEnabled ? tab.title : "编辑消息时仅支持插入 Emoji")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var searchBar: some View {
        let binding = selectedTab == .emoji || !allowStickers ? $emojiQuery : $stickerQuery
        let placeholder = selectedTab == .emoji || !allowStickers
            ? "搜索 Emoji（支持中文 / 英文关键词）…"
            : "搜索贴纸、Emoji 或公开贴纸包…"

        return HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(placeholder, text: binding)
                .textFieldStyle(.plain)
                .font(.callout)

            if !binding.wrappedValue.isEmpty {
                Button {
                    binding.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.75)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Emoji Tab

    private var emojiTabContent: some View {
        let store = appStore.stickers
        let trimmedQuery = emojiQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        return Group {
            if !trimmedQuery.isEmpty {
                emojiSearchResultsView(entries: store.searchedEmojis, isSearching: store.isSearchingEmojis)
            } else {
                ScrollViewReader { proxy in
                    VStack(spacing: 0) {
                        emojiCategoryStrip { target in
                            withAnimation(.snappy(duration: 0.2)) {
                                proxy.scrollTo(target, anchor: .top)
                            }
                        }

                        Divider()

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                if !store.recentEmojis.isEmpty {
                                    let recentEntries = store.recentEmojis.map { symbol in
                                        EmojiCatalog.entryBySymbol[symbol] ?? EmojiEntry(symbol, symbol)
                                    }
                                    emojiSectionView(
                                        title: EmojiCategoryKind.recent.title,
                                        entries: recentEntries
                                    )
                                    .id(EmojiCategoryKind.recent)
                                }

                                ForEach(EmojiCatalog.sections) { section in
                                    emojiSectionView(title: section.title, entries: section.entries)
                                        .id(section.kind)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                        }
                    }
                }
            }
        }
    }

    private func emojiCategoryStrip(onJump: @escaping (EmojiCategoryKind) -> Void) -> some View {
        let hasRecents = !appStore.stickers.recentEmojis.isEmpty
        let kinds = EmojiCategoryKind.allCases.filter { $0 != .recent || hasRecents }

        return HStack(spacing: 2) {
            ForEach(kinds) { kind in
                Button {
                    onJump(kind)
                } label: {
                    Image(systemName: kind.systemImage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(kind.title)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func emojiSearchResultsView(entries: [EmojiEntry], isSearching: Bool) -> some View {
        ScrollView {
            if entries.isEmpty {
                VStack(spacing: 8) {
                    if isSearching {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在搜索 Emoji…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "face.smiling")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("未找到匹配的 Emoji")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 72)
            } else {
                LazyVGrid(columns: emojiColumns, spacing: 4) {
                    ForEach(entries) { entry in
                        EmojiCellButton(entry: entry) {
                            appStore.stickers.recordRecentEmoji(entry.symbol)
                            onSelectEmoji(entry.symbol)
                        }
                    }
                }
                .padding(10)
            }
        }
    }

    private func emojiSectionView(title: String, entries: [EmojiEntry]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            LazyVGrid(columns: emojiColumns, spacing: 4) {
                ForEach(entries) { entry in
                    EmojiCellButton(entry: entry) {
                        appStore.stickers.recordRecentEmoji(entry.symbol)
                        onSelectEmoji(entry.symbol)
                    }
                }
            }
        }
    }

    // MARK: - Stickers Tab

    private var stickersTabContent: some View {
        let store = appStore.stickers
        let trimmedQuery = stickerQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(spacing: 0) {
            if !trimmedQuery.isEmpty {
                stickerSearchResultsView(
                    stickers: store.searchedStickers,
                    packs: store.searchedSets,
                    isSearching: store.isSearchingStickers
                )
            } else {
                stickerPackNavigationStrip
                Divider()
                activeStickerShelfContent
            }
        }
    }

    private var stickerPackNavigationStrip: some View {
        let store = appStore.stickers

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                shelfSystemButton(
                    selection: .favorites,
                    systemImage: "star.fill",
                    tint: .orange,
                    helpText: "收藏的贴纸 (\(store.favoriteStickers.count))"
                )

                shelfSystemButton(
                    selection: .recents,
                    systemImage: "clock.fill",
                    tint: .accentColor,
                    helpText: "最近使用的贴纸 (\(store.recentStickers.count))"
                )

                if !store.installedSets.isEmpty {
                    Divider()
                        .frame(height: 22)
                        .padding(.horizontal, 2)

                    ForEach(store.installedSets) { pack in
                        stickerPackTabButton(pack)
                    }
                }

                Divider()
                    .frame(height: 22)
                    .padding(.horizontal, 2)

                shelfSystemButton(
                    selection: .trending,
                    systemImage: "flame.fill",
                    tint: .pink,
                    helpText: "热门与发现贴纸包"
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(height: 44)
    }

    private func shelfSystemButton(
        selection: StickerShelfSelection,
        systemImage: String,
        tint: Color,
        helpText: String
    ) -> some View {
        let isSelected = selectedShelf == selection

        return Button {
            selectedShelf = selection
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? tint : Color.secondary)
                .frame(width: 32, height: 32)
                .background(
                    isSelected ? tint.opacity(0.15) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private func stickerPackTabButton(_ pack: StickerPackSummary) -> some View {
        let isSelected = selectedShelf == .installedPack(pack.id)

        return Button {
            selectedShelf = .installedPack(pack.id)
        } label: {
            Group {
                if let thumb = pack.thumbnail {
                    AnimatedStickerSurfaceView(
                        thumbnailInfo: thumb,
                        size: CGSize(width: 26, height: 26),
                        isPlaying: false,
                        maxPixelSize: 64,
                        downloadPriority: 14
                    )
                } else if let cover = pack.iconSticker {
                    AnimatedStickerSurfaceView(
                        sticker: cover,
                        size: CGSize(width: 26, height: 26),
                        isPlaying: false,
                        firstFrameOnly: true,
                        maxPixelSize: 64,
                        downloadPriority: 14
                    )
                } else {
                    Text(String(pack.title.prefix(1)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 32, height: 32)
            .background(
                isSelected ? Color.accentColor.opacity(0.16) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(pack.title)（\(pack.size) 张）")
    }

    @ViewBuilder
    private var activeStickerShelfContent: some View {
        let store = appStore.stickers

        if store.isLoadingInitial && store.installedSets.isEmpty && store.recentStickers.isEmpty && store.favoriteStickers.isEmpty {
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在加载贴纸…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch selectedShelf {
            case .favorites:
                stickerGridPage(
                    title: "收藏贴纸",
                    subtitle: "\(store.favoriteStickers.count) 张",
                    stickers: store.favoriteStickers,
                    isRecentList: false,
                    emptyTitle: "暂无收藏贴纸",
                    emptyHint: "右键任意贴纸可加入收藏，方便随时发送。",
                    trailingAction: nil
                )

            case .recents:
                stickerGridPage(
                    title: "最近使用",
                    subtitle: "\(store.recentStickers.count) 张",
                    stickers: store.recentStickers,
                    isRecentList: true,
                    emptyTitle: "暂无最近使用的贴纸",
                    emptyHint: "发送贴纸后将自动出现在这里，也可以去「热门」添加贴纸包。",
                    trailingAction: store.installedSets.isEmpty ? AnyView(
                        Button("浏览热门贴纸") {
                            selectedShelf = .trending
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    ) : nil
                )

            case .installedPack(let setId):
                installedPackPage(setId: setId)

            case .trending:
                trendingPacksPage
            }
        }
    }

    private func installedPackPage(setId: Int64) -> some View {
        let store = appStore.stickers
        let summary = store.installedSets.first(where: { $0.id == setId })
        let detail = store.loadedSetDetails[setId]
        let isLoading = store.loadingSetIds.contains(setId)
        let title = detail?.title ?? summary?.title ?? "贴纸包"
        let stickers = detail?.stickers ?? summary?.covers ?? []

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        if let fmt = detail?.formatSummary {
                            Text(fmt)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                    }
                    Text("\(detail?.stickers.count ?? summary?.size ?? stickers.count) 张贴纸")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("预览") {
                    onOpenStickerPack(setId)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("移除", role: .destructive) {
                    Task {
                        let ok = await store.setStickerSetInstalled(setId: setId, installed: false)
                        if ok {
                            selectedShelf = store.installedSets.first.map { .installedPack($0.id) } ?? .recents
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(store.mutatingSetIds.contains(setId))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if isLoading && stickers.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在加载贴纸包…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: stickerColumns, spacing: 6) {
                        ForEach(stickers) { sticker in
                            StickerPickerTileView(
                                sticker: sticker,
                                isFavorite: store.isFavorite(sticker),
                                showRemoveFromRecent: false,
                                onSend: { keepOpen in
                                    onSendSticker(sticker, keepOpen)
                                },
                                onToggleFavorite: {
                                    Task { _ = await store.toggleFavorite(sticker) }
                                },
                                onRemoveRecent: nil,
                                onOpenPack: sticker.setId != 0 ? { onOpenStickerPack(sticker.setId) } : nil
                            )
                        }
                    }
                    .padding(10)
                }
            }
        }
        .task(id: setId) {
            await store.loadStickerSet(id: setId)
        }
    }

    private func stickerGridPage(
        title: String,
        subtitle: String,
        stickers: [StickerItem],
        isRecentList: Bool,
        emptyTitle: String,
        emptyHint: String,
        trailingAction: AnyView?
    ) -> some View {
        let store = appStore.stickers

        return VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if stickers.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: isRecentList ? "clock" : "star")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text(emptyTitle)
                        .font(.callout.weight(.medium))
                    Text(emptyHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)
                    if let trailingAction {
                        trailingAction
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            } else {
                ScrollView {
                    LazyVGrid(columns: stickerColumns, spacing: 6) {
                        ForEach(stickers) { sticker in
                            StickerPickerTileView(
                                sticker: sticker,
                                isFavorite: store.isFavorite(sticker),
                                showRemoveFromRecent: isRecentList,
                                onSend: { keepOpen in
                                    onSendSticker(sticker, keepOpen)
                                },
                                onToggleFavorite: {
                                    Task { _ = await store.toggleFavorite(sticker) }
                                },
                                onRemoveRecent: isRecentList ? {
                                    Task { await store.removeRecent(sticker) }
                                } : nil,
                                onOpenPack: sticker.setId != 0 ? { onOpenStickerPack(sticker.setId) } : nil
                            )
                        }
                    }
                    .padding(10)
                }
            }
        }
    }

    private var trendingPacksPage: some View {
        let store = appStore.stickers

        return VStack(spacing: 0) {
            HStack {
                Text("热门贴纸包")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text("点击贴纸即可发送或添加到我的贴纸")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if store.isLoadingTrending && store.trendingSets.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在获取热门贴纸包…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.trendingSets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "flame")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("暂无热门贴纸推荐")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.trendingSets) { pack in
                            TrendingStickerPackCard(
                                pack: pack,
                                isInstalled: store.isSetInstalled(pack.id),
                                isMutating: store.mutatingSetIds.contains(pack.id),
                                onToggleInstall: {
                                    let currentlyInstalled = store.isSetInstalled(pack.id)
                                    Task {
                                        _ = await store.setStickerSetInstalled(
                                            setId: pack.id,
                                            installed: !currentlyInstalled
                                        )
                                    }
                                },
                                onOpenPack: {
                                    onOpenStickerPack(pack.id)
                                },
                                onSendSticker: { sticker, keepOpen in
                                    onSendSticker(sticker, keepOpen)
                                }
                            )
                        }
                    }
                    .padding(10)
                }
            }
        }
        .task {
            await store.ensureTrendingLoaded()
        }
    }

    private func stickerSearchResultsView(
        stickers: [StickerItem],
        packs: [StickerPackSummary],
        isSearching: Bool
    ) -> some View {
        let store = appStore.stickers

        return ScrollView {
            if isSearching && stickers.isEmpty && packs.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在搜索贴纸…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else if stickers.isEmpty && packs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("未找到匹配的贴纸或贴纸包")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    if !stickers.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("匹配贴纸 (\(stickers.count))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            LazyVGrid(columns: stickerColumns, spacing: 6) {
                                ForEach(stickers) { sticker in
                                    StickerPickerTileView(
                                        sticker: sticker,
                                        isFavorite: store.isFavorite(sticker),
                                        showRemoveFromRecent: false,
                                        onSend: { keepOpen in
                                            onSendSticker(sticker, keepOpen)
                                        },
                                        onToggleFavorite: {
                                            Task { _ = await store.toggleFavorite(sticker) }
                                        },
                                        onRemoveRecent: nil,
                                        onOpenPack: sticker.setId != 0 ? { onOpenStickerPack(sticker.setId) } : nil
                                    )
                                }
                            }
                        }
                    }

                    if !packs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("贴纸包 (\(packs.count))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(packs) { pack in
                                TrendingStickerPackCard(
                                    pack: pack,
                                    isInstalled: store.isSetInstalled(pack.id),
                                    isMutating: store.mutatingSetIds.contains(pack.id),
                                    onToggleInstall: {
                                        let installed = store.isSetInstalled(pack.id)
                                        Task {
                                            _ = await store.setStickerSetInstalled(
                                                setId: pack.id,
                                                installed: !installed
                                            )
                                        }
                                    },
                                    onOpenPack: {
                                        onOpenStickerPack(pack.id)
                                    },
                                    onSendSticker: { sticker, keepOpen in
                                        onSendSticker(sticker, keepOpen)
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(10)
            }
        }
    }

    // MARK: - Helpers

    private func chooseDefaultShelfIfNeeded() {
        guard !hasPickedInitialShelf else { return }
        hasPickedInitialShelf = true

        let store = appStore.stickers
        if !store.recentStickers.isEmpty {
            selectedShelf = .recents
        } else if !store.favoriteStickers.isEmpty {
            selectedShelf = .favorites
        } else if let firstPack = store.installedSets.first {
            selectedShelf = .installedPack(firstPack.id)
        } else {
            selectedShelf = .trending
        }
    }

    private func handleShelfSelectionChange(_ shelf: StickerShelfSelection) {
        switch shelf {
        case .installedPack(let setId):
            Task { await appStore.stickers.loadStickerSet(id: setId) }
        case .trending:
            Task { await appStore.stickers.ensureTrendingLoaded() }
        case .favorites, .recents:
            break
        }
    }
}

// MARK: - Subviews

private struct EmojiCellButton: View {
    let entry: EmojiEntry
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onTap) {
            Text(entry.symbol)
                .font(.system(size: 24))
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(
                    isHovered ? Color.accentColor.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .scaleEffect(isHovered ? 1.12 : 1.0)
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(entry.label)
    }
}

struct StickerPickerTileView: View {
    let sticker: StickerItem
    let isFavorite: Bool
    let showRemoveFromRecent: Bool
    var tileSize: CGFloat = 78
    let onSend: (_ keepOpen: Bool) -> Void
    let onToggleFavorite: () -> Void
    let onRemoveRecent: (() -> Void)?
    let onOpenPack: (() -> Void)?

    @State private var isHovered: Bool = false

    var body: some View {
        Button {
            let keepOpen = NSEvent.modifierFlags.contains(.option)
            onSend(keepOpen)
        } label: {
            ZStack(alignment: .topTrailing) {
                AnimatedStickerSurfaceView(
                    sticker: sticker,
                    size: CGSize(width: tileSize - 10, height: tileSize - 10),
                    isPlaying: isHovered,
                    firstFrameOnly: !isHovered,
                    maxPixelSize: 144,
                    downloadPriority: isHovered ? 24 : 12,
                    allowWebKitFallback: false,
                    showDownloadSpinner: false
                )
                .scaleEffect(isHovered ? 1.06 : 1.0)
                .animation(.easeOut(duration: 0.14), value: isHovered)

                if sticker.isPremium {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )
                        .padding(3)
                }
            }
            .frame(width: tileSize, height: tileSize)
            .background(
                isHovered ? Color.primary.opacity(0.07) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(stickerTooltip)
        .contextMenu {
            Button {
                onSend(false)
            } label: {
                Label("发送贴纸", systemImage: "paperplane")
            }

            Button {
                onToggleFavorite()
            } label: {
                Label(
                    isFavorite ? "取消收藏" : "收藏贴纸",
                    systemImage: isFavorite ? "star.slash" : "star"
                )
            }

            if showRemoveFromRecent, let onRemoveRecent {
                Button {
                    onRemoveRecent()
                } label: {
                    Label("从最近使用中移除", systemImage: "clock.badge.xmark")
                }
            }

            if let onOpenPack {
                Divider()
                Button {
                    onOpenPack()
                } label: {
                    Label("查看贴纸包…", systemImage: "square.grid.2x2")
                }
            }
        }
    }

    private var stickerTooltip: String {
        let base = sticker.emoji.isEmpty ? "点击发送贴纸" : "\(sticker.emoji) 点击发送（按住 Option 可连发）"
        return base
    }
}

private struct TrendingStickerPackCard: View {
    let pack: StickerPackSummary
    let isInstalled: Bool
    let isMutating: Bool
    let onToggleInstall: () -> Void
    let onOpenPack: () -> Void
    let onSendSticker: (StickerItem, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(action: onOpenPack) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(pack.title)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if pack.isOfficial {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.caption2)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        Text("\(pack.size) 张贴纸")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: onToggleInstall) {
                    if isMutating {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 44)
                    } else {
                        Text(isInstalled ? "已添加" : "添加")
                            .font(.caption.weight(.semibold))
                            .frame(minWidth: 44)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(isInstalled ? .secondary : .accentColor)
                .controlSize(.small)
                .disabled(isMutating)
            }

            if !pack.covers.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(pack.covers.prefix(5))) { sticker in
                        TrendingCoverTile(sticker: sticker) { keepOpen in
                            onSendSticker(sticker, keepOpen)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.65),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 0.75)
        )
    }
}

private struct TrendingCoverTile: View {
    let sticker: StickerItem
    let onSend: (Bool) -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button {
            onSend(NSEvent.modifierFlags.contains(.option))
        } label: {
            AnimatedStickerSurfaceView(
                sticker: sticker,
                size: CGSize(width: 56, height: 56),
                isPlaying: isHovered,
                firstFrameOnly: !isHovered,
                maxPixelSize: 120,
                downloadPriority: isHovered ? 22 : 10
            )
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(
                isHovered ? Color.primary.opacity(0.06) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .scaleEffect(isHovered ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.14), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
