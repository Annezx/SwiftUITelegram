import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var appStore
    @Environment(\.dismiss) private var dismiss
    @State private var accountPendingLogout: AccountSession?

    var body: some View {
        TabView {
            accountTab
                .tabItem {
                    Label("账号", systemImage: "person.2.circle")
                }

            storageTab
                .tabItem {
                    Label("API 与存储", systemImage: "externaldrive")
                }
        }
        .frame(width: 520, height: 390)
        .padding()
        .confirmationDialog(
            logoutDialogTitle,
            isPresented: Binding(
                get: { accountPendingLogout != nil },
                set: { if !$0 { accountPendingLogout = nil } }
            ),
            titleVisibility: .visible,
            presenting: accountPendingLogout
        ) { target in
            Button(target.isReady ? "退出登录" : "移除账号", role: .destructive) {
                accountPendingLogout = nil
                Task { await appStore.logOut(accountId: target.id) }
            }
            Button("取消", role: .cancel) {
                accountPendingLogout = nil
            }
        } message: { target in
            if appStore.persistedAccounts.count > 1 {
                Text("将退出账号「\(target.displayName)」并清理该账号本地缓存，其他已登录账号不受影响。")
            } else {
                Text("退出后需要重新通过手机号或二维码登录。")
            }
        }
    }

    private var logoutDialogTitle: String {
        if let target = accountPendingLogout {
            return target.isReady
                ? "确定要退出账号「\(target.displayName)」吗？"
                : "确定要移除账号「\(target.displayName)」吗？"
        }
        return "确定要退出当前 Telegram 账号吗？"
    }

    private var accountTab: some View {
        let accounts = appStore.persistedAccounts

        return Form {
            Section("已配置账号 (\(accounts.count))") {
                ForEach(accounts) { session in
                    accountManagementRow(session)
                }
            }

            Section {
                Button {
                    appStore.beginAddingAccount()
                    dismiss()
                    NSApp.activate()
                } label: {
                    Label("添加新 Telegram 账号…", systemImage: "person.crop.circle.badge.plus")
                }
                .disabled(appStore.readyAccounts.isEmpty)
            }
        }
        .formStyle(.grouped)
    }

    private func accountManagementRow(_ session: AccountSession) -> some View {
        let isActive = session.id == appStore.activeAccountId

        return HStack(spacing: 12) {
            AvatarView(
                title: session.displayName,
                initials: session.avatarInitials,
                accentSeed: session.accentColorId,
                fileId: session.smallPhotoFileId,
                knownLocalPath: session.smallPhotoLocalPath,
                size: 38,
                fileCache: session.fileCache
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.displayName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    if isActive {
                        Text("当前")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                    } else if session.isReady && session.unreadMessageCount > 0 {
                        Text("\(session.unreadMessageCount) 条未读")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if !session.isReady {
                        Text("未登录")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 8) {
                    if let username = session.username, !username.isEmpty {
                        Text("@\(username)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !session.phoneNumber.isEmpty {
                        Text("+\(session.phoneNumber)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 8)

            if !isActive {
                Button("切换") {
                    appStore.switchAccount(to: session.id)
                }
                .controlSize(.small)
            }

            if session.isReady || appStore.persistedAccounts.count > 1 {
                Button(session.isReady ? "退出" : "移除", role: .destructive) {
                    accountPendingLogout = session
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    private var storageTab: some View {
        Form {
            LabeledContent("API ID") {
                Text(appStore.credentials.map { String($0.apiId) } ?? "未配置")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            LabeledContent("当前账号") {
                Text(appStore.activeAccount.displayName)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("当前账号数据库目录") {
                Button("在 Finder 中显示") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: appStore.activeAccount.databaseDirectory)
                }
            }

            LabeledContent("当前账号媒体文件目录") {
                Button("在 Finder 中显示") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: appStore.activeAccount.filesDirectory)
                }
            }

            LabeledContent("临时媒体缓存") {
                Button("清理预览与转码缓存") {
                    appStore.audioPlayer.stop()
                    TGSStickerCache.shared.clear()
                    WebMStickerCache.shared.clear()
                    AppConfiguration.clearMediaCache()
                }
            }

            LabeledContent("本地凭证") {
                Button("清除本地保存的 API 凭证") {
                    appStore.clearSavedCredentials()
                }
            }
        }
        .formStyle(.grouped)
    }
}
