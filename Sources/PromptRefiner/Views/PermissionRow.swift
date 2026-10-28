import SwiftUI

struct PermissionRow: View {
    let title: String
    let explanation: String
    let symbol: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: RefinerDesign.rowSpacing) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: RefinerDesign.compactSpacing) {
                    Text(title).font(.body)
                    Label(granted ? "已授权" : "未授权", systemImage: granted ? "checkmark.circle.fill" : "circle")
                        .font(.callout)
                        .foregroundStyle(granted ? Color.green : Color.secondary)
                }
                Text(explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: RefinerDesign.compactSpacing)
            Button(granted ? "管理" : "打开设置", action: action)
                .controlSize(.small)
                .accessibilityLabel("\(title)：\(granted ? "管理权限" : "打开系统设置授权")")
        }
    }
}
