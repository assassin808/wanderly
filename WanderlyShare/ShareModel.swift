import Foundation
import Observation
import UniformTypeIdentifiers
import WanderlyCore

/// 分享进来的文字和链接，存进 App Group 收件箱，等 App 打开时导入。
@Observable
final class ShareModel {
    var text = ""
    var loading = true

    func load(from context: NSExtensionContext?) async {
        defer { loading = false }
        var parts: [String] = []
        for item in (context?.inputItems as? [NSExtensionItem]) ?? [] {
            if let content = item.attributedContentText?.string.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty {
                parts.append(content)
            }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    parts.append(url.absoluteString)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let value = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    parts.append(value.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
        var seen = Set<String>()
        text = parts.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: "\n")
    }

    func save(due: Date, hasTime: Bool) throws {
        guard let directory = SharedContainer.defaultURL else { throw CocoaError(.fileNoSuchFile) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        try SharedContainer.addToInbox(InboxItem(text: trimmed, due: due, hasTime: hasTime), in: directory)
    }
}
