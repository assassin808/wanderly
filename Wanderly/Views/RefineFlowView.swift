import SwiftUI
import SwiftData
import WanderlyCore

/// 晚间整理：一条一条过速记。
struct RefineFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Entry> { $0.stateRaw == "rough" }, sort: \Entry.createdAt)
    private var rough: [Entry]
    /// 打开时固定队列，避免标记完善后列表跳动。
    @State private var queue: [Entry] = []
    @State private var index = 0

    var body: some View {
        NavigationStack {
            Group {
                if index < queue.count {
                    let entry = queue[index]
                    Form {
                        EntryFields(entry: entry)
                        AskAISection(entry: entry)
                    }
                    .formStyle(.grouped)
                    .id(entry.id)
                    .safeAreaInset(edge: .bottom) {
                        actionBar(for: entry)
                    }
                } else {
                    ContentUnavailableView("都整理完了", systemImage: "checkmark.seal",
                                           description: Text("速记已经处理完。"))
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
            }
        }
        .onAppear {
            if queue.isEmpty { queue = rough }
        }
        .onDisappear {
            EntryActions.save(context)
        }
    }

    private func actionBar(for entry: Entry) -> some View {
        HStack(spacing: 12) {
            Menu {
                Button("其实已经做完了") { finish(entry, as: .done) }
                Button("不做了") { finish(entry, as: .dropped) }
                Button("推迟到明天") {
                    entry.snooze()
                    next()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)

            Button("跳过", action: next)
                .buttonStyle(.bordered)
            Spacer()
            Button("完善好了") { finish(entry, as: .open) }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.bar)
    }

    private func finish(_ entry: Entry, as state: EntryState) {
        entry.state = state
        EntryActions.save(context)
        next()
    }

    private func next() {
        withAnimation { index += 1 }
    }
}
