import Cocoa
import FlutterMacOS
import XCTest
@testable import abyssl_flutter

@MainActor
final class RunnerTests: XCTestCase {
  func testDefaultFrameIsCenteredAtExpectedSize() {
    let visibleFrame = NSRect(x: 0, y: 0, width: 1600, height: 1000)

    let frame = MainWindowFramePersistence.centeredDefaultFrame(in: visibleFrame)

    XCTAssertEqual(frame.size.width, 1250, accuracy: 0.5)
    XCTAssertEqual(frame.size.height, 763, accuracy: 0.5)
    XCTAssertEqual(frame.midX, visibleFrame.midX, accuracy: 0.5)
    XCTAssertEqual(frame.midY, visibleFrame.midY, accuracy: 0.5)
  }

  func testDefaultFrameSupportsNegativeScreenOrigins() {
    let visibleFrame = NSRect(x: -1920, y: 24, width: 1920, height: 1056)

    let frame = MainWindowFramePersistence.centeredDefaultFrame(in: visibleFrame)

    XCTAssertEqual(frame.midX, visibleFrame.midX, accuracy: 0.5)
    XCTAssertEqual(frame.midY, visibleFrame.midY, accuracy: 0.5)
    XCTAssertTrue(visibleFrame.contains(frame))
  }

  func testDefaultFrameFitsInsideSmallVisibleFrame() {
    let visibleFrame = NSRect(x: 40, y: 30, width: 1024, height: 700)

    let frame = MainWindowFramePersistence.centeredDefaultFrame(in: visibleFrame)

    XCTAssertEqual(frame, visibleFrame.integral)
  }

  func testReachabilityRequiresUsefulVisibleWindowArea() {
    let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)

    XCTAssertTrue(
      MainWindowFramePersistence.isFrameReachable(
        NSRect(x: 100, y: 100, width: 1000, height: 700),
        within: [visibleFrame]
      )
    )
    XCTAssertFalse(
      MainWindowFramePersistence.isFrameReachable(
        NSRect(x: 1400, y: 850, width: 1000, height: 700),
        within: [visibleFrame]
      )
    )
  }

  func testAutosavedFrameRoundTrip() throws {
    guard let visibleFrame = NSScreen.main?.visibleFrame else {
      throw XCTSkip("A screen is required for the AppKit frame round-trip test.")
    }
    let name = NSWindow.FrameAutosaveName("AbyssLMainWindowTests-\(UUID().uuidString)")
    defer { NSWindow.removeFrame(usingName: name) }
    let width = min(900, visibleFrame.width)
    let height = min(650, visibleFrame.height)
    let expectedFrame = NSRect(
      x: visibleFrame.midX - width / 2,
      y: visibleFrame.midY - height / 2,
      width: width,
      height: height
    ).integral
    let style: NSWindow.StyleMask = [.titled, .closable, .resizable]
    let source = NSWindow(
      contentRect: expectedFrame,
      styleMask: style,
      backing: .buffered,
      defer: false
    )
    source.setFrame(expectedFrame, display: false)
    source.saveFrame(usingName: name)

    let restored = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: style,
      backing: .buffered,
      defer: false
    )
    XCTAssertTrue(
      MainWindowFramePersistence.configure(restored, autosaveName: name)
    )
    XCTAssertEqual(restored.frame.origin.x, expectedFrame.origin.x, accuracy: 1)
    XCTAssertEqual(restored.frame.origin.y, expectedFrame.origin.y, accuracy: 1)
    XCTAssertEqual(restored.frame.width, expectedFrame.width, accuracy: 1)
    XCTAssertEqual(restored.frame.height, expectedFrame.height, accuracy: 1)
  }

  func testSparkleConfigurationUsesSignedManualUpdateChecks() throws {
    let info = try XCTUnwrap(Bundle.main.infoDictionary)

    XCTAssertEqual(info["CFBundleDisplayName"] as? String, "AbyssL")
    XCTAssertEqual(
      info["SUFeedURL"] as? String,
      "https://github.com/chardonnay/AbyssL/releases/latest/download/appcast.xml"
    )
    XCTAssertEqual(
      info["SUPublicEDKey"] as? String,
      "06IgND/9JcSxBjHLec/lmoeKc2tqs3BLUtl5ExOdxPk="
    )
    XCTAssertEqual(info["SUEnableInstallerLauncherService"] as? Bool, true)
    XCTAssertEqual(info["SUEnableAutomaticChecks"] as? Bool, false)
    XCTAssertEqual(info["SUAllowsAutomaticUpdates"] as? Bool, true)
    XCTAssertEqual(info["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
  }
}
