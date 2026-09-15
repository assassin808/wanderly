#if DEBUG && os(iOS)
import SwiftUI
import UIKit
import WidgetKit
import WanderlyCore

/// 调试用：以 `-renderWidgets` 启动时，把小组件的几种尺寸画成 PNG，放进 App 的 tmp 目录。
enum WidgetPreviewRenderer {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-renderWidgets") else { return }
        let variants: [(name: String, family: WidgetFamily, size: CGSize, accessory: Bool)] = [
            ("small", .systemSmall, CGSize(width: 170, height: 170), false),
            ("medium", .systemMedium, CGSize(width: 364, height: 170), false),
            ("rectangular", .accessoryRectangular, CGSize(width: 172, height: 76), true),
            ("circular", .accessoryCircular, CGSize(width: 76, height: 76), true),
            ("inline", .accessoryInline, CGSize(width: 260, height: 30), true),
        ]
        for variant in variants {
            let content = TodayWidgetView(snapshot: .sample, date: .now, family: variant.family)
                .padding(variant.accessory ? 0 : 16)
                .frame(width: variant.size.width, height: variant.size.height)
                .background(variant.accessory ? Color.black : Color.white)
                .environment(\.colorScheme, variant.accessory ? .dark : .light)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 3
            if let data = renderer.uiImage?.pngData() {
                try? data.write(to: FileManager.default.temporaryDirectory.appending(path: "widget-\(variant.name).png"))
            }
        }
    }
}
#endif
