#if os(iOS)
import AppIntents
import SwiftUI
import WidgetKit

/// 控制中心、锁屏和操作按钮上的「记一件事」。
struct CaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "io.github.assassin808.wanderly.capture") {
            ControlWidgetButton(action: OpenCaptureIntent()) {
                Label("记一件事", systemImage: "square.and.pencil")
            }
        }
        .displayName("记一件事")
        .description("打开 Wanderly，直接开始速记。")
    }
}
#endif
