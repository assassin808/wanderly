import Foundation
import WanderlyCore

/// 提醒设置按设备保存：iPhone 和 Mac 可以各自决定要不要响。
enum Preferences {
    enum Key {
        static let remindersOn = "remindersOnThisDevice"
        static let morningMinute = "morningMinute"
        static let eveningMinute = "eveningMinute"
        static let reviewWeekday = "reviewWeekday"
        static let checkDelayMinutes = "checkDelayMinutes"
        static let aiProvider = "aiProvider"
    }

    private static let registered: Void = {
        let d = ReminderSettings.default
        UserDefaults.standard.register(defaults: [
            Key.remindersOn: true,
            Key.morningMinute: d.morningMinute,
            Key.eveningMinute: d.eveningMinute,
            Key.reviewWeekday: d.reviewWeekday,
            Key.checkDelayMinutes: d.checkDelayMinutes,
        ])
    }()

    static func registerDefaults() {
        _ = registered
    }

    static var remindersOnThisDevice: Bool {
        registerDefaults()
        return UserDefaults.standard.bool(forKey: Key.remindersOn)
    }

    static var reminderSettings: ReminderSettings {
        registerDefaults()
        let defaults = UserDefaults.standard
        return ReminderSettings(
            morningMinute: defaults.integer(forKey: Key.morningMinute),
            eveningMinute: defaults.integer(forKey: Key.eveningMinute),
            reviewWeekday: defaults.integer(forKey: Key.reviewWeekday),
            checkDelayMinutes: defaults.integer(forKey: Key.checkDelayMinutes))
    }
}
