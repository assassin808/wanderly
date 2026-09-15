import SwiftUI
import SwiftData
import WanderlyCore

/// 一条一条过待完善的记录：回答 AI 的问题，或者直接标记完善好了。
struct RefineFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Entry> { $0.stateRaw == "rough" }, sort: \Entry.createdAt)
    private var rough: [Entry]
    /// 打开时固定队列，避免回答后列表跳动。
    @State private var queue: [Entry] = []
    @State private var index = 0

    var body: some View {
        NavigationStack {
            Group {
                if index < queue.count {
                    EntryConversation(entry: queue[index])
                        .id(queue[index].id)
                } else {
                    ContentUnavailableView("都整理完了", systemImage: "checkmark.seal",
                                           description: Text("待完善的记录已经处理完。"))
                }
            }
            .navigationTitle(index < queue.count ? "完善 \(index + 1) / \(queue.count)" : "完善")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                if index < queue.count {
                    ToolbarItem(placement: .primaryAction) {
                        Button("跳过", action: next)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完善好了") {
                            EntryActions.set(queue[index], to: .open, in: context)
                            next()
                        }
                    }
                }
            }
        }
        .onAppear {
            if queue.isEmpty { queue = rough.filter { $0.urgency != .archive } }
        }
        .onDisappear {
            EntryActions.save(context)
        }
    }

    private func next() {
        withAnimation { index += 1 }
    }
}
