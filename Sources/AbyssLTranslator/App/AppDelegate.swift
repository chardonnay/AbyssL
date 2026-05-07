import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    /// Captured from SwiftUI (`openWindow`) so Dock reopen can recreate the main window.
    var reopenMainWindow: (() -> Void)?

    private let hotkeyManager = HotkeyManager()
    private var captureShortcutObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        hotkeyManager.onCaptureShortcut = {
            PasteboardHelper.copyFrontmostSelectionToPasteboard { copiedText in
                self.activateMainWindow()
                NotificationCenter.default.post(name: .abysslTranslateSelection, object: copiedText)
            }
        }
        captureShortcutObserver = NotificationCenter.default.addObserver(
            forName: .abysslCaptureShortcutChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let shortcut = notification.object as? TranslationCaptureShortcut else { return }
            self?.hotkeyManager.update(shortcut: shortcut)
        }
        hotkeyManager.start()
    }

    func configure(settings: AppSettingsStore) {
        hotkeyManager.update(shortcut: settings.captureShortcut)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        activateMainWindow()
        return true
    }

    private func activateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if NSApp.windows.filter({ !$0.isSheet }).isEmpty {
            reopenMainWindow?()
        } else {
            for window in NSApp.windows where !window.isSheet {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    deinit {
        if let captureShortcutObserver {
            NotificationCenter.default.removeObserver(captureShortcutObserver)
        }
    }
}
