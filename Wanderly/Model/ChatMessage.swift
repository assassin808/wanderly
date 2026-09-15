import Foundation
import SwiftData
import WanderlyCore

/// 记录下面的一条对话。单独建模，这样两台设备各自追加的消息同步时不会互相覆盖。
@Model
final class ChatMessage {
    enum Kind: String {
        /// 整理时 AI 提出的追问。
        case question
        case chat
        /// Beta 浇水：隔几天 AI 主动抛出的新问题。
        case water
    }

    var id: UUID = UUID()
    var roleRaw: String = ChatTurn.Role.assistant.rawValue
    var kindRaw: String = Kind.chat.rawValue
    var text: String = ""
    var createdAt: Date = Date()
    var entry: Entry?

    /// 插入数据库之后再设置 entry 关系，见 EntryActions.addMessage。
    init(role: ChatTurn.Role, kind: Kind, text: String) {
        roleRaw = role.rawValue
        kindRaw = kind.rawValue
        self.text = text
    }

    var role: ChatTurn.Role { ChatTurn.Role(rawValue: roleRaw) ?? .assistant }
    var kind: Kind { Kind(rawValue: kindRaw) ?? .chat }

    /// 追问一般是「1. …」开头的多行，提醒里只放第一个问题。
    static func firstQuestion(in text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).map { String($0).trimmed }.first { !$0.isEmpty } ?? ""
        return line.replacingOccurrences(of: #"^\d+[.、]\s*"#, with: "", options: .regularExpression)
    }
}
