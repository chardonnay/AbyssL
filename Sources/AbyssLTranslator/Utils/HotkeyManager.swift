import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Detects a configured modifier + key pressed twice quickly.
final class HotkeyManager {
    private var monitor: Any?

    private var shortcut = TranslationCaptureShortcut.default
    private var lastMatchingKeyTime: Date?
    private let doubleTapWindow: TimeInterval = 0.45

    var onCaptureShortcut: (() -> Void)?

    func start() {
        requestAccessibilityTrustIfNeeded()
        stop()
        let mask: NSEvent.EventTypeMask = .keyDown

        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event: event)
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        lastMatchingKeyTime = nil
    }

    func update(shortcut: TranslationCaptureShortcut) {
        self.shortcut = shortcut
        lastMatchingKeyTime = nil
    }

    private func handle(event: NSEvent) {
        guard event.type == .keyDown else { return }
        guard event.charactersIgnoringModifiers?.lowercased() == shortcut.normalizedKey else { return }
        guard matchingModifierFlags(in: event) == shortcut.modifier.eventFlag else { return }

        let now = Date()
        if let previous = lastMatchingKeyTime, now.timeIntervalSince(previous) <= doubleTapWindow {
            lastMatchingKeyTime = nil
            DispatchQueue.main.async { [weak self] in
                self?.performCaptureAfterModifierRelease()
            }
        } else {
            lastMatchingKeyTime = now
        }
    }

    private func matchingModifierFlags(in event: NSEvent) -> NSEvent.ModifierFlags {
        let relevant: NSEvent.ModifierFlags = [.control, .option, .command, .shift]
        return event.modifierFlags.intersection(relevant)
    }

    private func requestAccessibilityTrustIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func performCaptureAfterModifierRelease(startedAt: Date = Date()) {
        if !currentFlagsContainShortcutModifier() {
            onCaptureShortcut?()
            return
        }

        guard Date().timeIntervalSince(startedAt) < 1.5 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.performCaptureAfterModifierRelease(startedAt: startedAt)
        }
    }

    private func currentFlagsContainShortcutModifier() -> Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(shortcut.modifier.cgEventFlag)
    }

    deinit {
        stop()
    }
}
