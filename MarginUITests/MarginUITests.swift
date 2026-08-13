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

    let presentation = app.segmentedControls["Document presentation"]
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
