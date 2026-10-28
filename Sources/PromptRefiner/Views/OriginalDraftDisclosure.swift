import SwiftUI

struct OriginalDraftDisclosure: View {
    let draft: String
    let copyOriginal: () -> Void
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: RefinerDesign.rowSpacing) {
                ScrollView {
                    Text(draft)
                        .font(.body)
                        .textSelection(.enabled)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(RefinerDesign.rowSpacing)
                }
                .frame(maxHeight: 180)
                .background(RefinerDesign.cardBackground, in: .rect(cornerRadius: RefinerDesign.editorRadius))
                Button("复制原稿", systemImage: "doc.on.doc", action: copyOriginal)
                    .controlSize(.small)
            }
            .padding(.top, RefinerDesign.compactSpacing)
        } label: {
            Label("查看原稿", systemImage: "text.alignleft")
                .font(.callout).foregroundStyle(.secondary)
        }
        .onChange(of: draft) { _, _ in expanded = false }
    }
}
