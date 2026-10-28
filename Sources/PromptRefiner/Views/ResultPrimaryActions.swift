import SwiftUI

struct ResultPrimaryActions: View {
    @ObservedObject var coordinator: Coordinator
    let validResult: Bool

    var body: some View {
        HStack(spacing: RefinerDesign.compactSpacing) {
            if coordinator.canApply {
                Button("复制", systemImage: "doc.on.doc", action: coordinator.copyResult)
                    .disabled(!validResult)
                    .help("复制当前编辑后的结果。")
                Button("回填到原输入框", systemImage: "arrow.turn.down.left", action: coordinator.applyResult)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!validResult)
                    .help("⌘↩ 回填当前编辑后的结果。")
            } else {
                Button("复制结果", systemImage: "doc.on.doc", action: coordinator.copyResult)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!validResult)
                    .help("⌘↩ 复制当前编辑后的结果。")
            }
        }
        .controlSize(.regular)
    }
}
