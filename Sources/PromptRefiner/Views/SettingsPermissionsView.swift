import AppKit
import Combine
import SwiftUI

struct SettingsPermissionsView: View {
    @State private var accessibilityAllowed = Accessibility.trusted
    @State private var captureAllowed = WindowCapture.permitted

    var body: some View {
        SettingsSection(title: "权限") {
            PermissionRow(title: "辅助功能", explanation: "读取原输入框，并把结果回填到原位置。",
                          symbol: "cursorarrow.and.square.on.square.dashed", granted: accessibilityAllowed,
                          action: openAccessibilitySettings)
            Divider()
            PermissionRow(title: "屏幕录制", explanation: "触发时截取当前窗口，补充文字之外的上下文。",
                          symbol: "macwindow", granted: captureAllowed,
                          action: openCaptureSettings)
            if !accessibilityAllowed {
                Label("未授权辅助功能时，右键仍可改写选中文字，结果需要复制。", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: refreshPermissions)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
    }

    private func refreshPermissions() {
        accessibilityAllowed = Accessibility.trusted
        captureAllowed = WindowCapture.permitted
    }

    private func openAccessibilitySettings() {
        if !accessibilityAllowed { Accessibility.requestPermission() }
        openPrivacyPane("Privacy_Accessibility")
        refreshPermissions()
    }

    private func openCaptureSettings() {
        if !captureAllowed { WindowCapture.requestPermission() }
        openPrivacyPane("Privacy_ScreenCapture")
        refreshPermissions()
    }

    private func openPrivacyPane(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
