import Foundation
import Observation

/// 通知点击等外部入口需要改变界面状态时，通过这里传递。
@Observable
final class AppRouter {
    static let shared = AppRouter()

    var showRefine = false
    var openEntryID: UUID?
}
