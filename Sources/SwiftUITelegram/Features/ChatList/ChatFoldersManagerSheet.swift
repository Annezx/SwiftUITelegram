import SwiftUI

/// Management sheet listing all custom Telegram chat folders with reordering, editing, creation, and deletion.
struct ChatFoldersManagerSheet: View {
    @Environment(AppStore.self) private var appStore
    @Environment(\.dismiss) private var dismiss

    @State private var editorRequest: ChatFolderEditorRequest?
    @State private var folderPendingDelete: ChatFolderItem?

    var body: some View {
        let folders = appStore.chatList.chatFolders

        VStack(spacing: 0) {
            headerSection

            Divider()

            if folders.isEmpty {
                ContentUnavailableView {
                    Label("还没有聊天文件夹", systemImage: "folder.badge.plus")
                } description: {
                    Text("创建文件夹将工作、群组、频道或未读对话分组展示，并与您的 Telegram 账号实时同步。")
                } actions: {
                    Button {
                        editorRequest = .create()
                    } label: {
                        Label("新建文件夹", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section("自定义文件夹 (\(folders.count))") {
                        ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                            folderRow(folder: folder, index: index, total: folders.count)
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            footerSection
        }
        .frame(width: 460, height: 460)
        .sheet(item: $editorRequest) { request in
            ChatFolderEditorSheet(request: request)
                .environment(appStore)
        }
        .confirmationDialog(
            deleteDialogTitle,
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
    }

    private var deleteDialogTitle: String {
        if let target = folderPendingDelete {
            return "确定要删除文件夹「\(target.title)」吗？"
        }
        return "确定要删除该文件夹吗？"
    }

    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("管理聊天文件夹")
                    .font(.headline)
                Text("新建、编辑、排序或删除文件夹（跨设备自动同步）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                editorRequest = .create()
            } label: {
                Label("新建", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func folderRow(folder: ChatFolderItem, index: Int, total: Int) -> some View {
        let unread = appStore.chatList.unreadCounts(for: folder.filter)
        let tint = ChatFolderColorPalette.color(for: folder.colorId) ?? Color.accentColor

        return HStack(spacing: 10) {
            Image(systemName: folder.sfSymbolName)
                .font(.body.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(folder.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    if folder.isShareable {
                        Image(systemName: "link")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help("可分享文件夹")
                    }

                    if unread.badgeCount > 0 {
                        Text("\(unread.badgeCount) 未读")
                            .font(.caption2.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                unread.hasUnmutedUnread ? Color.accentColor : Color.secondary.opacity(0.45),
                                in: Capsule()
                            )
                    }
                }

                if unread.totalChatCount > 0 {
                    Text("约 \(unread.totalChatCount) 个对话")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Button {
                    Task { await appStore.chatList.moveFolder(folderId: folder.id, offset: -1) }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(index == 0)
                .help("上移")

                Button {
                    Task { await appStore.chatList.moveFolder(folderId: folder.id, offset: 1) }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(index + 1 >= total)
                .help("下移")

                Button("编辑") {
                    editorRequest = .edit(folderId: folder.id, title: folder.title)
                }
                .controlSize(.small)

                Button(role: .destructive) {
                    folderPendingDelete = folder
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help("删除文件夹")
            }
        }
        .padding(.vertical, 4)
    }

    private var footerSection: some View {
        HStack {
            Text("右键点击侧边栏文件夹标签也可快速编辑或全部标为已读。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("完成") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
