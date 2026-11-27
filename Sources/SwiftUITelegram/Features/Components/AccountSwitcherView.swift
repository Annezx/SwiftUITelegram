import SwiftUI

/// Interactive sidebar footer button and popover allowing instant switching across
/// all concurrent Telegram accounts, viewing background unread counts, and adding new accounts.
struct AccountSwitcherView: View {
    @Environment(AppStore.self) private var appStore
    @State private var isShowingPopover: Bool = false

    private var active: AccountSession {
        appStore.activeAccount
    }

    var body: some View {
        Button {
            isShowingPopover.toggle()
        } label: {
            HStack(spacing: 9) {
                AvatarView(
                    title: active.displayName,
                    initials: active.avatarInitials,
                    accentSeed: active.accentColorId,
                    fileId: active.smallPhotoFileId,
                    knownLocalPath: active.smallPhotoLocalPath,
                    size: 30,
                    fileCache: active.fileCache
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(active.displayName)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let username = active.username, !username.isEmpty {
                        Text("@\(username)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if !active.phoneNumber.isEmpty {
                        Text("+\(active.phoneNumber)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                if appStore.otherAccountsUnreadCount > 0 {
                    Text(appStore.otherAccountsUnreadCount > 99 ? "99+" : "\(appStore.otherAccountsUnreadCount)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.accentColor, in: Capsule())
                        .help("其他账号有未读消息")
                }

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("切换或添加 Telegram 账号")
        .popover(isPresented: $isShowingPopover, arrowEdge: .top) {
            popoverContent
        }
    }

    private var popoverContent: some View {
        let accounts = appStore.persistedAccounts

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("账号列表")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(accounts.count) 个账号")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            Divider()

            VStack(spacing: 2) {
                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, session in
                    accountRow(session: session, index: index)
                }
            }

            Divider()

            Button {
                isShowingPopover = false
                appStore.beginAddingAccount()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)

                    Text("添加账号…")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)

                    Spacer()

                    Text("⇧⌘A")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .frame(width: 272)
    }

    private func accountRow(session: AccountSession, index: Int) -> some View {
        let isActive = session.id == appStore.activeAccountId

        return Button {
            isShowingPopover = false
            appStore.switchAccount(to: session.id)
        } label: {
            HStack(spacing: 9) {
                AvatarView(
                    title: session.displayName,
                    initials: session.avatarInitials,
                    accentSeed: session.accentColorId,
                    fileId: session.smallPhotoFileId,
                    knownLocalPath: session.smallPhotoLocalPath,
                    size: 30,
                    fileCache: session.fileCache
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.displayName)
                        .font(.callout.weight(isActive ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(accountSubtitle(for: session))
                        .font(.caption2)
                        .foregroundStyle(session.isReady ? Color.secondary : Color.orange)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if !isActive && session.isReady && session.unreadMessageCount > 0 {
                    Text(session.unreadMessageCount > 99 ? "99+" : "\(session.unreadMessageCount)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color.accentColor, in: Capsule())
                } else if isActive {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                } else if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isActive ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func accountSubtitle(for session: AccountSession) -> String {
        if !session.isReady {
            return session.authStep == .configuring ? "正在连接…" : "需要登录"
        }
        if let username = session.username, !username.isEmpty {
            return "@\(username)"
        }
        if !session.phoneNumber.isEmpty {
            return "+\(session.phoneNumber)"
        }
        return "在线"
    }
}
