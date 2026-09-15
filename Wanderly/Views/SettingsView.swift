import SwiftUI
import UserNotifications
import WanderlyCore

struct SettingsView: View {
    @AppStorage(Preferences.Key.remindersOn) private var remindersOn = true
    @AppStorage(Preferences.Key.morningMinute) private var morningMinute = ReminderSettings.default.morningMinute
    @AppStorage(Preferences.Key.eveningMinute) private var eveningMinute = ReminderSettings.default.eveningMinute
    @AppStorage(Preferences.Key.firstNudgeMinutes) private var firstNudgeMinutes = ReminderSettings.default.firstNudgeMinutes
    @AppStorage(Preferences.Key.checkDelayMinutes) private var checkDelayMinutes = ReminderSettings.default.checkDelayMinutes
    @AppStorage(Preferences.Key.aiProvider) private var provider: AIProvider = .gemini
    @AppStorage(Preferences.Key.betaIdeas) private var betaIdeas = false
    @AppStorage(Preferences.Key.waterIntervalDays) private var waterIntervalDays = 3
    @State private var apiKey = ""
    @State private var notificationsDenied = false
    @State private var upcoming: [UpcomingReminder] = []
    @State private var wanderMessage: String?

    /// 任一提醒设置变化都会重排并刷新列表。
    private var reminderSignature: [Int] {
        [remindersOn ? 1 : 0, morningMinute, eveningMinute, firstNudgeMinutes, checkDelayMinutes]
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

            Section("iCloud 同步") {
                if Persistence.isDemo {
                    Text("示例数据不会同步").foregroundStyle(.secondary)
                } else {
                    switch SyncStatus.shared.state {
                    case .waiting:
                        Text("正在连接 iCloud…").foregroundStyle(.secondary)
                    case let .synced(date):
                        Label("已同步 · \(DueText.describe(due: date, hasTime: true, now: .now))", systemImage: "checkmark.icloud")
                    case let .failed(detail):
                        VStack(alignment: .leading, spacing: 4) {
                            Label("同步出错", systemImage: "exclamationmark.icloud")
                                .foregroundStyle(.red)
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            Section {
                Picker("记下后多久提醒完善", selection: $firstNudgeMinutes) {
                    Text("1 小时").tag(60)
                    Text("2 小时").tag(120)
                    Text("3 小时").tag(180)
                    Text("4 小时").tag(240)
                }
                DatePicker("早上：到期的事、还在进行吗", selection: minutes($morningMinute), displayedComponents: .hourAndMinute)
                DatePicker("晚上：定期提醒完善", selection: minutes($eveningMinute), displayedComponents: .hourAndMinute)
                Picker("有具体时间的事，过多久问做完没", selection: $checkDelayMinutes) {
                    Text("30 分钟").tag(30)
                    Text("1 小时").tag(60)
                    Text("2 小时").tag(120)
                    Text("4 小时").tag(240)
                }
            } header: {
                Text("提醒节奏")
            } footer: {
                Text("紧急的每天提醒，这几天的每 2 天，不急的每周；只记录的不提醒。晚上 10 点以后不打扰。")
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
                Text("AI")
            } footer: {
                Text(keyFooter)
            }

            Section {
                Toggle("Idea 生长", isOn: $betaIdeas)
                if betaIdeas {
                    Picker("想法放多久没动就浇水", selection: $waterIntervalDays) {
                        Text("3 天").tag(3)
                        Text("5 天").tag(5)
                        Text("7 天").tag(7)
                    }
                    Button {
                        Task {
                            wanderMessage = nil
                            wanderMessage = await AIWorker.shared.wander(force: true) ?? "漫游完成，结果在列表最上面。"
                        }
                    } label: {
                        HStack {
                            Text("现在漫游一次")
                            if AIWorker.shared.wandering {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(AIWorker.shared.wandering)
                    if let wanderMessage {
                        Text(wanderMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Beta")
            } footer: {
                Text("漫游：每周把几个想法放在一起，找找可能的联系，由你决定采纳还是删掉。浇水：想法放久了，AI 会再问一个新问题。")
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
