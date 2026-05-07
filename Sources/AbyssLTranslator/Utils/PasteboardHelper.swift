import AppKit
import Carbon.HIToolbox

enum PasteboardHelper {
    /// Copies the current frontmost selection via a synthetic Command+C.
    /// Requires Accessibility permission for synthetic events.
    static func copyFrontmostSelectionToPasteboard() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    static func copyFrontmostSelectionToPasteboard(
        timeout: TimeInterval = 1.2,
        completion: @escaping (String?) -> Void
    ) {
        let pasteboard = NSPasteboard.general
        let initialChangeCount = pasteboard.changeCount
        copyFrontmostSelectionToPasteboard()
        waitForPasteboardStringChange(
            initialChangeCount: initialChangeCount,
            deadline: Date().addingTimeInterval(timeout),
            completion: completion
        )
    }

    static func stringFromPasteboard() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    static func setString(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private static func waitForPasteboardStringChange(
        initialChangeCount: Int,
        deadline: Date,
        completion: @escaping (String?) -> Void
    ) {
        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount != initialChangeCount {
            completion(pasteboard.string(forType: .string))
            return
        }

        guard Date() < deadline else {
            completion(pasteboard.string(forType: .string))
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            waitForPasteboardStringChange(
                initialChangeCount: initialChangeCount,
                deadline: deadline,
                completion: completion
            )
        }
    }
}
