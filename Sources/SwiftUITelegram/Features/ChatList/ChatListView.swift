import AppKit
import SwiftUI

struct ChatListView: View {
    @Environment(AppStore.self) private var appStore
    @FocusState private var isSearchFocused: Bool
    @State private var confirmationRequest: ChatActionConfirmationRequest?
    @State private var folderEditorRequest: ChatFolderEditorRequest?
    @State private var isShowingFolderManager: Bool = false
    @State private var folderPendingDelete: ChatFolderItem?

    var body: some View {
        @Bindable var chatList = appStore.chatList
        let chats = chatList.visibleChats
        let showFolderTags = chatList.areFolderTagsEnabled
            && chatList.searchQuery.isEmpty
            && chatList.selectedFilter.folderId == nil

        VStack(spacing: 0) {
            // Exact 28pt standard titlebar traffic-light row; search box starts immediately underneath.
            Color.clear
                .frame(height: 28)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(
                        "搜索对话 (⌘K)",
                        text: Binding(
                            get: { chatList.searchQuery },
                            set: { chatList.updateSearchQuery($0) }
                        )
                    )
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)

                    if !chatList.searchQuery.isEmpty {
                        Button {
                            chatList.updateSearchQuery("")
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                ChatFolderTabBarView(
                    tabs: chatList.orderedTabs,
                    selectedFilter: chatList.selectedFilter,
                    unreadProvider: { chatList.unreadCounts(for: $0) },
                    folderOrderIndex: { folderId in
                        chatList.chatFolders.firstIndex(where: { $0.id == folderId })
                    },
                    customFolderCount: chatList.chatFolders.count,
                    onSelect: { filter in
                        chatList.selectFilter(filter)
                    },
                    onMarkAllRead: { filter in
                        Task { await chatList.markChatListAsRead(filter) }
                    },
                    onRefresh: { filter in
                        Task { await chatList.refreshList(for: filter) }
                    },
                    onCreateFolder: {
                        folderEditorRequest = .create()
                    },
                    onEditFolder: { folderId in
                        let title = chatList.folder(for: folderId)?.title ?? chatList.title(for: .folder(folderId))
                        folderEditorRequest = .edit(folderId: folderId, title: title)
                    },
                    onMoveFolder: { folderId, offset in
                        Task { await chatList.moveFolder(folderId: folderId, offset: offset) }
                    },
                    onRequestDeleteFolder: { folderId in
                        folderPendingDelete = chatList.folder(for: folderId)
                    },
                    onManageFolders: {
                        isShowingFolderManager = true
                    }
                )
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            Divider()

            if let error = chatList.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .lineLimit(2)
                    Spacer()
                    Button("重试") {
                        chatList.errorMessage = nil
                        Task { await chatList.refreshCurrentList() }
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.1))
            }

            if chats.isEmpty && !chatList.isLoadingChats {
                emptyChatListView(for: chatList)
            } else {
                List(selection: $chatList.selectedChatId) {
                    ForEach(chats) { chat in
                        ChatRowView(
                            chat: chat,
                            isPinned: chatList.searchQuery.isEmpty ? chat.isPinned(in: chatList.selectedFilter) : false,
                            folderTags: showFolderTags ? chatList.folderTags(for: chat) : []
                        )
                        .tag(chat.id)
                        .contextMenu {
                            chatContextMenu(for: chat)
                        }
                        .onAppear {
                            if chat.id == chats.last?.id {
                                Task { await chatList.loadMoreChats() }
                            }
                        }
                    }

                    if chatList.isLoadingChats {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }

            Divider()

            sidebarFooter
        }
        .background(
            SidebarMaterialBackground()
                .ignoresSafeArea(.all, edges: .top)
        )
        .ignoresSafeArea(.all, edges: .top)
        .sheet(item: $confirmationRequest) { request in
            ChatActionConfirmationSheet(request: request) { revoke in
                switch request.kind {
                case .clearHistory:
                    return await appStore.chatList.clearHistory(chatId: request.chat.id, revoke: revoke)
                case .deleteOrLeave:
                    return await appStore.chatList.deleteOrLeaveChat(chatId: request.chat.id, revoke: revoke)
                }
            }
            .environment(appStore)
        }
        .sheet(item: $folderEditorRequest) { request in
            ChatFolderEditorSheet(request: request)
                .environment(appStore)
        }
        .sheet(isPresented: $isShowingFolderManager) {
            ChatFoldersManagerSheet()
                .environment(appStore)
        }
        .confirmationDialog(
            deleteFolderDialogTitle,
            isPresented: Binding(
                get: { folderPendingDelete != nil },
                set: { if !$0 { folderPendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: folderPendingDelete
        ) { target in
            Button("删除文件夹", role: .destructive) {
                folderPendingDelete = nil
                Task { await appStore.chatList.deleteFolder(folderId: target.id) }
            }
            Button("取消", role: .cancel) {
                folderPendingDelete = nil
            }
        } message: { _ in
            Text("删除文件夹仅移除该分组标签，不会删除或退出其中的任何对话。")
        }
        .onAppear {
            Task {
                await chatList.loadMoreChats(for: chatList.selectedFilter)
            }
        }
        .onChange(of: chatList.selectedFilter) { _, newFilter in
            Task {
                await chatList.loadMoreChats(for: newFilter)
            }
        }
        .onChange(of: appStore.searchFocusTrigger) { _, _ in
            isSearchFocused = true
        }
        .onChange(of: appStore.createFolderTrigger) { _, _ in
            folderEditorRequest = .create()
        }
        .onChange(of: appStore.manageFoldersTrigger) { _, _ in
            isShowingFolderManager = true
        }
    }

    private var deleteFolderDialogTitle: String {
        if let target = folderPendingDelete {
            return "确定要删除文件夹「\(target.title)」吗？"
        }
        return "确定要删除该文件夹吗？"
    }

    @ViewBuilder
    private func emptyChatListView(for chatList: ChatListStore) -> some View {
        if !chatList.searchQuery.isEmpty {
            ContentUnavailableView(
                "无匹配结果",
                systemImage: "magnifyingglass",
                description: Text("请尝试其他关键词。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch chatList.selectedFilter {
            case .main:
                ContentUnavailableView(
                    "暂无对话",
                    systemImage: "tray",
                    description: Text("已加载的对话将显示在这里。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .archive:
                ContentUnavailableView(
                    "暂无已归档对话",
                    systemImage: "archivebox",
                    description: Text("右键点击任意对话可将其归档。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .folder(let folderId):
                let folder = chatList.folder(for: folderId)
                let title = folder?.title ?? chatList.title(for: .folder(folderId))
                ContentUnavailableView {
                    Label("「\(title)」中暂无对话", systemImage: folder?.sfSymbolName ?? "folder")
                } description: {
                    Text("右键点击任意对话可将其加入此文件夹，或编辑筛选规则。")
                } actions: {
                    Button("编辑文件夹") {
                        folderEditorRequest = .edit(folderId: folderId, title: title)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Chat List Context Menu

    @ViewBuilder
    private func chatContextMenu(for chat: ChatSummary) -> some View {
        let chatList = appStore.chatList
        let activeFilter = chatList.selectedFilter
        let isPinned = chat.isPinned(in: activeFilter)
        let isSavedMessages: Bool = {
            guard let meId = appStore.currentUser?.id else { return false }
            if case .privateUser(let userId) = chat.kind {
                return userId == meId
            }
            return false
        }()

        if chat.hasUnreadIndicator {
            Button {
                Task { await chatList.markAsRead(chatId: chat.id) }
            } label: {
                Label("标记为已读", systemImage: "envelope.open")
            }
        } else {
            Button {
                Task { await chatList.markAsUnread(chatId: chat.id) }
            } label: {
                Label("标记为未读", systemImage: "envelope.badge")
            }
        }

        if chat.order(in: activeFilter) != 0 {
            Button {
                Task { await chatList.togglePin(chatId: chat.id, in: activeFilter) }
            } label: {
                Label(
                    isPinned ? "取消置顶" : "置顶对话",
                    systemImage: isPinned ? "pin.slash" : "pin"
                )
            }
        }

        Menu {
            ForEach(chatList.chatFolders) { folder in
                let inFolder = chat.belongsToList(folder.filter)
                Button {
                    Task {
                        if inFolder {
                            await chatList.removeChat(chat.id, fromFolder: folder.id)
                        } else {
                            await chatList.addChat(chat.id, toFolder: folder.id)
                        }
                    }
                } label: {
                    Label(
                        inFolder ? "✓ \(folder.title)" : folder.title,
                        systemImage: folder.sfSymbolName
                    )
                }
            }

            if !chatList.chatFolders.isEmpty {
                Divider()
            }

            Button {
                folderEditorRequest = .create(preselectedChatId: chat.id)
            } label: {
                Label("新建文件夹并添加…", systemImage: "folder.badge.plus")
            }
        } label: {
            Label("文件夹", systemImage: "folder")
        }

        if !isSavedMessages {
            if chat.isMuted {
                Button {
                    Task { await chatList.setMute(chatId: chat.id, muteFor: 0) }
                } label: {
                    Label("开启通知", systemImage: "bell")
                }
            } else {
                Menu {
                    Button("静音 1 小时") {
                        Task { await chatList.setMute(chatId: chat.id, muteFor: 3600) }
                    }
                    Button("静音 8 小时") {
                        Task { await chatList.setMute(chatId: chat.id, muteFor: 8 * 3600) }
                    }
                    Button("静音 2 天") {
                        Task { await chatList.setMute(chatId: chat.id, muteFor: 48 * 3600) }
                    }
                    Divider()
                    Button("永久静音") {
                        Task { await chatList.setMute(chatId: chat.id, muteFor: Int(Int32.max)) }
                    }
                } label: {
                    Label("静音通知", systemImage: "bell.slash")
                }
            }

            Button {
                Task { await chatList.toggleArchive(chatId: chat.id) }
            } label: {
                Label(
                    chat.isArchived ? "取消归档" : "归档对话",
                    systemImage: chat.isArchived ? "tray.and.arrow.up" : "archivebox"
                )
            }
        }

        Divider()

        if canClearHistory(for: chat) {
            Button {
                confirmationRequest = ChatActionConfirmationRequest(chat: chat, kind: .clearHistory)
            } label: {
                Label("清空聊天记录…", systemImage: "eraser")
            }
        }

        if !isSavedMessages {
            Button(role: .destructive) {
                confirmationRequest = ChatActionConfirmationRequest(chat: chat, kind: .deleteOrLeave)
            } label: {
                Label(
                    deleteOrLeaveLabel(for: chat.kind),
                    systemImage: deleteOrLeaveSymbol(for: chat.kind)
                )
            }
        }
    }

    private func canClearHistory(for chat: ChatSummary) -> Bool {
        switch chat.kind {
        case .privateUser, .secret, .basicGroup:
            return chat.canBeDeletedOnlyForSelf || chat.canBeDeletedForAllUsers
        case .supergroup, .channel:
            return false
        }
    }

    private func deleteOrLeaveLabel(for kind: ChatKind) -> String {
        switch kind {
        case .privateUser, .secret:
            return "删除对话…"
        case .basicGroup, .supergroup:
            return "退出群组…"
        case .channel:
            return "退出频道…"
        }
    }

    private func deleteOrLeaveSymbol(for kind: ChatKind) -> String {
        switch kind {
        case .privateUser, .secret:
            return "trash"
        case .basicGroup, .supergroup, .channel:
            return "rectangle.portrait.and.arrow.right"
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 6) {
            AccountSwitcherView()

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.body)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("设置 (⌘,)")
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: LayoutMetrics.bottomBarHeight)
    }
}

private struct SidebarMaterialBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .sidebar
        nsView.blendingMode = .behindWindow
        nsView.state = .followsWindowActiveState
    }
}
