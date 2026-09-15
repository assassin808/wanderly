import CloudKit
import CoreData
import Foundation
import Observation
import os

/// 监听 SwiftData 背后的 CloudKit 同步事件：在设置里显示状态，并把错误详情写进系统日志。
@Observable
final class SyncStatus {
    static let shared = SyncStatus()

    enum State: Equatable {
        case waiting
        case synced(Date)
        case failed(String)
    }

    private(set) var state: State = .waiting
    @ObservationIgnored private let logger = Logger(subsystem: "io.github.assassin808.wanderly", category: "sync")

    func start() {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                  let endDate = event.endDate else { return }
            let kind = SyncStatus.name(of: event.type)
            let detail = event.error.map(SyncStatus.describe)
            MainActor.assumeIsolated {
                SyncStatus.shared.record(kind: kind, endDate: endDate, detail: detail)
            }
        }
    }

    private func record(kind: String, endDate: Date, detail: String?) {
        if let detail {
            logger.error("CloudKit \(kind, privacy: .public) failed: \(detail, privacy: .public)")
            state = .failed(detail)
        } else {
            logger.info("CloudKit \(kind, privacy: .public) succeeded")
            state = .synced(endDate)
        }
    }

    nonisolated private static func name(of type: NSPersistentCloudKitContainer.EventType) -> String {
        switch type {
        case .setup: "setup"
        case .`import`: "import"
        case .export: "export"
        @unknown default: "event"
        }
    }

    /// 展开 CloudKit 的部分失败和底层错误，否则只能看到「Partial Failure」。
    nonisolated private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var parts = ["\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"]
        if let debug = nsError.userInfo[NSDebugDescriptionErrorKey] as? String {
            parts.append(debug)
        }
        // 部分失败的详情只能通过 CKError 的接口拿到，直接读 userInfo 是空的。
        if let ckError = error as? CKError, let partial = ckError.partialErrorsByItemID {
            for (item, itemError) in partial {
                let e = itemError as NSError
                let debug = e.userInfo[NSDebugDescriptionErrorKey] as? String ?? ""
                parts.append("\(item) → \(e.domain) \(e.code): \(e.localizedDescription) \(debug)")
            }
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying \(underlying.domain) \(underlying.code): \(underlying.localizedDescription)")
        }
        return parts.joined(separator: "\n")
    }
}
