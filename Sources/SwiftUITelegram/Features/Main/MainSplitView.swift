import SwiftUI

struct MainSplitView: View {
    @Environment(AppStore.self) private var appStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var isSidebarHidden: Bool {
        columnVisibility == .detailOnly
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ChatListView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 310, max: 420)
        } detail: {
            if let chat = appStore.chatList.selectedChat {
                ConversationView(
                    chat: chat,
                    isSidebarHidden: isSidebarHidden,
                    onShowSidebar: {
                        withAnimation(.snappy(duration: 0.2)) {
                            columnVisibility = .all
                        }
                    }
                )
                .id(chat.id)
            } else {
                emptyDetailView
            }
        }
        .toolbarVisibility(.hidden, for: .windowToolbar)
        .onAppear {
            if let selected = appStore.chatList.selectedChatId {
                appStore.conversation.selectChat(selected)
            }
        }
        .onChange(of: appStore.chatList.selectedChatId) { _, newChatId in
            appStore.conversation.selectChat(newChatId)
        }
    }

    private var emptyDetailView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if isSidebarHidden {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            columnVisibility = .all
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("显示侧边栏")
                    .padding(.leading, 72)
                }

                Spacer()

                ConnectionStatusBadge(status: appStore.connectionStatus)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())

            ContentUnavailableView(
                "选择一个对话",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("从左侧列表选择任意对话开始聊天，或按 ⌘K 快速搜索。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}
