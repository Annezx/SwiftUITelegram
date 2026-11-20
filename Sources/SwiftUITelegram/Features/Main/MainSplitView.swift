import SwiftUI

struct MainSplitView: View {
    @Environment(AppStore.self) private var appStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ChatListView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 310, max: 420)
        } detail: {
            if let chat = appStore.chatList.selectedChat {
                ConversationView(chat: chat)
                    .id(chat.id)
            } else {
                ContentUnavailableView(
                    "选择一个对话",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("从左侧列表选择任意对话开始聊天，或按 ⌘K 快速搜索。")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .status) {
                ConnectionStatusBadge(status: appStore.connectionStatus)
            }
        }
        .onChange(of: appStore.chatList.selectedChatId) { _, newChatId in
            appStore.conversation.selectChat(newChatId)
        }
    }
}
