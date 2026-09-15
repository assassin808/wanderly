import SwiftUI
import UserNotifications
import WanderlyCore

struct SettingsView: View {
    @AppStorage(Preferences.Key.remindersOn) private var remindersOn = true
    @AppStorage(Preferences.Key.morningMinute) private var morningMinute = ReminderSettings.default.morningMinute
    @AppStorage(Preferences.Key.eveningMinute) private var eveningMinute = ReminderSettings.default.eveningMinute
    @AppStorage(Preferences.Key.reviewWeekday) private var reviewWeekday = ReminderSettings.default.reviewWeekday
    @AppStorage(Preferences.Key.checkDelayMinutes) private var checkDelayMinutes = ReminderSettings.default.checkDelayMinutes
    @State private var apiKey = APIKeyStore.load() ?? ""
    @State private var notificationsDenied = false

    private let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

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
                SecureField("Claude API Key", text: $apiKey)
                    .onChange(of: apiKey) { _, key in APIKeyStore.save(key) }
                Link("在 Anthropic Console 创建 Key", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
            } header: {
                Text("AI 追问")
            } footer: {
                Text("Key 保存在钥匙串里，只在你自己的设备间通过 iCloud 钥匙串同步。")
            }
        }
        .formStyle(.grouped)
        .onChange(of: [morningMinute, eveningMinute, reviewWeekday, checkDelayMinutes]) {
            Reminders.shared.scheduleSoon()
        }
        .onChange(of: remindersOn) {
            Reminders.shared.scheduleSoon()
        }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsDenied = settings.authorizationStatus == .denied
        }
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
