import Foundation
import WidgetKit
import WanderlyCore

/// 把当前的待办写进 App Group，内容变了才刷新小组件。
enum WidgetBridge {
    static func publish(_ entries: [EntrySnapshot]) {
        guard !Persistence.isDemo, let directory = SharedContainer.defaultURL else { return }
        let snapshot = WidgetSnapshot(entries: entries)
        guard snapshot != SharedContainer.readSnapshot(in: directory) else { return }
        try? SharedContainer.writeSnapshot(snapshot, in: directory)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
