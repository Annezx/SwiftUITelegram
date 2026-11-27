import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appStore: AppStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensures proper window focus and Dock icon even when launched directly via SwiftPM.
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let mainWindow = MainWindowFrameStore.mainWindow {
            MainWindowFrameStore.saveFrame(for: mainWindow)
        }
        appStore?.shutdown()
    }
}
