import Foundation
import SwiftData

/// Beta 漫游的结果：AI 推测几个想法之间可能的联系，等用户采纳或删掉。
@Model
final class WanderLink {
    var id: UUID = UUID()
    var title: String = ""
    var insight: String = ""
    var question: String = ""
    /// 用到的想法 id，逗号分隔。
    var sourceIDsRaw: String = ""
    /// 生成时的想法标题，想法后来被删掉也能显示。
    var sourceTitles: String = ""
    var createdAt: Date = Date()

    init(title: String, insight: String, question: String, sourceIDs: [UUID], sourceTitles: [String]) {
        self.title = title
        self.insight = insight
        self.question = question
        self.sourceIDsRaw = sourceIDs.map(\.uuidString).joined(separator: ",")
        self.sourceTitles = sourceTitles.joined(separator: "、")
    }

    var sourceIDs: [UUID] {
        sourceIDsRaw.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }
}
