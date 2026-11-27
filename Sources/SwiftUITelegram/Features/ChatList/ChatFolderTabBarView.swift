import SwiftUI

/// Maps TDLib's 0...6 chat folder color IDs to SwiftUI colors matching Telegram's palette.
enum ChatFolderColorPalette {
    private static let colors: [Color] = [
        Color(red: 0.90, green: 0.31, blue: 0.30), // 0: Red
        Color(red: 0.92, green: 0.54, blue: 0.18), // 1: Orange
        Color(red: 0.52, green: 0.39, blue: 0.88), // 2: Violet
        Color(red: 0.24, green: 0.70, blue: 0.39), // 3: Green
        Color(red: 0.18, green: 0.64, blue: 0.78), // 4: Cyan
        Color(red: 0.22, green: 0.52, blue: 0.90), // 5: Blue
        Color(red: 0.86, green: 0.34, blue: 0.60)  // 6: Pink
    ]

    static func color(for colorId: Int) -> Color? {
        guard colorId >= 0 else { return nil }
        return colors[colorId % colors.count]
    }
}

/// Horizontal scrollable folder tab strip for switching between All Chats, custom TDLib folders
/// (`ChatListFolder`), and Archived chats, with live per-list unread counts and quick actions.
struct ChatFolderTabBarView: View {
    let tabs: [ChatListTabItem]
    let selectedFilter: ChatListFilter
    let unreadProvider: (ChatListFilter) -> ChatListUnreadCounts
    let folderOrderIndex: (Int) -> Int?
    let customFolderCount: Int
    let onSelect: (ChatListFilter) -> Void
    let onMarkAllRead: (ChatListFilter) -> Void
    let onRefresh: (ChatListFilter) -> Void
    let onCreateFolder: () -> Void
    let onEditFolder: (Int) -> Void
    let onMoveFolder: (Int, Int) -> Void
    let onRequestDeleteFolder: (Int) -> Void
    let onManageFolders: () -> Void

    @Namespace private var activeTabNamespace
    @State private var hoveredTabId: String?

    var body: some View {
        HStack(spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(tabs) { tab in
                            tabButton(for: tab)
                                .id(tab.id)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .onChange(of: selectedFilter) { _, newFilter in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newFilter.id, anchor: .center)
                    }
                }
            }

            folderActionsMenu
        }
    }

    private func tabButton(for tab: ChatListTabItem) -> some View {
        let isSelected = tab.filter == selectedFilter
        let isHovered = hoveredTabId == tab.id
        let unread = unreadProvider(tab.filter)

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                onSelect(tab.filter)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tab.sfSymbolName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))

                Text(tab.title)
                    .font(.caption.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if unread.badgeCount > 0 {
                    Text(unread.badgeCount > 99 ? "99+" : "\(unread.badgeCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            unread.hasUnmutedUnread
                                ? Color.accentColor
                                : Color.secondary.opacity(0.45),
                            in: Capsule()
                        )
                }
            }
            .foregroundStyle(isSelected ? Color.accentColor : (isHovered ? Color.primary : Color.secondary))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.accentColor.opacity(0.16))
                        .matchedGeometryEffect(id: "activeFolderTab", in: activeTabNamespace)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredTabId = tab.id
            } else if hoveredTabId == tab.id {
                hoveredTabId = nil
            }
        }
        .help(tabTooltip(for: tab, unread: unread))
        .contextMenu {
            tabContextMenu(for: tab, unread: unread)
        }
    }

    @ViewBuilder
    private func tabContextMenu(for tab: ChatListTabItem, unread: ChatListUnreadCounts) -> some View {
        if unread.badgeCount > 0 {
            Button {
                onMarkAllRead(tab.filter)
            } label: {
                Label("全部标为已读", systemImage: "envelope.open")
            }
        }

        Button {
            onRefresh(tab.filter)
        } label: {
            Label("刷新列表", systemImage: "arrow.clockwise")
        }

        if case .folder(let folderId) = tab.filter {
            Divider()

            Button {
                onEditFolder(folderId)
            } label: {
                Label("编辑文件夹…", systemImage: "pencil")
            }

            if let index = folderOrderIndex(folderId) {
                if index > 0 {
                    Button {
                        onMoveFolder(folderId, -1)
                    } label: {
                        Label("向左移动", systemImage: "arrow.left")
                    }
                }

                if index + 1 < customFolderCount {
                    Button {
                        onMoveFolder(folderId, 1)
                    } label: {
                        Label("向右移动", systemImage: "arrow.right")
                    }
                }
            }

            Button(role: .destructive) {
                onRequestDeleteFolder(folderId)
            } label: {
                Label("删除文件夹…", systemImage: "trash")
            }
        }

        Divider()

        Button {
            onCreateFolder()
        } label: {
            Label("新建文件夹…", systemImage: "folder.badge.plus")
        }

        Button {
            onManageFolders()
        } label: {
            Label("管理文件夹…", systemImage: "slider.horizontal.3")
        }
    }

    private var folderActionsMenu: some View {
        Menu {
            ForEach(tabs) { tab in
                let isSelected = tab.filter == selectedFilter
                let unread = unreadProvider(tab.filter)
                let badgeSuffix = unread.badgeCount > 0 ? " (\(unread.badgeCount))" : ""
                let title = (isSelected ? "✓ " : "") + tab.menuTitle + badgeSuffix

                Button {
                    onSelect(tab.filter)
                } label: {
                    Label(title, systemImage: tab.sfSymbolName)
                }
            }

            Divider()

            Button {
                onCreateFolder()
            } label: {
                Label("新建文件夹…", systemImage: "folder.badge.plus")
            }

            Button {
                onManageFolders()
            } label: {
                Label("管理文件夹…", systemImage: "slider.horizontal.3")
            }
        } label: {
            Image(systemName: customFolderCount > 0 ? "folder.badge.gearshape" : "folder.badge.plus")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("切换或管理聊天文件夹")
    }

    private func tabTooltip(for tab: ChatListTabItem, unread: ChatListUnreadCounts) -> String {
        if unread.badgeCount > 0 {
            return "\(tab.menuTitle)（\(unread.badgeCount) 个未读对话）"
        }
        return tab.menuTitle
    }
}
