import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    super.awakeFromNib()

    let flutterViewController = FlutterViewController()
    var windowFrame = self.frame
    windowFrame.size = NSSize(width: 1250, height: 763)
    if let visibleFrame = self.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
      windowFrame.origin.x = visibleFrame.midX - windowFrame.width / 2
      windowFrame.origin.y = visibleFrame.midY - windowFrame.height / 2
    }
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
      NSLog("Unable to configure Flutter platform channels: NSApplication.shared.delegate is not AppDelegate.")
      assertionFailure("AppDelegate type mismatch; configureChannels(for:) could not be called.")
      return
    }
    appDelegate.configureChannels(for: flutterViewController)
  }
}
