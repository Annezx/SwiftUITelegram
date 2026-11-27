import SwiftUI

struct ForwardMessagesRequest: Identifiable, Equatable {
    let id = UUID()
    let fromChatId: Int64
    let messages: [MessageItem]

    var messageIds: [Int64] {
        messages.map(\.id)
    }

    var hasAnyMediaCaption: Bool {
        messages.contains { !$0.content.captionText.isEmpty }
    }
}

struct ForwardMessagesSheet: View {
    @Environment(AppStore.self) private var appStore
    @Environment(\.dismiss) private var dismiss

    let request: ForwardMessagesRequest
    let onForward: (
        _ targetChatIds: [Int64],
        _ sendCopy: Bool,
        _ removeCaption: Bool,
        _ comment: String
    ) async -> Bool

    @State private var searchQuery: String = ""
    @State private var candidateChats: [ChatSummary] = []
    @State private var savedMessagesChatId: Int64?
    @State private var selectedChatIds: Set<Int64> = []
    @State private var sendCopy: Bool = false
    @State private var removeCaption: Bool = false
    @State private var commentText: String = ""
    @State private var isForwarding: Bool = false
    @State private var searchTask: Task<Void, Never>?

    private var summaryLine: String {
        if request.messages.count == 1, let first = request.messages.first {
            return first.previewText
        }
        return "共 \(request.messages.count) 条消息"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            Divider()

            searchBar

            Divider()

            chatListSection

            Divider()

            optionsAndFooter
        }
        .frame(width: 440, height: 540)
        .task {
            await loadInitialTargets()
        }
        .onChange(of: searchQuery) { _, newValue in
            scheduleSearch(query: newValue)
        }
        .onChange(of: sendCopy) { _, enabled in
            if !enabled {
                removeCaption = false
            }
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrowshape.turn.up.right.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(request.messages.count == 1 ? "转发消息" : "转发 \(request.messages.count) 条消息")
                    .font(.headline)
                Text(summaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isForwarding)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("搜索目标对话、群组或频道…", text: $searchQuery)
                .textFieldStyle(.plain)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var chatListSection: some View {
        Group {
            if candidateChats.isEmpty {
                ContentUnavailableView(
                    "未找到匹配的对话",
                    systemImage: "magnifyingglass",
                    description: Text("请尝试输入其他关键词。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(candidateChats) { chat in
                            forwardTargetRow(chat: chat)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func forwardTargetRow(chat: ChatSummary) -> some View {
        let isSelected = selectedChatIds.contains(chat.id)
        let isSavedMessages = chat.id == savedMessagesChatId

        return Button {
            if isSelected {
                selectedChatIds.remove(chat.id)
            } else {
                selectedChatIds.insert(chat.id)
            }
        } label: {
            HStack(spacing: 10) {
                if isSavedMessages {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.gradient)
                            .frame(width: 36, height: 36)
                        Image(systemName: "bookmark.fill")
                            .font(.callout)
                            .foregroundStyle(.white)
                    }
                } else {
                    AvatarView(
                        title: chat.title,
                        initials: chat.avatarInitials,
                        accentSeed: chat.accentColorId,
                        fileId: chat.smallPhotoFileId,
                        knownLocalPath: chat.smallPhotoLocalPath,
                        size: 36
                    )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isSavedMessages ? "收藏夹 (Saved Messages)" : chat.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(isSavedMessages ? "仅自己可见的云端收藏" : kindLabel(for: chat.kind))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.45))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isSelected ? Color.accentColor.opacity(0.10) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var optionsAndFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Toggle("隐藏原发送者", isOn: $sendCopy)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .font(.caption)

                if sendCopy && request.hasAnyMediaCaption {
                    Toggle("移除说明文字", isOn: $removeCaption)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .font(.caption)
                }

                Spacer()
            }

            TextField("添加附言（可选）…", text: $commentText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.regular)

            HStack(spacing: 10) {
                if !selectedChatIds.isEmpty {
                    Text("已选择 \(selectedChatIds.count) 个对话")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isForwarding)

                Button {
                    Task {
                        isForwarding = true
                        let orderedTargets = candidateChats
                            .map(\.id)
                            .filter { selectedChatIds.contains($0) }
                        let remainingTargets = selectedChatIds.filter { !orderedTargets.contains($0) }
                        let finalTargets = orderedTargets + Array(remainingTargets)
                        let ok = await onForward(finalTargets, sendCopy, removeCaption, commentText)
                        isForwarding = false
                        if ok {
                            dismiss()
                        }
                    }
                } label: {
                    if isForwarding {
                        ProgressView()
                            .controlSize(.small)
                            .frame(minWidth: 56)
                    } else {
                        Text(selectedChatIds.count > 1 ? "转发 (\(selectedChatIds.count))" : "转发")
                            .frame(minWidth: 56)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedChatIds.isEmpty || isForwarding)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func loadInitialTargets() async {
        var chats = appStore.chatList.allSortedChats
        if let meId = appStore.currentUser?.id,
           let savedChat = await appStore.chatList.ensureSavedMessagesChat(currentUserId: meId)
        {
            savedMessagesChatId = savedChat.id
            chats.removeAll { $0.id == savedChat.id }
            chats.insert(savedChat, at: 0)
        }
        candidateChats = chats
    }

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Task { await loadInitialTargets() }
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let results = await appStore.chatList.searchForwardTargets(query: trimmed)
            guard !Task.isCancelled else { return }
            candidateChats = results
        }
    }

    private func kindLabel(for kind: ChatKind) -> String {
        switch kind {
        case .privateUser: return "私聊"
        case .basicGroup: return "群组"
        case .supergroup: return "超级群组"
        case .channel: return "频道"
        case .secret: return "加密对话"
        }
    }
}
