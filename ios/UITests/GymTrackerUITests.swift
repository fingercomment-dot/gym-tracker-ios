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

        // «Изменить»: the iPhone's handles; drag the first exercise below the next one.
        // A slow drag scrolls by a known amount (a swipe may fling «Изменить» under the bar).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.52)), withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(1)
        let edit = app.buttons["nv.edit.s:plan"]
        let nextExercise = app.buttons["nv.row.s:plan/ex:A2"]
        if edit.waitForExistence(timeout: 3), firstExercise.exists, nextExercise.exists {
            edit.tap()
            sleep(1)
            shot("22a-today-edit")
            // the simulator's synthetic drag on the handle sometimes doesn't take (same code, same screen):
            // up to three tries; moved = the first exercise is now below the second (not just «somewhere else»,
            // which a scroll would give too)
            let handleX = app.frame.width - 44
            let origin = app.coordinate(withNormalizedOffset: .zero)
            var moved = false
            for attempt in 1...3 where !moved {
                let start = origin.withOffset(CGVector(dx: handleX, dy: firstExercise.frame.midY))
                let end = origin.withOffset(CGVector(dx: handleX, dy: nextExercise.frame.maxY + 8))
                start.press(forDuration: attempt == 1 ? 0.5 : 0.9, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.4)
                sleep(2)
                moved = firstExercise.frame.minY > nextExercise.frame.minY
                if !moved { print("reorder: try \(attempt) did not take") }
            }
            shot("22-today-dragged")
            XCTAssertTrue(moved, "reordering did not move the row (first \(firstExercise.frame.minY), second \(nextExercise.frame.minY))")
            edit.tap()
            sleep(1)
        } else {
            XCTFail("no «Изменить» on the exercises")
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

    /// The exercise card, the workout's steps and the summary, drawn by the app from the web app's description.
    func test3CardStepsSummary() {
        waitForPage()
        app.tabBars.firstMatch.buttons["Сегодня"].tap()
        XCTAssertTrue(app.navigationBars["Сегодня"].waitForExistence(timeout: 8), "Today drawn by the app did not come up")
        sleep(1)

        // the exercise card: the photos, the technique; its history and settings tabs
        let exercise = app.buttons["nv.row.s:plan/ex:A1"]
        if exercise.waitForExistence(timeout: 4) {
            exercise.tap()
            XCTAssertTrue(app.segmentedControls.buttons["Растяжение"].waitForExistence(timeout: 6), "the exercise card's photos did not come up")
            sleep(2)
            shot("70-card-technique")
            app.swipeUp()
            sleep(1)
            shot("70b-card-technique-more")
            app.swipeDown()
            sleep(1)
            let history = app.segmentedControls.buttons["История"]
            if history.waitForExistence(timeout: 3) {
                history.tap()
                sleep(2)
                shot("71-card-history")
            } else {
                XCTFail("no history tab in the exercise card")
            }
            let settings = app.segmentedControls.buttons["Настройки"]
            if settings.waitForExistence(timeout: 3) {
                settings.tap()
                sleep(2)
                shot("72-card-settings")
            }
            let close = app.navigationBars.buttons["Закрыть"].firstMatch
            if close.exists { tapFrame(close) } else { app.swipeDown(velocity: .fast) }
            sleep(2)
        } else {
            XCTFail("no exercise row on Today")
        }

        // a workout: the readiness sheet's button starts it
        let start = app.buttons["nv.btn.s:hero/Начать тренировку"]
        if start.waitForExistence(timeout: 3) {
            start.tap()
            let go = app.buttons["nv.btn.foot0"]
            if go.waitForExistence(timeout: 5) { go.tap() } else { XCTFail("no start button in the readiness sheet") }
        }
        let list = app.navigationBars["Верх A"]
        XCTAssertTrue(list.waitForExistence(timeout: 6), "the workout list did not come up")
        sleep(1)

        // «Ещё» → «Разминка, замена, заметки»: the exercise's step screen, pushed over the list
        let more = app.buttons["more.0"]
        if more.waitForExistence(timeout: 3) {
            more.tap()
            let old = element(beginningWith: "Разминка, замена")
            if old.waitForExistence(timeout: 3) { old.tap() } else { XCTFail("no «Разминка, замена, заметки» in the menu") }
        } else {
            XCTFail("no «Ещё» menu on the first exercise")
        }
        XCTAssertTrue(app.navigationBars["Упражнение"].waitForExistence(timeout: 6), "the exercise's step screen did not come up")
        sleep(1)
        shot("80-step-intro")
        app.swipeUp()
        sleep(1)
        shot("80b-step-intro-more")

        // the main button at the bottom: the set, then the rest with its ring and wheels, then a superset's «straight on»
        let main = app.buttons["nv.btn.foot0"]
        if main.waitForExistence(timeout: 3) { tapFrame(main) }
        XCTAssertTrue(app.navigationBars["Подход"].waitForExistence(timeout: 5), "the set screen did not come up")
        sleep(1)
        shot("81-step-set")
        if main.waitForExistence(timeout: 3) { tapFrame(main) }
        XCTAssertTrue(app.navigationBars["Отдых"].waitForExistence(timeout: 5), "the rest screen did not come up")
        sleep(2)
        shot("82-step-rest")
        if app.pickerWheels.count > 0 {
            app.pickerWheels.element(boundBy: app.pickerWheels.count - 1).swipeDown()
            sleep(2)
            shot("82b-step-rest-wheels")
        }
        if main.waitForExistence(timeout: 3) { tapFrame(main) }
        XCTAssertTrue(app.navigationBars["Суперсет"].waitForExistence(timeout: 5), "the superset screen did not come up")
        sleep(1)
        shot("83-step-superset")

        // back to the list with the back button
        let back = app.navigationBars["Суперсет"].buttons.firstMatch
        if back.exists { tapFrame(back) }
        XCTAssertTrue(list.waitForExistence(timeout: 5), "back did not return to the workout list")
        sleep(1)

        // finish → the summary, then «Готово»
        app.swipeUp()
        let finish = app.buttons["workout.finish"]
        if finish.waitForExistence(timeout: 3) {
            finish.tap()
            sleep(1)
            let ok = app.buttons["Завершить"]
            if ok.waitForExistence(timeout: 3) { ok.tap() } else { XCTFail("no «Завершить» in the question") }
        }
        XCTAssertTrue(app.navigationBars["Итоги"].waitForExistence(timeout: 6), "the summary did not come up")
        sleep(2)
        shot("84-summary")
        app.swipeUp()
        sleep(1)
        shot("84b-summary-more")
        // «Отправить Claude»: the page copies the report; its note comes up at the top
        let send = app.buttons["Отправить Claude"].firstMatch
        if send.waitForExistence(timeout: 3) {
            tapFrame(send)
            XCTAssertTrue(app.descendants(matching: .any)["toast"].waitForExistence(timeout: 3), "the page's note did not come up")
            shot("84c-summary-toast")
        }
        // «Готово» is under the capsule now: the tap has to go through it
        let done = app.navigationBars["Итоги"].buttons["Готово"]
        if done.exists { tapFrame(done) } else { XCTFail("no «Готово» on the summary") }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 6), "the tabs did not come back after the summary")
        sleep(1)
        shot("85-after-summary")
        XCTAssertEqual(app.state, .runningForeground, "the app is not running at the end")
    }

    /// The web app 12.11 («60/40»): Today and Progress are the page's own, Calendar and Settings the app's. A switch
    /// never shows an empty screen (the app holds a picture of the old one until the page says the new one is drawn);
    /// the workout list slides over the page's Today and away from it. CI records the screen during this test.
    func test4SplitTabs() {
        app.terminate()
        app.launchArguments = ["-GymDemo", "-GymSplit", "-GymHealthDemo"]
        app.launch()
        XCTAssertTrue(web.waitForExistence(timeout: 40), "no web view")
        XCTAssertTrue(web.staticTexts["Сегодня"].waitForExistence(timeout: 30), "the page's Today did not load")
        // what the Shortcuts app brought from Health reaches the page once it says it's ready
        XCTAssertTrue(web.staticTexts["health 1 sleep 3"].waitForExistence(timeout: 10), "the Health batch did not reach the page")
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "no tab bar")
        sleep(2)
        shot("90-split-today")
        let cover = app.descendants(matching: .any)["tab.cover"]
        func go(_ tab: String, until: XCUIElement, _ name: String) {
            tabBar.buttons[tab].tap()
            XCTAssertTrue(until.waitForExistence(timeout: 6), "\(tab) did not come up")
            sleep(2)
            XCTAssertFalse(cover.exists, "the picture over the switch to \(tab) stayed")
            shot(name)
        }
        go("Календарь", until: app.navigationBars["Календарь"], "91-split-calendar")
        go("Сегодня", until: web.staticTexts["Сегодня"], "92-split-today-again")
        go("Прогресс", until: web.staticTexts["Тренировок за 4 недели"], "93-split-progress")
        go("Настройки", until: app.navigationBars["Настройки"], "94-split-settings")
        go("Календарь", until: app.navigationBars["Календарь"], "95-split-calendar-again")
        go("Прогресс", until: web.staticTexts["Тренировок за 4 недели"], "96-split-progress-again")
        go("Сегодня", until: web.staticTexts["Сегодня"], "97-split-today-third")

        // the workout list over the page's Today, then away
        let start = web.buttons["Тренировка"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "no start button on the page's Today")
        start.tap()
        XCTAssertTrue(app.navigationBars["Верх A"].waitForExistence(timeout: 6), "the workout list did not come up")
        sleep(2)
        shot("98-split-workout")
        tapFrame(app.buttons["workout.minimize"].firstMatch)
        sleep(2)
        XCTAssertTrue(web.staticTexts["Сегодня"].exists, "the page's Today is not under the list")
        shot("99-split-after-workout")
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
            // a plain tap on the button: the app's invisible button over it hands it to the page's button
            hold.tap()
            XCTAssertTrue(web.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "holdTap")).firstMatch.waitForExistence(timeout: 3), "the tap did not reach the page's button")
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
