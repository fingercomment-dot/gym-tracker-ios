import XCTest

/// Runs the app on its test page (launch argument -GymDemo) in the simulator and photographs the native parts —
/// the wheels' panel and the press-and-hold menu. CI puts the pictures on the "ci-shots" release.
final class GymTrackerUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    func testWheelsAndMenu() {
        let app = XCUIApplication()
        app.launchArguments = ["-GymDemo"]
        app.launch()

        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 40), "no web view")
        let weight = web.buttons["Вес"]
        XCTAssertTrue(weight.waitForExistence(timeout: 30), "the test page did not load")
        sleep(1)
        shot("00-page")

        // the wheels for weight and reps
        weight.tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 8), "the wheels did not come up")
        sleep(1)
        shot("01-weight-reps")
        XCTAssertEqual(app.state, .runningForeground, "the app went away after opening the wheels")

        if app.pickerWheels.count > 1 {
            app.pickerWheels.element(boundBy: 0).swipeUp()
            app.pickerWheels.element(boundBy: 1).swipeDown()
            sleep(2)
            shot("02-turned")
        }

        // other columns in the same panel: time
        web.buttons["Время"].tap()
        sleep(1)
        shot("03-time")

        let done = app.buttons["picker.done"]
        if done.waitForExistence(timeout: 3) { done.tap() }
        sleep(1)
        shot("04-closed")

        // the button with a menu: press and hold
        let hold = web.buttons["Запланировать"]
        if hold.waitForExistence(timeout: 5) {
            hold.press(forDuration: 1.6)
            sleep(1)
            shot("05-menu")
            // a menu item's label is its title and its subtitle
            let item = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Отправить Claude")).firstMatch
            if item.waitForExistence(timeout: 4) {
                item.tap()
                sleep(1)
                shot("06-picked")
                // the page heard the pick
                XCTAssertTrue(web.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "\"pick\":\"1\"")).firstMatch.waitForExistence(timeout: 3), "the pick did not reach the page")
            } else {
                XCTFail("the press-and-hold menu did not show")
            }
        }
        XCTAssertEqual(app.state, .runningForeground, "the app is not running at the end")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
