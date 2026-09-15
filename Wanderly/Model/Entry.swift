import Foundation
import SwiftData
import WanderlyCore

/// 唯一的数据类型。CloudKit 同步要求所有属性有默认值或可选。
@Model
final class Entry {
    var id: UUID = UUID()
    /// 速记时写下的原话，第一行作为标题。
    var text: String = ""
    var details: String = ""
    var nextStep: String = ""
    var due: Date = Date()
    var hasTime: Bool = false
    var stateRaw: String = EntryState.rough.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var refinedAt: Date?
    var closedAt: Date?
    var snoozeCount: Int = 0

    init(text: String, due: Date, hasTime: Bool = false, state: EntryState = .rough) {
        self.text = text
        self.due = due
        self.hasTime = hasTime
        self.stateRaw = state.rawValue
    }

    var state: EntryState {
        get { EntryState(rawValue: stateRaw) ?? .rough }
        set {
            stateRaw = newValue.rawValue
            updatedAt = .now
            switch newValue {
            case .rough:
                closedAt = nil
            case .open:
                refinedAt = refinedAt ?? .now
                closedAt = nil
            case .done, .dropped:
                closedAt = .now
            }
        }
    }

    var title: String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "（空白）" : trimmed
    }

    var snapshot: EntrySnapshot {
        EntrySnapshot(id: id, title: title, due: due, hasTime: hasTime, state: state)
    }

    func snooze(days: Int = 1) {
        due = DueMath.snoozed(due: due, hasTime: hasTime, days: days, now: .now)
        snoozeCount += 1
        updatedAt = .now
    }
}
