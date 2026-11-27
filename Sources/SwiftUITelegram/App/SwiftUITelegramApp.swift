import SwiftUI

@main
struct SwiftUITelegramApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appStore = AppStore()

    var body: some Scene {
        WindowGroup("SwiftUITelegram") {
            RootView()
                .environment(appStore)
                .frame(minWidth: 820, minHeight: 540)
                .task {
                    appDelegate.appStore = appStore
                    appStore.bootstrap()
                }
        }
        .defaultSize(width: 1120, height: 740)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("账号") {
                ForEach(Array(appStore.persistedAccounts.prefix(9).enumerated()), id: \.element.id) { index, session in
                    Button(session.id == appStore.activeAccountId ? "✓ \(session.displayName)" : session.displayName) {
                        appStore.switchAccount(to: session.id)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command])
                }

                Divider()

                Button("添加账号…") {
                    appStore.beginAddingAccount()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(appStore.readyAccounts.isEmpty)
            }

            CommandMenu("对话") {
                Button("搜索对话") {
                    appStore.triggerSearchFocus()
                }
                .keyboardShortcut("k", modifiers: [.command])
                .disabled(appStore.authStep != .ready)

                Button("刷新会话列表") {
                    Task {
                        await appStore.chatList.refreshCurrentList()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(appStore.authStep != .ready)
            }
        }

        Settings {
            SettingsView()
                .environment(appStore)
        }
    }
}
