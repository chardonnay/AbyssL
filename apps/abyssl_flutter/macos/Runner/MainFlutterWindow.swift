import Cocoa
import FlutterMacOS

@MainActor
enum MainWindowFramePersistence {
  static let autosaveName = NSWindow.FrameAutosaveName("AbyssLMainWindow")
  static let defaultSize = NSSize(width: 1250, height: 763)
  static let minimumSize = NSSize(width: 736, height: 558)

  static func centeredDefaultFrame(in visibleFrame: NSRect) -> NSRect {
    let size = NSSize(
      width: min(defaultSize.width, visibleFrame.width),
      height: min(defaultSize.height, visibleFrame.height)
    )
    return NSRect(
      x: (visibleFrame.midX - size.width / 2).rounded(),
      y: (visibleFrame.midY - size.height / 2).rounded(),
      width: size.width,
      height: size.height
    )
  }

  static func isFrameReachable(_ frame: NSRect, within visibleFrames: [NSRect]) -> Bool {
    visibleFrames.contains { visibleFrame in
      let intersection = frame.intersection(visibleFrame)
      return intersection.width >= 160 && intersection.height >= 120
    }
  }

  @discardableResult
  static func configure(
    _ window: NSWindow,
    autosaveName requestedAutosaveName: NSWindow.FrameAutosaveName? = nil
  ) -> Bool {
    let resolvedAutosaveName = requestedAutosaveName ?? autosaveName
    window.minSize = minimumSize
    let restoredFrame = window.setFrameUsingName(resolvedAutosaveName)
    let visibleFrames = NSScreen.screens.map(\.visibleFrame)
    if !restoredFrame || !isFrameReachable(window.frame, within: visibleFrames),
       let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
      window.setFrame(centeredDefaultFrame(in: visibleFrame), display: true)
    }
    return window.setFrameAutosaveName(resolvedAutosaveName)
  }
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    super.awakeFromNib()

    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    if !MainWindowFramePersistence.configure(self) {
      NSLog("Unable to register the AbyssL main window frame autosave name.")
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
      NSLog("Unable to configure Flutter platform channels: NSApplication.shared.delegate is not AppDelegate.")
      assertionFailure("AppDelegate type mismatch; configureChannels(for:) could not be called.")
      return
    }
    appDelegate.configureChannels(for: flutterViewController)
  }
}
