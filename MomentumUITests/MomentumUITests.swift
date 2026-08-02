import XCTest

final class MomentumUITests: XCTestCase {
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launchArguments = ["-usePreviewStore"]
        app.launch()

        let startButton = app.buttons["Start with Upper A"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }
}
