import Foundation
import SwiftData
import WanderlyCore

enum Persistence {
    /// 以 `-demo` 启动时使用内存数据库和示例数据，方便截图和测试。
    static let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")

    static let schema = Schema([Entry.self, ChatMessage.self, WanderLink.self])

    static let container: ModelContainer = {
        if isDemo {
            let container = try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
            seed(container.mainContext)
            return container
        }
        do {
            return try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .automatic))
        } catch {
            print("iCloud store unavailable, using local store: \(error)")
            return try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none))
        }
    }()

    private static func seed(_ context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }

        func organized(_ entry: Entry, title: String, category: EntryCategory, summary: String = "") -> Entry {
            entry.aiTitle = title
            entry.category = category
            entry.aiSummary = summary
            entry.aiStatus = .done
            context.insert(entry)
            return entry
        }

        let meeting = organized(
            Entry(text: "和导师开组会，带上 radar plot 和上周的 ablation", urgency: .urgent,
                  due: calendar.date(bySettingHour: 15, minute: 0, second: 0, of: today)!, hasTime: true, state: .open),
            title: "和导师开组会", category: .meeting, summary: "带上 radar plot 和上周的 ablation 结果。")

        _ = organized(
            Entry(text: "报销会议差旅", urgency: .soon, due: day(-2), state: .open),
            title: "报销会议差旅", category: .todo)

        let idea = organized(
            Entry(text: "idea：让 agent 自己写 eval 再自己打分，看看能不能发现自己的弱点", urgency: .later),
            title: "让 agent 自己写 eval", category: .idea, summary: "让 agent 为自己出评测题并打分，借此暴露弱点。")

        let landlord = organized(
            Entry(text: "回房东邮件 暖气坏了", urgency: .urgent),
            title: "回房东邮件：暖气", category: .todo)

        _ = organized(
            Entry(text: "读 Concordia 那篇论文，先看 abstract 和 Figure 1", urgency: .later, state: .open),
            title: "读 Concordia 论文", category: .todo)

        _ = organized(
            Entry(text: "https://arxiv.org/abs/2312.03664 generative agent-based modeling", urgency: .archive, state: .open),
            title: "生成式 agent 建模论文", category: .reference, summary: "关于用生成式 agent 做社会模拟的论文链接。")

        let coffee = Entry(text: "买咖啡豆", urgency: .soon, state: .done)
        context.insert(coffee)

        for (entry, question) in [
            (idea, "1. 你最想用它验证 agent 的哪种能力？\n2. 自己给自己打分时，怎么避免它偏袒自己？"),
            (landlord, "1. 暖气是哪天开始坏的？\n2. 希望房东最晚什么时候来修？"),
        ] {
            let message = ChatMessage(role: .assistant, kind: .question, text: question)
            context.insert(message)
            message.entry = entry
        }
        _ = meeting
        try? context.save()
    }
}
