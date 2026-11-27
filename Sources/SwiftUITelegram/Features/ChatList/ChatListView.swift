import SwiftUI

struct ChatListView: View {
    @Environment(AppStore.self) private var appStore
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        @Bindable var chatList = appStore.chatList
        let chats = chatList.visibleChats

        VStack(spacing: 0) {
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

                Picker("列表筛选", selection: $chatList.selectedFilter) {
                    ForEach(ChatListFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(10)

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
                ContentUnavailableView(
                    chatList.searchQuery.isEmpty ? "暂无对话" : "无匹配结果",
                    systemImage: chatList.searchQuery.isEmpty ? "tray" : "magnifyingglass",
                    description: Text(chatList.searchQuery.isEmpty ? "已加载的对话将显示在这里。" : "请尝试其他关键词。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $chatList.selectedChatId) {
                    ForEach(chats) { chat in
                        ChatRowView(
                            chat: chat,
                            isPinned: chat.isPinned(in: chatList.selectedFilter)
                        )
                        .tag(chat.id)
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
            }

            Divider()

            sidebarFooter
        }
        .onChange(of: chatList.selectedFilter) { _, newFilter in
            Task {
                await chatList.loadMoreChats(for: newFilter)
            }
        }
        .onChange(of: appStore.searchFocusTrigger) { _, _ in
            isSearchFocused = true
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 6) {
            AccountSwitcherView()

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.body)
            }
            .buttonStyle(.borderless)
            .help("设置 (⌘,)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
