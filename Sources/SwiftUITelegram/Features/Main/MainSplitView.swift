import SwiftUI

struct MainSplitView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        @Bindable var store = appStore

        HSplitView {
            ChatListView()
                .frame(minWidth: 260, idealWidth: 310, maxWidth: 420)
                .layoutPriority(0)

            detailColumn
                .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        }
        .ignoresSafeArea(.all, edges: .top)
        .onAppear {
            if let selected = appStore.chatList.selectedChatId {
                appStore.conversation.selectChat(selected)
            }
        }
        .onChange(of: appStore.chatList.selectedChatId) { _, newChatId in
            appStore.conversation.selectChat(newChatId)
        }
        .sheet(item: $store.pendingChatInvite) { invite in
            TelegramChatInviteSheet(invite: invite)
                .environment(appStore)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let chat = appStore.chatList.selectedChat {
            ConversationView(chat: chat)
                .id(chat.id)
        } else {
            emptyDetailView
        }
    }

    private var emptyDetailView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer()

                ConnectionStatusBadge(status: appStore.connectionStatus)
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())

            ContentUnavailableView(
                "选择一个对话",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("从左侧列表选择任意对话开始聊天，或按 ⌘K 快速搜索。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.all, edges: .top)
    }
}
