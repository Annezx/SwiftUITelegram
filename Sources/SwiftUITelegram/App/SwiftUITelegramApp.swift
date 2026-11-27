import SwiftUI

@main
struct SwiftUITelegramApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appStore = AppStore()

    var body: some Scene {
        let initialSize = MainWindowFrameStore.initialDefaultSize()

        WindowGroup("SwiftUITelegram") {
            RootView()
                .environment(appStore)
                .frame(
                    minWidth: MainWindowFrameStore.minimumSize.width,
                    minHeight: MainWindowFrameStore.minimumSize.height
                )
                .task {
                    appDelegate.appStore = appStore
                    appStore.bootstrap()
                }
                .ignoresSafeArea(.all, edges: .top)
        }
        .defaultSize(width: initialSize.width, height: initialSize.height)
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

                Divider()

                Button("上一个文件夹") {
                    appStore.chatList.selectPreviousTab()
                }
                .keyboardShortcut("[", modifiers: [.command, .option])
                .disabled(appStore.authStep != .ready)

                Button("下一个文件夹") {
                    appStore.chatList.selectNextTab()
                }
                .keyboardShortcut("]", modifiers: [.command, .option])
                .disabled(appStore.authStep != .ready)

                Divider()

                Button("新建文件夹…") {
                    appStore.triggerCreateFolder()
                }
                .disabled(appStore.authStep != .ready)

                Button("管理文件夹…") {
                    appStore.triggerManageFolders()
                }
                .disabled(appStore.authStep != .ready)
            }
        }

        Settings {
            SettingsView()
                .environment(appStore)
        }
    }
}
