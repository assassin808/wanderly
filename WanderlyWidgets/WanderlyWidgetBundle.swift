import SwiftUI
import WidgetKit

@main
struct WanderlyWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        #if os(iOS)
        CaptureControl()
        #endif
    }
}
