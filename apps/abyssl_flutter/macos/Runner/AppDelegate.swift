import Cocoa
import FlutterMacOS
import ApplicationServices
import Carbon.HIToolbox
import PDFKit

@main
class AppDelegate: FlutterAppDelegate {
  private var channel: FlutterMethodChannel?
  private var documentChannel: FlutterMethodChannel?
  private var monitor: Any?
  private var shortcutModifier = "control"
  private var shortcutKey = "c"
  private var lastMatchingKeyTime: Date?
  private let doubleTapWindow: TimeInterval = 0.45

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      configureChannels(for: controller)
    }
    foregroundMainWindow()
  }

  func configureChannels(for controller: FlutterViewController) {
    guard channel == nil || documentChannel == nil else { return }
    let channel = FlutterMethodChannel(
      name: "org.abyssl.translator/capture",
      binaryMessenger: controller.engine.binaryMessenger
    )
    if self.channel == nil {
      self.channel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        self?.handle(call: call, result: result)
      }
    }
    let documentChannel = FlutterMethodChannel(
      name: "org.abyssl.translator/document",
      binaryMessenger: controller.engine.binaryMessenger
    )
    if self.documentChannel == nil {
      self.documentChannel = documentChannel
      documentChannel.setMethodCallHandler { [weak self] call, result in
        self?.handleDocument(call: call, result: result)
      }
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  private func foregroundMainWindow() {
    DispatchQueue.main.async { [weak self] in
      NSApp.setActivationPolicy(.regular)
      self?.mainFlutterWindow?.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "platformStatus":
      result([
        "supported": true,
        "message": AXIsProcessTrusted()
          ? "macOS capture adapter is active."
          : "macOS requires Accessibility/Input Monitoring permission for global capture.",
        "sessionType": "macOS",
      ])
    case "configureCapture":
      if let args = call.arguments as? [String: Any] {
        shortcutModifier = (args["modifier"] as? String) ?? shortcutModifier
        shortcutKey = ((args["key"] as? String) ?? shortcutKey).lowercased()
      }
      result(nil)
    case "startCapture":
      requestAccessibilityTrustIfNeeded()
      startMonitor()
      result(nil)
    case "stopCapture":
      stopMonitor()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleDocument(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "extractPdfText":
      guard
        let args = call.arguments as? [String: Any],
        let path = args["path"] as? String
      else {
        result(FlutterError(code: "bad-arguments", message: "PDF path is missing.", details: nil))
        return
      }
      guard let pdf = PDFDocument(url: URL(fileURLWithPath: path)) else {
        result(FlutterError(code: "pdf-read-failed", message: "PDF could not be read.", details: nil))
        return
      }
      var chunks: [String] = []
      for index in 0 ..< pdf.pageCount {
        guard let page = pdf.page(at: index) else { continue }
        let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
          chunks.append(text)
        }
      }
      result(chunks.joined(separator: "\n\n"))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startMonitor() {
    stopMonitor()
    monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      self?.handle(event: event)
    }
  }

  private func stopMonitor() {
    if let monitor {
      NSEvent.removeMonitor(monitor)
      self.monitor = nil
    }
    lastMatchingKeyTime = nil
  }

  private func handle(event: NSEvent) {
    guard event.type == .keyDown else { return }
    guard event.charactersIgnoringModifiers?.lowercased() == shortcutKey else { return }
    guard matchingModifierFlags(in: event) == eventFlag(for: shortcutModifier) else { return }
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

  private func eventFlag(for modifier: String) -> NSEvent.ModifierFlags {
    switch modifier {
    case "option":
      return .option
    case "command":
      return .command
    case "shift":
      return .shift
    default:
      return .control
    }
  }

  private func cgFlag(for modifier: String) -> CGEventFlags {
    switch modifier {
    case "option":
      return .maskAlternate
    case "command":
      return .maskCommand
    case "shift":
      return .maskShift
    default:
      return .maskControl
    }
  }

  private func requestAccessibilityTrustIfNeeded() {
    guard !AXIsProcessTrusted() else { return }
    let options = [
      kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
    ] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }

  private func performCaptureAfterModifierRelease(startedAt: Date = Date()) {
    if !CGEventSource.flagsState(.combinedSessionState).contains(cgFlag(for: shortcutModifier)) {
      copyFrontmostSelectionToPasteboard { [weak self] copiedText in
        if let copiedText, !copiedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          NSApp.activate(ignoringOtherApps: true)
          self?.channel?.invokeMethod("captureText", arguments: copiedText)
        }
      }
      return
    }
    guard Date().timeIntervalSince(startedAt) < 1.5 else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
      self?.performCaptureAfterModifierRelease(startedAt: startedAt)
    }
  }

  private func copyFrontmostSelectionToPasteboard(
    timeout: TimeInterval = 1.2,
    completion: @escaping (String?) -> Void
  ) {
    let pasteboard = NSPasteboard.general
    let initialChangeCount = pasteboard.changeCount
    let src = CGEventSource(stateID: .combinedSessionState)
    let keyDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
    let keyUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
    keyDown?.flags = .maskCommand
    keyUp?.flags = .maskCommand
    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
    waitForPasteboardStringChange(
      initialChangeCount: initialChangeCount,
      deadline: Date().addingTimeInterval(timeout),
      completion: completion
    )
  }

  private func waitForPasteboardStringChange(
    initialChangeCount: Int,
    deadline: Date,
    completion: @escaping (String?) -> Void
  ) {
    let pasteboard = NSPasteboard.general
    if pasteboard.changeCount != initialChangeCount {
      completion(pasteboard.string(forType: .string))
      return
    }
    if Date() >= deadline {
      completion(nil)
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
      self?.waitForPasteboardStringChange(
        initialChangeCount: initialChangeCount,
        deadline: deadline,
        completion: completion
      )
    }
  }

  deinit {
    stopMonitor()
  }
}
