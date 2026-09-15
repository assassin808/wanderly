import Foundation
import Observation

/// 通知、小组件、控件和链接这些外部入口需要改变界面状态时，通过这里传递。
@Observable
final class AppRouter {
    static let shared = AppRouter()

    var showRefine = false
    var openEntryID: UUID?
    /// 每加一次，速记输入框就获得焦点。
    var captureRequest = 0

    func requestCapture() {
        showRefine = false
        captureRequest += 1
    }

    /// 处理 wanderly://capture 和 wanderly://entry/<id>。
    func handle(_ url: URL) {
        guard url.scheme == "wanderly" else { return }
        switch url.host() {
        case "capture":
            requestCapture()
        case "entry":
            if let id = UUID(uuidString: url.lastPathComponent) {
                showRefine = false
                openEntryID = id
            }
        default:
            break
        }
    }
}
