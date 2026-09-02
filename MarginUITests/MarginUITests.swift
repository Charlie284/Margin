import XCTest

final class MarginUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testPresentationControlsSwitchModes() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))

    // DocumentGroup opens its browser when no recent document exists. Create a known document so
    // this test owns the state that exposes the presentation controls.
    app.typeKey("n", modifierFlags: .command)

    // SwiftUI exposes a segmented Picker as an XCUI radio group on macOS.
    let presentation = app.radioGroups["Document presentation"]
    XCTAssertTrue(presentation.waitForExistence(timeout: 8))

    let read = presentation.radioButtons["Read"]
    let split = presentation.radioButtons["Split"]
    let write = presentation.radioButtons["Write"]
    XCTAssertTrue(read.exists)
    XCTAssertTrue(split.exists)
    XCTAssertTrue(write.exists)

    read.click()
    XCTAssertTrue(read.isSelected)
    split.click()
    XCTAssertTrue(split.isSelected)
    write.click()
    XCTAssertTrue(write.isSelected)
  }
}
