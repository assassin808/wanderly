import Foundation
import SwiftData
import WanderlyCore

enum Persistence {
    /// 以 `-demo` 启动时使用内存数据库和示例数据，方便截图和调试。
    static let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")

    static let container: ModelContainer = {
        let schema = Schema([Entry.self])
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

        let meeting = Entry(text: "和导师开组会", due: calendar.date(bySettingHour: 15, minute: 0, second: 0, of: today)!, hasTime: true, state: .open)
        meeting.details = "带上 radar plot 和上周的 ablation"
        meeting.nextStep = "中午前把图导出来"

        let reimburse = Entry(text: "报销会议差旅", due: day(-2), state: .open)

        let idea = Entry(text: "idea：让 agent 自己写 eval 再自己打分", due: DueShortcut.weekend.date(from: .now))

        let landlord = Entry(text: "回房东邮件 暖气", due: day(1))

        let paper = Entry(text: "读 Concordia 那篇论文", due: DueShortcut.nextWeekend.date(from: .now), state: .open)
        paper.nextStep = "先读 abstract 和 Figure 1"

        let coffee = Entry(text: "买咖啡豆", due: day(-1), state: .done)

        [meeting, reimburse, idea, landlord, paper, coffee].forEach(context.insert)
        try? context.save()
    }
}
