import SwiftUI

struct ChatFolderEditorRequest: Identifiable, Equatable {
    let id = UUID()
    let folderId: Int?
    let initialTitle: String
    let preselectedChatId: Int64?

    static func create(preselectedChatId: Int64? = nil) -> ChatFolderEditorRequest {
        ChatFolderEditorRequest(
            folderId: nil,
            initialTitle: "新建文件夹",
            preselectedChatId: preselectedChatId
        )
    }

    static func edit(folderId: Int, title: String) -> ChatFolderEditorRequest {
        ChatFolderEditorRequest(
            folderId: folderId,
            initialTitle: title,
            preselectedChatId: nil
        )
    }
}

/// Native macOS sheet for creating or editing a Telegram chat folder (`createChatFolder` / `editChatFolder`).
struct ChatFolderEditorSheet: View {
    private enum ChatPickerTarget: Equatable {
        case included
        case excluded
    }

    @Environment(AppStore.self) private var appStore
    @Environment(\.dismiss) private var dismiss

    let request: ChatFolderEditorRequest

    @State private var draft = ChatFolderDraft.empty
    @State private var isLoading: Bool = false
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    @State private var activePicker: ChatPickerTarget?
    @State private var chatSearchQuery: String = ""

    private var isEditing: Bool {
        request.folderId != nil
    }

    private var allIncludedIds: [Int64] {
        var seen = Set<Int64>()
        var result: [Int64] = []
        for id in draft.pinnedChatIds + draft.includedChatIds {
            if seen.insert(id).inserted {
                result.append(id)
            }
        }
        return result
    }

    private var filteredPickerChats: [ChatSummary] {
        let trimmed = chatSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let allChats = appStore.chatList.allSortedChats
        guard !trimmed.isEmpty else {
            return Array(allChats.prefix(80))
        }
        return allChats.filter { chat in
            chat.title.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            Divider()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("正在加载文件夹配置…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                editorBody
            }

            if let errorMessage {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.1))
            }

            Divider()

