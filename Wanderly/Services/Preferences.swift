import Foundation
import WanderlyCore

/// 设置按设备保存：iPhone 和 Mac 可以各自决定要不要响、用哪家 AI。
enum Preferences {
    enum Key {
        static let remindersOn = "remindersOnThisDevice"
        static let morningMinute = "morningMinute"
        static let eveningMinute = "eveningMinute"
        static let firstNudgeMinutes = "firstNudgeMinutes"
        static let checkDelayMinutes = "checkDelayMinutes"
        static let aiProvider = "aiProvider"
        static let captureUrgency = "captureUrgency"
        static let betaIdeas = "betaIdeas"
        static let waterIntervalDays = "waterIntervalDays"
        static let lastWanderAt = "lastWanderAt"
    }

    private static let registered: Void = {
        let d = ReminderSettings.default
        UserDefaults.standard.register(defaults: [
            Key.remindersOn: true,
            Key.morningMinute: d.morningMinute,
            Key.eveningMinute: d.eveningMinute,
            Key.firstNudgeMinutes: d.firstNudgeMinutes,
            Key.checkDelayMinutes: d.checkDelayMinutes,
            Key.betaIdeas: false,
            Key.waterIntervalDays: 3,
        ])
    }()

    static func registerDefaults() {
        _ = registered
    }

    private static var defaults: UserDefaults {
        registerDefaults()
        return .standard
    }

    static var remindersOnThisDevice: Bool { defaults.bool(forKey: Key.remindersOn) }

    static var reminderSettings: ReminderSettings {
        ReminderSettings(
            morningMinute: defaults.integer(forKey: Key.morningMinute),
            eveningMinute: defaults.integer(forKey: Key.eveningMinute),
            firstNudgeMinutes: defaults.integer(forKey: Key.firstNudgeMinutes),
            checkDelayMinutes: defaults.integer(forKey: Key.checkDelayMinutes))
    }

    static var aiProvider: AIProvider {
        AIProvider(rawValue: defaults.string(forKey: Key.aiProvider) ?? "") ?? .gemini
    }

    static var betaIdeas: Bool { defaults.bool(forKey: Key.betaIdeas) }

    static var waterIntervalDays: Int { max(1, defaults.integer(forKey: Key.waterIntervalDays)) }

    static var lastWanderAt: Date? {
        get { defaults.object(forKey: Key.lastWanderAt) as? Date }
        set { defaults.set(newValue, forKey: Key.lastWanderAt) }
    }
}
