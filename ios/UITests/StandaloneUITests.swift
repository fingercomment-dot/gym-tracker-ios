import XCTest

final class StandaloneUITests: XCTestCase {
    func testBundledAppLaunchesWithoutClaude() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "Bundled app did not connect to native tabs")
        XCTAssertFalse(app.textFields["https://claude.ai/artifact/…"].exists)
        app.tabBars.buttons["Настройки"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Скопировать все данные")).firstMatch.waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
    }
}