            footerSection
        }
        .frame(width: 480, height: 580)
        .task(id: request.id) {
            await loadInitialDraft()
        }
    }

    // MARK: - Header & Footer

    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: draft.iconName.isEmpty ? "folder.fill" : ChatFolderIconCatalog.sfSymbolName(for: draft.iconName))
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(isEditing ? "编辑文件夹" : "新建文件夹")
                    .font(.headline)
                Text(isEditing ? "修改文件夹名称、图标与筛选条件" : "按分类或指定对话整理您的聊天列表")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            .disabled(isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var footerSection: some View {
        HStack(spacing: 10) {
            if !draft.isValid && !isLoading {
                Text(validationHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("取消") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isSaving)

            Button {
                Task { await submitSave() }
            } label: {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .frame(minWidth: 64)
                } else {
                    Text(isEditing ? "保存" : "创建")
                        .frame(minWidth: 64)
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(isLoading || isSaving || !draft.isValid)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var validationHint: String {
        let len = draft.trimmedTitle.count
        if len == 0 {
            return "请输入文件夹名称"
        }
        if len > ChatFolderDraft.maxTitleLength {
            return "名称最多 \(ChatFolderDraft.maxTitleLength) 个字符"
        }
        return "请至少选择一个分类或对话"
    }

    // MARK: - Editor Form Body

    private var editorBody: some View {
        Form {
            Section("名称与图标") {
                HStack(spacing: 8) {
                    TextField("例如：工作、频道、未读", text: $draft.title)
                        .textFieldStyle(.roundedBorder)

                    Text("\(draft.trimmedTitle.count)/\(ChatFolderDraft.maxTitleLength)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(
                            draft.trimmedTitle.count > ChatFolderDraft.maxTitleLength
                                ? Color.red
                                : Color.secondary
                        )
                        .frame(width: 36, alignment: .trailing)
                }

                iconGridPicker
            }

            if draft.isShareable {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "link.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        Text("此文件夹已创建分享链接。按 Telegram 规则，可分享文件夹仅支持通过「始终包含的对话」管理成员，无法启用分类或排除规则。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section("包含的对话分类") {
                    Toggle(isOn: $draft.includeContacts) {
                        Label("联系人", systemImage: "person")
                    }
                    Toggle(isOn: $draft.includeNonContacts) {
                        Label("非联系人", systemImage: "person.badge.plus")
                    }
                    Toggle(isOn: $draft.includeGroups) {
                        Label("群组", systemImage: "person.3")
                    }
                    Toggle(isOn: $draft.includeChannels) {
                        Label("频道", systemImage: "megaphone")
                    }
                    Toggle(isOn: $draft.includeBots) {
                        Label("机器人", systemImage: "cpu")
                    }
                }
            }

            Section {
                chatSelectionSummary(
                    chatIds: allIncludedIds,
                    target: .included,
                    emptyText: "尚未添加指定对话",
                    buttonTitle: activePicker == .included ? "收起对话选择" : "添加或管理包含对话…"
                )

                if activePicker == .included {
                    inlineChatPicker(for: .included)
                }
            } header: {
                Text("始终包含的对话 (\(allIncludedIds.count))")
            }

            if !draft.isShareable {
                Section("排除条件") {
                    Toggle(isOn: $draft.excludeMuted) {
                        Label("排除已静音对话", systemImage: "speaker.slash")
                    }
                    Toggle(isOn: $draft.excludeRead) {
                        Label("排除已读对话", systemImage: "envelope.open")
                    }
                    Toggle(isOn: $draft.excludeArchived) {
                        Label("排除已归档对话", systemImage: "archivebox")
                    }
                }

                Section {
                    chatSelectionSummary(
                        chatIds: draft.excludedChatIds,
                        target: .excluded,
                        emptyText: "尚未设置排除对话",
                        buttonTitle: activePicker == .excluded ? "收起对话选择" : "添加或管理排除对话…"
                    )

                    if activePicker == .excluded {
                        inlineChatPicker(for: .excluded)
                    }
                } header: {
                    Text("始终排除的对话 (\(draft.excludedChatIds.count))")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var iconGridPicker: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 8)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(ChatFolderIconCatalog.selectableOptions) { option in
                let isSelected = draft.iconName == option.tdName
                Button {
                    draft.iconName = option.tdName
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: option.sfSymbolName)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .frame(height: 18)
                        Text(option.label)
                            .font(.system(size: 9))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .background(
                        isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentColor.opacity(0.6) : Color.clear,
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .help(option.label)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func chatSelectionSummary(
        chatIds: [Int64],
        target: ChatPickerTarget,
        emptyText: String,
        buttonTitle: String
    ) -> some View {
        if chatIds.isEmpty {
            Text(emptyText)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(chatIds, id: \.self) { chatId in
                    selectedChatChipRow(chatId: chatId, target: target)
                }
            }
        }

        Button {
            if activePicker == target {
                activePicker = nil
                chatSearchQuery = ""
            } else {
                chatSearchQuery = ""
                activePicker = target
            }
        } label: {
            Label(
                buttonTitle,
                systemImage: activePicker == target ? "chevron.up" : "plus.circle"
            )
            .font(.callout)
        }
        .buttonStyle(.link)
    }

    private func selectedChatChipRow(chatId: Int64, target: ChatPickerTarget) -> some View {
        let chat = appStore.chatList.chatsById[chatId]
        return HStack(spacing: 8) {
            if let chat {
                AvatarView(
                    title: chat.title,
                    initials: chat.avatarInitials,
                    accentSeed: chat.accentColorId,
                    fileId: chat.smallPhotoFileId,
                    knownLocalPath: chat.smallPhotoLocalPath,
                    size: 22
                )
                Text(chat.title)
                    .font(.callout)
                    .lineLimit(1)
            } else {
                Image(systemName: "bubble.left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                Text("对话 #\(chatId)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                removeChat(chatId, from: target)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("移除")
        }
        .onAppear {
            if chat == nil {
                appStore.chatList.ensureChatLoaded(chatId: chatId)
            }
        }
    }

    private func inlineChatPicker(for target: ChatPickerTarget) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("筛选已加载的对话…", text: $chatSearchQuery)
                    .textFieldStyle(.plain)
                if !chatSearchQuery.isEmpty {
                    Button {
                        chatSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredPickerChats) { chat in
                        let selected = isChatSelected(chat.id, in: target)
                        Button {
                            toggleChat(chat.id, in: target)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)

                                AvatarView(
                                    title: chat.title,
                                    initials: chat.avatarInitials,
                                    accentSeed: chat.accentColorId,
                                    fileId: chat.smallPhotoFileId,
                                    knownLocalPath: chat.smallPhotoLocalPath,
                                    size: 24
                                )

                                Text(chat.title)
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Spacer(minLength: 4)

                                Text(appStore.chatList.subtitle(for: chat))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                selected ? Color.accentColor.opacity(0.1) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 160)
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func isChatSelected(_ chatId: Int64, in target: ChatPickerTarget) -> Bool {
        switch target {
        case .included:
            return draft.includedChatIds.contains(chatId) || draft.pinnedChatIds.contains(chatId)
        case .excluded:
            return draft.excludedChatIds.contains(chatId)
        }
    }

    private func toggleChat(_ chatId: Int64, in target: ChatPickerTarget) {
        if isChatSelected(chatId, in: target) {
            removeChat(chatId, from: target)
        } else {
            switch target {
            case .included:
                draft.excludedChatIds.removeAll { $0 == chatId }
                if !draft.includedChatIds.contains(chatId) {
                    draft.includedChatIds.append(chatId)
                }
            case .excluded:
                draft.includedChatIds.removeAll { $0 == chatId }
                draft.pinnedChatIds.removeAll { $0 == chatId }
                if !draft.excludedChatIds.contains(chatId) {
                    draft.excludedChatIds.append(chatId)
                }
            }
        }
    }

    private func removeChat(_ chatId: Int64, from target: ChatPickerTarget) {
        switch target {
        case .included:
            draft.includedChatIds.removeAll { $0 == chatId }
            draft.pinnedChatIds.removeAll { $0 == chatId }
        case .excluded:
            draft.excludedChatIds.removeAll { $0 == chatId }
        }
    }

    private func loadInitialDraft() async {
        errorMessage = nil
        activePicker = nil
        chatSearchQuery = ""

        if let folderId = request.folderId {
            isLoading = true
            let result = await appStore.chatList.loadFolderDraft(folderId: folderId)
            isLoading = false

            if let loaded = result.draft {
                draft = loaded
                for id in loaded.includedChatIds + loaded.pinnedChatIds + loaded.excludedChatIds {
                    appStore.chatList.ensureChatLoaded(chatId: id)
                }
            } else {
                draft = ChatFolderDraft(title: request.initialTitle)
                errorMessage = result.error ?? "无法加载文件夹详情"
            }
        } else {
            var initial = ChatFolderDraft.empty
            if let preselectedChatId = request.preselectedChatId {
                initial.includedChatIds = [preselectedChatId]
            }
            draft = initial
        }
    }

    private func submitSave() async {
        errorMessage = nil
        isSaving = true
        let error = await appStore.chatList.saveFolder(folderId: request.folderId, draft: draft)
        isSaving = false

        if let error {
            errorMessage = error
        } else {
            dismiss()
        }
    }
}
