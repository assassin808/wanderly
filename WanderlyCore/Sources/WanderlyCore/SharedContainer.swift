import Foundation

/// 分享扩展存下、等 App 导入的一条记录。
public struct InboxItem: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var text: String
    public var urgency: Urgency
    public var hasDue: Bool
    public var due: Date
    public var hasTime: Bool
    public var createdAt: Date

    public init(id: UUID = UUID(), text: String, urgency: Urgency = .soon, due: Date? = nil, hasTime: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.urgency = urgency
        self.hasDue = due != nil
        self.due = due ?? createdAt
        self.hasTime = hasTime
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, urgency, hasDue, due, hasTime, createdAt
    }

    /// 早期版本的收件箱文件没有紧急程度和 hasDue。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        urgency = try container.decodeIfPresent(Urgency.self, forKey: .urgency) ?? .soon
        hasDue = try container.decodeIfPresent(Bool.self, forKey: .hasDue) ?? true
        due = try container.decode(Date.self, forKey: .due)
        hasTime = try container.decode(Bool.self, forKey: .hasTime)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

/// App、小组件和分享扩展共用的 App Group 目录。
public enum SharedContainer {
    #if os(macOS)
    /// macOS 上 `group.` 开头的 App Group 受隐私保护：签名对不上时系统会弹「访问其他 App 的数据」并卡住访问线程。
    /// 用 Team ID 开头的写法不会弹窗。
    public static let appGroup = "ZS2UVBACK8.io.github.assassin808.wanderly"
    #else
    public static let appGroup = "group.io.github.assassin808.wanderly"
    #endif

    /// 没有 App Group 权限（比如未签名的调试包）时为 nil。
    public static var defaultURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    public static func writeSnapshot(_ snapshot: WidgetSnapshot, in directory: URL) throws {
        try JSONEncoder().encode(snapshot).write(to: snapshotURL(in: directory), options: .atomic)
    }

    public static func readSnapshot(in directory: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL(in: directory)) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// 每条记录单独一个文件，原子写入，App 读取时不会读到写了一半的内容。
    public static func addToInbox(_ item: InboxItem, in directory: URL) throws {
        let inbox = inboxURL(in: directory)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try JSONEncoder().encode(item).write(to: inbox.appending(path: "\(item.id.uuidString).json"), options: .atomic)
    }

    /// 取出并删除收件箱里的所有记录，按记录时间排序。
    public static func takeInbox(in directory: URL) -> [InboxItem] {
        let files = (try? FileManager.default.contentsOfDirectory(at: inboxURL(in: directory), includingPropertiesForKeys: nil)) ?? []
        var items: [InboxItem] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file), let item = try? JSONDecoder().decode(InboxItem.self, from: data) {
                items.append(item)
            }
            try? FileManager.default.removeItem(at: file)
        }
        return items.sorted { $0.createdAt < $1.createdAt }
    }

    static func snapshotURL(in directory: URL) -> URL {
        directory.appending(path: "widget-snapshot.json")
    }

    static func inboxURL(in directory: URL) -> URL {
        directory.appending(path: "inbox", directoryHint: .isDirectory)
    }
}
