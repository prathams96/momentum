import XCTest

final class MomentumUITests: XCTestCase {
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launchArguments = ["-usePreviewStore"]
        app.launch()

        let planButton = app.buttons["See the plan"]
        XCTAssertTrue(planButton.waitForExistence(timeout: 5))
        planButton.tap()

        let nextButton = app.buttons["Keep Upper A next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap()

        let startButton = app.buttons["Start with Upper A"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }
}
