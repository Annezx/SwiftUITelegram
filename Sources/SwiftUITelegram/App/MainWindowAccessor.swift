import AppKit
import SwiftUI

@MainActor
enum MainWindowFrameStore {
    static let frameDefaultsKey = "SwiftUITelegram.MainWindowFrame.v1"
    static let defaultSize = CGSize(width: 1120, height: 740)
    static let minimumSize = CGSize(width: 820, height: 540)
    static weak var mainWindow: NSWindow?

    static func initialDefaultSize() -> CGSize {
        guard let saved = savedFrame() else {
            return defaultSize
        }
        let clamped = clampedFrame(saved)
        return CGSize(width: clamped.width, height: clamped.height)
    }

    static func savedFrame() -> NSRect? {
        guard let raw = UserDefaults.standard.string(forKey: frameDefaultsKey), !raw.isEmpty else {
            return nil
        }
        let rect = NSRectFromString(raw)
        guard rect.width >= minimumSize.width, rect.height >= minimumSize.height else {
            return nil
        }
        return rect
    }

    @MainActor
    static func saveFrame(for window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen) else { return }
        let frame = window.frame
        guard frame.width >= minimumSize.width, frame.height >= minimumSize.height else { return }
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: frameDefaultsKey)
    }

    static func clampedFrame(_ frame: NSRect) -> NSRect {
        let screens = NSScreen.screens
        let targetScreen = screens.first(where: { $0.visibleFrame.intersects(frame) })
            ?? NSScreen.main
            ?? screens.first

        guard let visible = targetScreen?.visibleFrame else {
            return NSRect(
                x: frame.origin.x,
                y: frame.origin.y,
                width: max(frame.width, minimumSize.width),
                height: max(frame.height, minimumSize.height)
            )
        }

        let width = min(max(frame.width, minimumSize.width), visible.width)
        let height = min(max(frame.height, minimumSize.height), visible.height)

        var originX = frame.origin.x
        var originY = frame.origin.y

        if originX + width > visible.maxX {
            originX = visible.maxX - width
        }
        if originX < visible.minX {
            originX = visible.minX
        }
        if originY + height > visible.maxY {
            originY = visible.maxY - height
        }
        if originY < visible.minY {
            originY = visible.minY
        }

        return NSRect(x: originX, y: originY, width: width, height: height)
    }
}

/// Configures the hosting macOS `NSWindow` so standard traffic-light controls stay visible
/// without a redundant titlebar/toolbar above the split view, and persists/restores window size & position.
struct MainWindowAccessor: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MainWindowHostView {
        let view = MainWindowHostView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: MainWindowHostView, context: Context) {
        if let window = nsView.window {
            context.coordinator.configureChrome(for: window)
        }
    }

    @MainActor
    final class Coordinator {
        private weak var attachedWindow: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var hasRestoredFrame = false
        private var isRestoringFrame = false

        func attach(to window: NSWindow?) {
            guard attachedWindow !== window else {
                if let window {
                    configureChrome(for: window)
                }
                return
            }

            removeObservers()
            attachedWindow = window

            guard let window else { return }

            MainWindowFrameStore.mainWindow = window
            configureChrome(for: window)
            restoreSavedFrameIfNeeded(for: window)
            installObservers(for: window)
        }

        func configureChrome(for window: NSWindow) {
            if !window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.insert(.fullSizeContentView)
            }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            if window.toolbar != nil {
                window.toolbar = nil
            }
            window.minSize = NSSize(
                width: MainWindowFrameStore.minimumSize.width,
                height: MainWindowFrameStore.minimumSize.height
            )

            window.standardWindowButton(.closeButton)?.isHidden = false
            window.standardWindowButton(.miniaturizeButton)?.isHidden = false
            window.standardWindowButton(.zoomButton)?.isHidden = false
        }

        private func restoreSavedFrameIfNeeded(for window: NSWindow) {
            guard !hasRestoredFrame else { return }
            hasRestoredFrame = true

            guard let saved = MainWindowFrameStore.savedFrame() else { return }
            let target = MainWindowFrameStore.clampedFrame(saved)

            isRestoringFrame = true
            window.setFrame(target, display: true)

            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                self.configureChrome(for: window)
                if !window.styleMask.contains(.fullScreen) {
                    window.setFrame(target, display: true)
                }
                self.isRestoringFrame = false
            }
        }

        private func installObservers(for window: NSWindow) {
            let center = NotificationCenter.default
            let names: [Notification.Name] = [
                NSWindow.didResizeNotification,
                NSWindow.didEndLiveResizeNotification,
                NSWindow.didMoveNotification,
                NSWindow.willCloseNotification,
            ]

            observers = names.map { name in
                center.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] _ in
                    Task { @MainActor [weak self, weak window] in
                        guard let self, let window, !self.isRestoringFrame else { return }
                        MainWindowFrameStore.saveFrame(for: window)
                    }
                }
            }
        }

        private func removeObservers() {
            let center = NotificationCenter.default
            for observer in observers {
                center.removeObserver(observer)
            }
            observers.removeAll()
        }
    }
}

final class MainWindowHostView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            onWindowChange?(nil)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
