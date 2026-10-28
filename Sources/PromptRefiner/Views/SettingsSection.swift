import SwiftUI

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: RefinerDesign.compactSpacing) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: RefinerDesign.rowSpacing) {
                content
            }
            .padding(RefinerDesign.rowSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RefinerDesign.cardBackground, in: .rect(cornerRadius: RefinerDesign.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: RefinerDesign.cardRadius)
                    .stroke(RefinerDesign.separator.opacity(0.45), lineWidth: 1)
            }
        }
    }
}
