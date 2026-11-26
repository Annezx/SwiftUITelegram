import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var appStore
    @State private var showLogoutConfirm = false

    var body: some View {
        TabView {
            accountTab
                .tabItem {
                    Label("账号", systemImage: "person.crop.circle")
                }

            storageTab
                .tabItem {
                    Label("API 与存储", systemImage: "externaldrive")
                }
        }
        .frame(width: 480, height: 330)
        .padding()
        .confirmationDialog(
            "确定要退出当前 Telegram 账号吗？",
            isPresented: $showLogoutConfirm,
            titleVisibility: .visible
        ) {
            Button("退出登录", role: .destructive) {
                Task { await appStore.logOut() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("退出后需要重新通过手机号或二维码登录。")
        }
    }

    private var accountTab: some View {
        Form {
            if let user = appStore.currentUser {
                HStack(spacing: 14) {
                    AvatarView(
                        title: user.displayName,
                        initials: String(user.displayName.prefix(2)).uppercased(),
                        accentSeed: Int(user.id % 7),
                        fileId: user.smallPhotoFileId,
                        knownLocalPath: user.smallPhotoLocalPath,
                        size: 52
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.displayName)
                            .font(.headline)
                        if let username = user.username {
                            Text("@\(username)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        if !user.phoneNumber.isEmpty {
                            Text("+\(user.phoneNumber)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.vertical, 6)

                Button("退出登录", role: .destructive) {
                    showLogoutConfirm = true
                }
            } else {
                Text("当前尚未登录 Telegram 账号。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var storageTab: some View {
        Form {
            LabeledContent("API ID") {
                Text(appStore.credentials.map { String($0.apiId) } ?? "未配置")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            LabeledContent("TDLib 数据库目录") {
                Button("在 Finder 中显示") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: AppConfiguration.tdlibDatabaseDirectory)
                }
            }

            LabeledContent("TDLib 媒体文件目录") {
                Button("在 Finder 中显示") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: AppConfiguration.tdlibFilesDirectory)
                }
            }

            LabeledContent("临时媒体缓存") {
                Button("清理预览与转码缓存") {
                    appStore.audioPlayer.stop()
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
