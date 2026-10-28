import AppKit
import Combine
import ServiceManagement
import SwiftUI

struct LoginItemRow: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var errorMessage = ""
    @State private var showsError = false
    @State private var needsApproval = SMAppService.mainApp.status == .requiresApproval

    var body: some View {
        VStack(alignment: .leading, spacing: RefinerDesign.compactSpacing) {
            SettingToggleRow(title: "开机启动", explanation: "登录后在菜单栏待命，按快捷键时才开始工作。", isOn: $enabled)
            if needsApproval {
                HStack(spacing: RefinerDesign.compactSpacing) {
                    Label("需要在登录项中允许后台运行。", systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("打开登录项", action: openLoginSettings).controlSize(.small)
                }
            }
        }
        .onChange(of: enabled) { _, newValue in updateLoginItem(newValue) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
        }
        .alert("无法更新开机启动", isPresented: $showsError) {
            Button("好", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func updateLoginItem(_ requested: Bool) {
        guard requested != (SMAppService.mainApp.status == .enabled) else { return }
        do {
            if requested { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            errorMessage = error.localizedDescription
            showsError = true
        }
        refreshStatus()
    }

    private func refreshStatus() {
        enabled = SMAppService.mainApp.status == .enabled
        needsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    private func openLoginSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
