import SwiftUI

struct ResultActionBar: View {
    @ObservedObject var coordinator: Coordinator
    let validResult: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: RefinerDesign.rowSpacing) {
                if coordinator.hasUndo {
                    Button("撤销回填", systemImage: "arrow.uturn.backward", action: coordinator.undoLast)
                        .controlSize(.small)
                        .help("只撤销上次回填，保留其他输入。")
                } else {
                    Text(coordinator.canApply ? "回填后由你发送" : "原稿已保留")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: RefinerDesign.rowSpacing)
                ResultPrimaryActions(coordinator: coordinator, validResult: validResult)
            }
            VStack(alignment: .trailing, spacing: RefinerDesign.compactSpacing) {
                ResultPrimaryActions(coordinator: coordinator, validResult: validResult)
                if coordinator.hasUndo {
                    Button("撤销回填", systemImage: "arrow.uturn.backward", action: coordinator.undoLast)
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, RefinerDesign.pageInset)
        .padding(.vertical, RefinerDesign.rowSpacing)
    }
}
