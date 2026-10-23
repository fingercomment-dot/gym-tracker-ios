import XCTest

/// Runs the app on its test page (launch argument -GymDemo) in the simulator and photographs the native parts —
/// the tab bar, Today and Settings drawn from the web app's description, the workout list, the player bar,
/// the wheels, the press-and-hold menu. CI puts the pictures on the "ci-shots" release.
final class GymTrackerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-GymDemo"]
        app.launch()
    }

    private var web: XCUIElement { app.webViews.firstMatch }

    /// The test page opens on Calendar, a tab the page draws itself.
    private func waitForPage() {
        XCTAssertTrue(web.waitForExistence(timeout: 40), "no web view")
        XCTAssertTrue(web.buttons["Вес"].waitForExistence(timeout: 30), "the test page did not load")
        sleep(1)
    }

    private func element(beginningWith text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    /// iOS 26 glass bar buttons give the test no point to tap: tap the middle of the element's frame.
    private func tapFrame(_ element: XCUIElement) {
        guard element.exists else {
            XCTFail("nothing to tap: \(element)")
            return
        }
        if element.isHittable {
            element.tap()
        } else {
            let f = element.frame
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY)).tap()
        }
    }

    /// Today and Settings drawn by the app, the workout list, the player bar of a minimised workout.
    func test1TodayWorkoutSettings() {
        waitForPage()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "no tab bar")
        shot("10-calendar-page")

        // Today, drawn by the app
        tabBar.buttons["Сегодня"].tap()
        XCTAssertTrue(app.navigationBars["Сегодня"].waitForExistence(timeout: 8), "Today drawn by the app did not come up")
        sleep(1)
        shot("20-today")

        // the plan's fold: the exercises go and come back
        let fold = app.buttons["nv.fold.s:plan"]
        let firstExercise = app.buttons["nv.row.s:plan/ex:A1"]
        if fold.waitForExistence(timeout: 3) {
            XCTAssertTrue(firstExercise.exists, "no exercise rows on Today")
            fold.tap()
            sleep(1)
            XCTAssertFalse(firstExercise.exists, "the fold did not close the exercises")
            shot("21-today-folded")
            fold.tap()
            sleep(1)
            XCTAssertTrue(firstExercise.waitForExistence(timeout: 3), "the fold did not open the exercises again")
        } else {
            XCTFail("no fold on the exercises' section")
        }

        // press and drag an exercise below the next one (both in sight, above the tab bar)
        app.swipeUp()
        sleep(1)
        let nextExercise = app.buttons["nv.row.s:plan/ex:A2"]
        if firstExercise.exists, nextExercise.exists {
            let before = firstExercise.frame.minY
            firstExercise.press(forDuration: 1.2, thenDragTo: nextExercise, withVelocity: .slow, thenHoldForDuration: 0.6)
            sleep(2)
            shot("22-today-dragged")
            let after = app.buttons["nv.row.s:plan/ex:A1"].frame.minY
            XCTAssertGreaterThan(after, before + 10, "drag to reorder did not move the row (\(before) → \(after))")
        }
        app.swipeDown()
        sleep(1)

        // the weight sheet, drawn by the app: the wheels, then «Сохранить»
        let weight = app.buttons["nv.row.s:quick/q-weight"]
        if weight.waitForExistence(timeout: 3) {
            weight.tap()
            let sheetBar = app.navigationBars["Вес сегодня"]
            XCTAssertTrue(sheetBar.waitForExistence(timeout: 5), "the weight sheet did not come up")
            sleep(1)
            shot("23-weight-sheet")
            if app.pickerWheels.count > 0 {
                app.pickerWheels.element(boundBy: 0).swipeUp()
                sleep(2)
                shot("23b-weight-turned")
            }
            let save = sheetBar.buttons["Сохранить"]
            if save.exists { tapFrame(save) } else { app.swipeDown(velocity: .fast) }
            sleep(2)
            XCTAssertFalse(sheetBar.exists, "the weight sheet did not go away")
        } else {
            XCTFail("no weight row on Today")
        }

        // the second button's press-and-hold menu, the iPhone's own
        let second = app.buttons["nv.btn.s:hero/btns/Запланировать"]
        if second.waitForExistence(timeout: 3) {
            second.press(forDuration: 1.3)
            sleep(1)
            shot("24-hero-menu")
            let pick = element(beginningWith: "Как прошло?")
            if pick.waitForExistence(timeout: 3) {
                pick.tap()
                sleep(1)
                XCTAssertTrue(second.label.contains("Как прошло?"), "the pick did not change the button: \(second.label)")
            } else {
                XCTFail("the button's menu did not show")
            }
        } else {
            XCTFail("no second button on Today")
        }

        app.swipeUp()
        sleep(1)
        shot("25-today-bottom")
        app.swipeUp()
        sleep(1)
        shot("26-today-end")
        app.swipeDown()
        app.swipeDown()
        app.swipeDown()
        sleep(1)

        // start the workout from Today: the readiness questions first, in the app's sheet
        let start = app.buttons["nv.btn.s:hero/Начать тренировку"]
        if start.waitForExistence(timeout: 3) {
            start.tap()
            XCTAssertTrue(app.navigationBars["Как ты сегодня?"].waitForExistence(timeout: 5), "the readiness sheet did not come up")
            sleep(1)
            shot("27-checkin-sheet")
            app.swipeUp()
            sleep(1)
            shot("28-checkin-bottom")
            let go = app.buttons["nv.btn.foot0"]
            if go.waitForExistence(timeout: 3) { go.tap() } else { XCTFail("no start button at the bottom of the readiness sheet") }
        } else {
            XCTFail("no start button on Today")
        }
        let title = app.navigationBars["Верх A"]
        XCTAssertTrue(title.waitForExistence(timeout: 6), "the workout list did not come up")
        sleep(1)
        shot("30-workout")

        let tick = app.buttons["tick.0.0.0"]
        if tick.waitForExistence(timeout: 3) {
            tick.tap()
            sleep(1)
            shot("31-ticked")
        } else {
            XCTFail("no circle for the first set")
        }
        let row = app.buttons["set.0.0.1"]
        if row.waitForExistence(timeout: 3) {
            row.tap()
            sleep(1)
            shot("32-wheels")
            row.tap()
            sleep(1)
        }
        let info = app.buttons["info.0"]
        if info.waitForExistence(timeout: 3) {
            info.tap()
            sleep(1)
            shot("33-sheet-over-list")
            let close = web.buttons["Закрыть окно"]
            if close.waitForExistence(timeout: 3) { close.tap() }
            sleep(1)
        }

        // «Свернуть»: the list goes, Today and the player bar with the workout come up
        let minimize = app.buttons["workout.minimize"].firstMatch
        XCTAssertTrue(minimize.waitForExistence(timeout: 3), "no «Свернуть» button")
        tapFrame(minimize)
        sleep(2)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5), "minimise: the tab bar did not come back")
        let mini = app.buttons["mini.open"]
        XCTAssertTrue(mini.waitForExistence(timeout: 5), "no player bar with the minimised workout")
        shot("34-minimized-mini")
        if mini.exists {
            mini.tap()
            XCTAssertTrue(title.waitForExistence(timeout: 5), "the player bar did not open the workout")
            sleep(1)
            tapFrame(app.buttons["workout.minimize"].firstMatch)
            sleep(2)
        }

        // Settings, drawn by the app, with its pages
        app.tabBars.firstMatch.buttons["Настройки"].tap()
        XCTAssertTrue(app.navigationBars["Настройки"].waitForExistence(timeout: 6), "Settings drawn by the app did not come up")
        sleep(1)
        shot("40-settings")
        let look = element(beginningWith: "Оформление")
        if look.waitForExistence(timeout: 3) {
            look.tap()
            XCTAssertTrue(app.navigationBars["Оформление"].waitForExistence(timeout: 5), "Appearance did not open")
            sleep(1)
            shot("41-look")
            let green = app.buttons["Зелёный"]
            if green.waitForExistence(timeout: 3) {
                green.tap()
                sleep(1)
                shot("42-look-green")
            }
            // back with the back button (a glass button: tapped by its place)
            let back = app.navigationBars["Оформление"].buttons.firstMatch
            if back.exists { tapFrame(back) }
            XCTAssertTrue(app.navigationBars["Настройки"].waitForExistence(timeout: 5), "back did not return to Settings")
            sleep(1)
            shot("43-settings-back")
        } else {
            XCTFail("no Appearance row in Settings")
        }
        let program = element(beginningWith: "Программа")
        if program.waitForExistence(timeout: 3) {
            program.tap()
            XCTAssertTrue(app.navigationBars["Программа"].waitForExistence(timeout: 5), "Program did not open")
            sleep(1)
            shot("44-program")
        }

        // Calendar: the iPhone's month calendar with the workouts' marks; a day opens in the app's sheet
        app.tabBars.firstMatch.buttons["Календарь"].tap()
        XCTAssertTrue(app.navigationBars["Календарь"].waitForExistence(timeout: 6), "Calendar drawn by the app did not come up")
        sleep(2)
        shot("50-calendar")
        let day = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "15")).firstMatch
        if day.waitForExistence(timeout: 3) {
            day.tap()
            sleep(2)
            shot("51-day-sheet")
            let close = app.navigationBars.buttons["Закрыть"].firstMatch
            if close.exists { tapFrame(close) } else { app.swipeDown(velocity: .fast) }
            sleep(2)
        } else {
            XCTFail("no day 15 in the calendar")
        }
        app.swipeUp()
        sleep(1)
        shot("52-calendar-bottom")

        // Progress: Swift Charts
        app.tabBars.firstMatch.buttons["Прогресс"].tap()
        XCTAssertTrue(app.navigationBars["Прогресс"].waitForExistence(timeout: 6), "Progress drawn by the app did not come up")
        sleep(2)
        shot("60-progress")
        for i in 1...4 {
            app.swipeUp()
            sleep(1)
            shot("6\(i)-progress-more")
        }
        XCTAssertEqual(app.state, .runningForeground, "the app is not running at the end")
    }

    /// The wheels' panel and the press-and-hold menu on the page (Calendar: the page's own tab).
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
            let item = element(beginningWith: "Отправить Claude")
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

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
