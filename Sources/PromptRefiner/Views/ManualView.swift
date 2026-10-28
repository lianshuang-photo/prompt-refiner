import SwiftUI

struct ManualView: View {
    @ObservedObject var coordinator: Coordinator

    var body: some View {
        VStack(spacing: 0) {
            AppHeader(title: "写下你的想法", subtitle: "手动输入只使用下面的文字。")
                .padding(RefinerDesign.pageInset)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: RefinerDesign.compactSpacing) {
                    HStack {
                        Text("原稿").font(.headline)
                        Spacer(minLength: 0)
                        Text("\(coordinator.manualDraft.utf16.count.formatted()) / 40,000")
                            .font(.callout).foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    MultilineEditor(text: $coordinator.manualDraft,
                                    placeholder: "写下你想做的事，以及需要保留的限制…",
                                    accessibilityLabel: "需要细化的原稿", minimumHeight: 180, maximumHeight: 300)
                    if coordinator.manualDraft.utf16.count > 40_000 {
                        Label("原稿过长，请删减后再细化。", systemImage: "exclamationmark.circle")
                            .font(.callout).foregroundStyle(.red)
                    }
                }
                .padding(RefinerDesign.pageInset)
            }
            Divider()
            HStack(spacing: RefinerDesign.rowSpacing) {
                Text("保留原意，补清范围与执行要求。")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("开始细化", systemImage: "sparkles", action: coordinator.runManual)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canRefine)
                    .help("⌘↩ 开始细化。")
            }
            .padding(.horizontal, RefinerDesign.pageInset)
            .padding(.vertical, RefinerDesign.rowSpacing)
        }
        .background(RefinerDesign.windowBackground)
        .tint(RefinerDesign.accent)
    }

    private var canRefine: Bool {
        !coordinator.busy && coordinator.manualDraft.utf16.count <= 40_000
            && !coordinator.manualDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
