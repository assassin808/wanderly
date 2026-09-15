import XCTest

/// 在模拟器里走一遍主要流程。全部使用 `-demo` 内存数据库，不碰真实数据。
@MainActor
final class WanderlyUITests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    private func launch(_ arguments: [String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    func testCaptureThenComplete() {
        let app = launch(["-demo", "-skipNotificationPrompt"])

        let field = app.textFields["captureField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText("UI 测试速记\n")

        let row = app.staticTexts["UI 测试速记"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        // 示例数据里有 2 条速记，新记的一条也待完善。
        XCTAssertTrue(app.buttons["完善 3"].waitForExistence(timeout: 5))

        // 记完后输入框保持聚焦方便连续记；键盘会挡住下面的行，先收起来。
        app.keyboards.buttons["Done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        app.buttons["完成：UI 测试速记"].tap()

        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["完善 2"].waitForExistence(timeout: 5))
    }

    func testRefineFlow() {
        let app = launch(["-demo", "-skipNotificationPrompt"])

        let refine = app.buttons["refineButton"]
        XCTAssertTrue(refine.waitForExistence(timeout: 15))
        refine.tap()

        XCTAssertTrue(app.staticTexts["完善 1 / 2"].waitForExistence(timeout: 5))
        app.buttons["完善好了"].tap()
        XCTAssertTrue(app.staticTexts["完善 2 / 2"].waitForExistence(timeout: 5))
        app.buttons["完善好了"].tap()
        XCTAssertTrue(app.staticTexts["都整理完了"].waitForExistence(timeout: 5))

        app.buttons["关闭"].tap()
        let done = app.buttons["refineButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertEqual(done.label, "完善")
        XCTAssertFalse(done.isEnabled)
    }

    func testRemindersScheduledAndTestNotificationDelivered() {
        let app = launch(["-demo"])

        let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label IN {'Allow', '允许'}")).firstMatch
        if allow.waitForExistence(timeout: 10) { allow.tap() }

        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()

        // 设置页会重排，然后列出接下来的提醒。
        let planned = app.staticTexts.matching(NSPredicate(format: "label IN {'晚间整理', '做完了吗？'} OR label BEGINSWITH '今天有'")).firstMatch
        XCTAssertTrue(planned.waitForExistence(timeout: 10), "设置页没有列出排好的提醒")

        app.buttons["发一条测试通知"].tap()
        XCUIDevice.shared.press(.home)
        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '提醒可以正常收到'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 20), "测试通知没有弹出")
    }

    /// 需要编译时注入了 Gemini Key，并用 TEST_RUNNER_WANDERLY_LIVE_AI=1 运行。
    func testAIQuestions() throws {
        guard ProcessInfo.processInfo.environment["WANDERLY_LIVE_AI"] == "1" else {
            throw XCTSkip("设置 TEST_RUNNER_WANDERLY_LIVE_AI=1 才会真的调用 AI")
        }
        let app = launch(["-demo", "-skipNotificationPrompt"])

        let row = app.staticTexts["回房东邮件 暖气"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()

        let ask = app.buttons["askAIButton"]
        for _ in 0..<5 where !(ask.exists && ask.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(ask.isHittable)
        ask.tap()

        // 问题回来后按钮会被问题列表替换；出错的话按钮会留着并显示错误。
        XCTAssertTrue(ask.waitForNonExistence(timeout: 60), "AI 没有返回问题")
        let questions = XCTAttachment(screenshot: app.screenshot())
        questions.name = "AI questions"
        questions.lifetime = .keepAlways
        add(questions)

        let again = app.buttons["换一组问题"]
        for _ in 0..<3 where !again.exists {
            app.swipeUp()
        }
        XCTAssertTrue(again.exists)
    }
}
