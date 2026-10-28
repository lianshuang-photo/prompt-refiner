import SwiftUI

struct CompactResultPanelView: View {
    @ObservedObject var coordinator: Coordinator

    var body: some View {
        VStack(alignment: .leading, spacing: RefinerDesign.rowSpacing) {
            HStack(spacing: RefinerDesign.compactSpacing) {
                Label("细化完成", systemImage: "text.badge.star")
                    .font(.headline)
                Spacer(minLength: RefinerDesign.compactSpacing)
                Button("展开", systemImage: "arrow.up.left.and.arrow.down.right", action: coordinator.showResult)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("查看完整结果、补充建议和原稿。")
                Button("关闭", systemImage: "xmark", action: coordinator.dismissResultPanel)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                    .help("关闭结果浮层，结果仍保留在菜单栏。")
            }

            CompactSourceSummary(description: coordinator.sourceDescription, details: coordinator.sourceDetails)

            MultilineEditor(text: $coordinator.editedPrompt, placeholder: "改写结果…",
                            accessibilityLabel: "细化后的提示词，可编辑", minimumHeight: 100, maximumHeight: 148)

            if !statusMessage.isEmpty {
                CompactResultNotice(message: statusMessage, tone: coordinator.noticeTone)
            }

            HStack(spacing: RefinerDesign.compactSpacing) {
                if coordinator.hasUndo {
                    Button("撤销", systemImage: "arrow.uturn.backward", action: coordinator.undoLast)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help("撤销上次回填，保留其他输入。")
                }
                Spacer(minLength: 0)
                ResultPrimaryActions(coordinator: coordinator, validResult: validResult)
            }
        }
        .padding(RefinerDesign.rowSpacing + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: RefinerDesign.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: RefinerDesign.cardRadius)
                .stroke(RefinerDesign.separator.opacity(0.5), lineWidth: 1)
        }
        .tint(RefinerDesign.accent)
    }

    private var validResult: Bool {
        coordinator.result != nil && !coordinator.busy
            && !coordinator.editedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && coordinator.editedPrompt.utf16.count <= 40_000
    }

    private var statusMessage: String {
        if coordinator.editedPrompt.utf16.count > 40_000 {
            return "结果超过长度限制，请删减后再应用。"
        }
        if !coordinator.canApply,
           let bindingIssue = coordinator.sourceDetails.first(where: { $0.hasPrefix("回填：") && !$0.contains("已绑定") }) {
            let reason = String(bindingIssue.dropFirst("回填：".count))
            return coordinator.result?.requiresReview == true ? "\(reason)；另有关键推断，展开后检查。" : reason
        }
        if !coordinator.resultNote.isEmpty { return coordinator.resultNote }
        if coordinator.hasUndo { return "已回填到原输入框，可继续编辑或撤销。" }
        if !coordinator.canApply { return "暂时无法回填到原输入框，请复制结果。" }
        return ""
    }
}
