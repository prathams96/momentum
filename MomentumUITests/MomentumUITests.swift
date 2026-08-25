import XCTest

final class MomentumUITests: XCTestCase {
    @MainActor
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launchArguments = ["-usePreviewStore"]
        app.launch()

        let getStarted = app.buttons["Get started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5))
        getStarted.tap()

        let examplePlan = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Start from the example plan")
        ).firstMatch
        XCTAssertTrue(examplePlan.waitForExistence(timeout: 5))
        examplePlan.tap()

        let nextButton = app.buttons["Keep Upper A next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 10))
        nextButton.tap()

        let startButton = app.buttons["Start with Upper A"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }
}
