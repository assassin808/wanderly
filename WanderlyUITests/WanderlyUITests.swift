import WanderlyCore
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

    /// 多行输入框在 UIKit 里是 text view，按 identifier 找不区分类型。
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func testCaptureThenComplete() {
        let app = launch(["-demo", "-skipNotificationPrompt"])

        let field = element("captureField", in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText("UI 测试速记")
        app.buttons["captureSave"].tap()

        let row = app.staticTexts["UI 测试速记"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        // 示例数据里有 2 条待完善，新记的一条也待完善。
        XCTAssertTrue(app.buttons["完善 3"].waitForExistence(timeout: 5))

        app.buttons["完成：UI 测试速记"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["完善 2"].waitForExistence(timeout: 5))
    }

    /// 回归：AI 换了标题之后，列表和详情都要能看到自己记下的原文。
    func testOriginalTextStaysVisible() {
        let app = launch(["-demo", "-skipNotificationPrompt"])

        let aiTitle = app.staticTexts["回房东邮件：暖气"]
        XCTAssertTrue(aiTitle.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["回房东邮件 暖气坏了"].exists, "列表里应该同时能看到原文")

        aiTitle.tap()
        let original = element("originalField", in: app)
        XCTAssertTrue(original.waitForExistence(timeout: 5))
        XCTAssertTrue(original.isHittable, "详情里的原文不用点开就能看到")
        attachScreenshot(app, name: "Original text visible")
    }

    func testDetectsTimeWhileTyping() throws {
        let app = launch(["-demo", "-skipNotificationPrompt"])

        let field = element("captureField", in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        let text = "周五下午三点和导师聊 eval"
        field.typeText(text)

        let detected = try XCTUnwrap(DueParser.parse(text, now: .now))
        let label = DueText.describe(due: detected.date, hasTime: detected.hasTime, now: .now)
        XCTAssertTrue(app.buttons["识别到 \(label)"].waitForExistence(timeout: 5))

        app.buttons["captureSave"].tap()
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[label].exists, "新记的事应该带着识别到的时间")
    }

    /// 回归：以前 AI 追问的内容一离开页面或切到后台就没了。
    func testConversationSurvivesClosingAndBackground() {
        let app = launch(["-demo", "-skipNotificationPrompt"])

        let row = app.staticTexts["回房东邮件：暖气"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()

        // 回归：以前问题被挤到输入框后面，打开只看得到「回答 AI 的问题…」。问题必须真的在屏幕上。
        let banner = element("pendingQuestion", in: app)
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "输入框上方应该显示 AI 的问题")
        XCTAssertTrue(banner.label.contains("暖气是哪天开始坏的"))
        XCTAssertTrue(banner.isHittable)
        let question = element("aiMessage", in: app)
        XCTAssertTrue(question.waitForExistence(timeout: 5), "AI 的追问应该在对话里")
        let onScreen = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: question)
        wait(for: [onScreen], timeout: 5)
        attachScreenshot(app, name: "Question visible on open")

        let input = element("chatField", in: app)
        input.tap()
        input.typeText("上周三开始坏的，希望周末前修好")
        app.buttons["chatSend"].tap()
        let reply = app.staticTexts["上周三开始坏的，希望周末前修好"]
        XCTAssertTrue(reply.waitForExistence(timeout: 5))

        app.buttons["好"].tap()
        XCUIDevice.shared.press(.home)
        app.activate()

        // 回复之后就算完善了，待完善从 2 条变成 1 条。
        XCTAssertTrue(app.buttons["完善 1"].waitForExistence(timeout: 10))
        app.staticTexts["回房东邮件：暖气"].tap()
        XCTAssertTrue(reply.waitForExistence(timeout: 5), "关掉再打开后，对话应该还在")
        XCTAssertTrue(element("aiMessage", in: app).exists)
    }

    func testCaptureLinkFocusesInput() {
        let app = launch(["-demo", "-skipNotificationPrompt"])
        XCTAssertTrue(element("captureField", in: app).waitForExistence(timeout: 15))
        XCTAssertFalse(app.keyboards.firstMatch.exists)

        app.open(URL(string: "wanderly://capture")!)
        let confirm = springboard.buttons.matching(NSPredicate(format: "label IN {'Open', '打开'}")).firstMatch
        if confirm.waitForExistence(timeout: 2) { confirm.tap() }

        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "wanderly://capture 应该让输入框获得焦点")
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
        let planned = app.staticTexts.matching(NSPredicate(format:
            "label BEGINSWITH '去完善' OR label BEGINSWITH '有 ' OR label BEGINSWITH '今天有' OR label IN {'做完了吗？', '还在进行吗？'}")).firstMatch
        XCTAssertTrue(planned.waitForExistence(timeout: 10), "设置页没有列出排好的提醒")

        app.buttons["发一条测试通知"].tap()
        XCUIDevice.shared.press(.home)
        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '提醒可以正常收到'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 20), "测试通知没有弹出")
    }

    /// 需要编译时注入了 Gemini Key，并用 TEST_RUNNER_WANDERLY_LIVE_AI=1 运行。
    func testAIOrganizesInBackgroundAndChats() throws {
        guard ProcessInfo.processInfo.environment["WANDERLY_LIVE_AI"] == "1" else {
            throw XCTSkip("设置 TEST_RUNNER_WANDERLY_LIVE_AI=1 才会真的调用 AI")
        }
        let app = launch(["-demo", "-skipNotificationPrompt", "-demoAI"])

        let field = element("captureField", in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        let text = "想做一个让 agent 自己出 eval 题再自己打分的实验，看看它能不能发现自己的弱点"
        field.typeText(text)
        app.buttons["captureSave"].tap()

        // AI 可能很快就把标题换掉，所以按原文生成的固定标识找这一行；问题整理好会直接出现在对话里。
        let row = app.staticTexts["entry:\(text)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(element("aiMessage", in: app).waitForExistence(timeout: 90), "AI 没有在后台整理出问题")
        attachScreenshot(app, name: "AI organized")

        let input = element("chatField", in: app)
        input.tap()
        input.typeText("主要想验证它能不能找出自己在长程规划上的问题")
        app.buttons["chatSend"].tap()

        // 对话会滚到底部，列表只渲染看得见的行，所以不数消息条数，而是等一条不带「AI 追问」标记的回复出现。
        // 免费额度经常繁忙，App 会自动换模型、隔几秒重试，所以多等一会儿。
        let reply = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'aiMessage' AND NOT (label BEGINSWITH 'AI 追问')"))
            .firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 240), "AI 没有回复")
        attachScreenshot(app, name: "AI replied")
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
