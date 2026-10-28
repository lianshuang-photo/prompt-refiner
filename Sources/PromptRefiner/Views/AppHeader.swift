import SwiftUI
import AppKit

struct AppHeader: View {
    let title: String
    let subtitle: String
    var symbol = "text.badge.star"
    private static let brandmark = Bundle.main.url(forResource: "Brandmark", withExtension: "png").flatMap(NSImage.init(contentsOf:))

    var body: some View {
        HStack(alignment: .center, spacing: RefinerDesign.rowSpacing) {
            Group {
                if symbol == "text.badge.star", let brandmark = Self.brandmark {
                    Image(nsImage: brandmark).resizable().scaledToFill()
                } else {
                    Image(systemName: symbol).font(.title2).foregroundStyle(RefinerDesign.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RefinerDesign.accent.opacity(0.10))
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(.rect(cornerRadius: 10))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2).bold()
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
