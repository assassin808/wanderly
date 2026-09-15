import SwiftUI
import UserNotifications
import WanderlyCore

struct SettingsView: View {
    @AppStorage(Preferences.Key.remindersOn) private var remindersOn = true
    @AppStorage(Preferences.Key.morningMinute) private var morningMinute = ReminderSettings.default.morningMinute
    @AppStorage(Preferences.Key.eveningMinute) private var eveningMinute = ReminderSettings.default.eveningMinute
    @AppStorage(Preferences.Key.reviewWeekday) private var reviewWeekday = ReminderSettings.default.reviewWeekday
    @AppStorage(Preferences.Key.checkDelayMinutes) private var checkDelayMinutes = ReminderSettings.default.checkDelayMinutes
    @AppStorage(Preferences.Key.aiProvider) private var provider: AIProvider = .gemini
    @State private var apiKey = ""
    @State private var notificationsDenied = false
    @State private var upcoming: [UpcomingReminder] = []

    private let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    /// 任一提醒设置变化都会重排并刷新列表。
    private var reminderSignature: [Int] {
        [remindersOn ? 1 : 0, morningMinute, eveningMinute, reviewWeekday, checkDelayMinutes]
    }

    var body: some View {
        Form {
            Section {
                Toggle("在这台设备上提醒", isOn: $remindersOn)
                if notificationsDenied {
                    Text("系统通知权限是关着的，需要去系统设置里打开。")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button("发一条测试通知") {
                    Task { await Reminders.shared.sendTest() }
                }
            } footer: {
                Text("iPhone 和 Mac 都开着的话会各响一次，可以只留一台。")
            }

            Section("接下来的提醒") {
                if upcoming.isEmpty {
                    Text(remindersOn ? "还没有排好的提醒" : "这台设备的提醒已关闭")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(upcoming) { item in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                Text(item.body)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text(DueText.describe(due: item.date, hasTime: true, now: .now))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("提醒时间") {
                DatePicker("早上：今天到期的事", selection: minutes($morningMinute), displayedComponents: .hourAndMinute)
                DatePicker("晚上：完善速记、确认做完", selection: minutes($eveningMinute), displayedComponents: .hourAndMinute)
                Picker("周回顾", selection: $reviewWeekday) {
                    Text("关闭").tag(0)
                    ForEach(1...7, id: \.self) { day in
                        Text(weekdays[day - 1] + "晚上").tag(day)
                    }
                }
                Picker("有具体时间的事，过多久问做完没", selection: $checkDelayMinutes) {
                    Text("30 分钟").tag(30)
                    Text("1 小时").tag(60)
                    Text("2 小时").tag(120)
                    Text("4 小时").tag(240)
                }
            }

            Section {
                Picker("服务", selection: $provider) {
                    ForEach(AIProvider.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                SecureField("\(provider.displayName) API Key", text: $apiKey)
                switch provider {
                case .gemini:
                    Link("在 Google AI Studio 创建 Key", destination: URL(string: "https://aistudio.google.com/apikey")!)
                case .claude:
                    Link("在 Anthropic Console 创建 Key", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                }
            } header: {
                Text("AI 追问")
            } footer: {
                Text(keyFooter)
            }
        }
        .formStyle(.grouped)
        .task(id: reminderSignature) {
            await Reminders.shared.reschedule()
            upcoming = await Reminders.shared.upcoming()
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsDenied = settings.authorizationStatus == .denied
        }
        .task(id: provider) {
            apiKey = APIKeyStore.load(for: provider) ?? ""
        }
        .onChange(of: apiKey) { _, key in
            APIKeyStore.save(key, for: provider)
        }
    }

    private var keyFooter: String {
        if provider == .gemini, apiKey.isEmpty, APIKeyStore.bundledGeminiKey != nil {
            return "没填时使用编译时内置的 Gemini Key。"
        }
        return "Key 保存在钥匙串里，只在你自己的设备间通过 iCloud 钥匙串同步。"
    }

    private func minutes(_ value: Binding<Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: value.wrappedValue / 60, minute: value.wrappedValue % 60, second: 0, of: .now)!
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            value.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
    }
}
