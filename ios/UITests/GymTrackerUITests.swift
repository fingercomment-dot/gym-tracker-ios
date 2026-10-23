import XCTest

/// Runs the app on its test page (launch argument -GymDemo) in the simulator and photographs the native parts —
/// the tab bar, the workout list, the wheels, the press-and-hold menu. CI puts the pictures on the "ci-shots" release.
final class GymTrackerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-GymDemo"]
        app.launch()
    }

    private var web: XCUIElement { app.webViews.firstMatch }

    private func waitForPage() {
        XCTAssertTrue(web.waitForExistence(timeout: 40), "no web view")
        XCTAssertTrue(web.buttons["Вес"].waitForExistence(timeout: 30), "the test page did not load")
        sleep(1)
    }

    /// The tab bar and the workout list drawn by the app.
    func test1TabsAndWorkout() {
        waitForPage()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "no tab bar")
        shot("10-tabs")
        tabBar.buttons["Прогресс"].tap()
        sleep(1)
        shot("11-tab-progress")
        tabBar.buttons["Сегодня"].tap()
        sleep(1)

        web.buttons["Тренировка"].tap()
        let title = app.navigationBars["Верх A"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "the workout list did not come up")
        sleep(1)
        shot("12-workout")

        // «Свернуть»: the list goes away, the tab bar comes back; then into the workout again
        tapMinimize()
        sleep(1)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5), "minimise: the tab bar did not come back")
        shot("12a-minimized")
        web.buttons["Тренировка"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5), "the workout list did not come up again")
        sleep(1)

        // tick the first set off, like a reminder
        let tick = app.buttons["tick.0.0.0"]
        if tick.waitForExistence(timeout: 3) {
            tick.tap()
            sleep(1)
            shot("13-ticked")
        } else {
            XCTFail("no circle for the first set")
        }

        // the drums right under a set
        let row = app.buttons["set.0.0.1"]
        if row.waitForExistence(timeout: 3) {
            row.tap()
            sleep(1)
            shot("14-wheels")
            if app.pickerWheels.count > 0 {
                app.pickerWheels.element(boundBy: 0).swipeUp()
                sleep(2)
                shot("15-wheels-turned")
            }
            row.tap()
            sleep(1)
        } else {
            XCTFail("no row for the second set")
        }

        // open the bench and its drums (weight and reps)
        let bench = app.staticTexts["Жим штанги лёжа"]
        if bench.waitForExistence(timeout: 3) {
            bench.tap()
            sleep(1)
            let benchRow = app.buttons["set.1.0.0"]
            if benchRow.waitForExistence(timeout: 3) {
                benchRow.tap()
                sleep(1)
                app.swipeUp()
                sleep(1)
                shot("16-bench-wheels")
                if benchRow.isHittable { benchRow.tap() }
                app.swipeDown()
                sleep(1)
            }
        }

        // a sheet of the page over the app's list
        let info = app.buttons["info.0"]
        if info.waitForExistence(timeout: 3) {
            info.tap()
            sleep(1)
            shot("17-sheet-over-list")
            let close = web.buttons["Закрыть окно"]
            if close.waitForExistence(timeout: 3) { close.tap() }
            sleep(1)
        }

        app.swipeUp()
        sleep(1)
        shot("18-workout-bottom")
        let finish = app.buttons["workout.finish"]
        if finish.waitForExistence(timeout: 3) {
            finish.tap()
            sleep(1)
            shot("19-finish-ask")
            // on iOS 26 the question comes out of the button, without its own «cancel»: a tap outside closes it
            // (not in the status bar: a tap there doesn't reach the app)
            let cancel = app.buttons["Продолжить"]
            let outside = app.otherElements["PopoverDismissRegion"]
            if cancel.waitForExistence(timeout: 2) {
                cancel.tap()
            } else if outside.exists {
                outside.tap()
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
            }
            sleep(2)
            shot("19b-finish-closed")
        }

        tapMinimize()
        sleep(1)
        shot("20-minimized")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5), "the tab bar did not come back")
        XCTAssertEqual(app.state, .runningForeground, "the app is not running at the end")
    }

    /// The wheels' panel and the press-and-hold menu on the page.
    func test2WheelsAndMenu() {
        waitForPage()
        web.buttons["Вес"].tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 8), "the wheels did not come up")
        sleep(1)
        shot("01-weight-reps")
        XCTAssertEqual(app.state, .runningForeground, "the app went away after opening the wheels")

        web.buttons["Время"].tap()
        sleep(1)
        shot("03-time")
        let done = app.buttons["picker.done"]
        if done.waitForExistence(timeout: 3) { done.tap() }
        sleep(1)

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
                XCTAssertTrue(web.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "\"pick\":\"1\"")).firstMatch.waitForExistence(timeout: 3), "the pick did not reach the page")
            } else {
                XCTFail("the press-and-hold menu did not show")
            }
        }
        XCTAssertEqual(app.state, .runningForeground, "the app is not running at the end")
    }

    /// iOS 26 glass bar buttons give the test no point to tap: tap the middle of the button's frame.
    private func tapMinimize() {
        let minimize = app.buttons["workout.minimize"].firstMatch
        XCTAssertTrue(minimize.waitForExistence(timeout: 3), "no «Свернуть» button")
        if minimize.isHittable {
            minimize.tap()
        } else {
            let f = minimize.frame
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY)).tap()
        }
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
