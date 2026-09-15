import Foundation

/// 把一条记录和它的对话导出成 Markdown，用于分享或存档。
public enum MarkdownExport {
    public struct Message: Sendable, Equatable {
        public var role: ChatTurn.Role
        public var text: String

        public init(role: ChatTurn.Role, text: String) {
            self.role = role
            self.text = text
        }
    }

    public static func entry(
        title: String,
        category: EntryCategory?,
        urgency: Urgency,
        due: String?,
        text: String,
        details: String = "",
        nextStep: String = "",
        summary: String,
        messages: [Message]
    ) -> String {
        var lines = ["# \(title)", ""]
        if let category { lines.append("- 类别：\(category.label)") }
        lines.append("- 紧急程度：\(urgency.label)")
        if let due { lines.append("- 截止：\(due)") }
        lines += ["", "## 原文", "", text.trimmed]
        if !details.trimmed.isEmpty {
            lines += ["", "## 细节", "", details.trimmed]
        }
        if !nextStep.trimmed.isEmpty {
            lines += ["", "## 下一步", "", nextStep.trimmed]
        }
        if !summary.trimmed.isEmpty {
            lines += ["", "## AI 整理", "", summary.trimmed]
        }
        if !messages.isEmpty {
            lines += ["", "## 对话", ""]
            for message in messages {
                lines.append("**\(message.role == .user ? "我" : "AI")**：\(message.text.trimmed)")
                lines.append("")
            }
            lines.removeLast()
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
