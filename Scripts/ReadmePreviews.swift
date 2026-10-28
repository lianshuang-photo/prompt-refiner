import AppKit
import RefinerCore
import SwiftUI

/// Offscreen exports of the real settings views with isolated example preferences.
@main struct ReadmePreviews {
    @MainActor static func main() throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.appearance = NSAppearance(named: .aqua)
        UserDefaults.standard.setVolatileDomain([
            "codexPath": "/Users/you/.local/bin/codex", "model": "", "effort": "low",
            "autoApply": true, "captureWindow": true, "useConversation": true,
            "rewriteStyle": "augment", "keyCode": 35, "modifiers": 6144,
            "shortcutLabel": "⌃⌥P", "onboardingShown": true
        ], forName: UserDefaults.argumentDomain)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let coordinator = Coordinator()
        for (name, tab, height) in [("settings", SettingsTab.general, 820.0), ("strategies", SettingsTab.advanced, 620.0)] {
            let view = SettingsView(settings: coordinator.settings, coordinator: coordinator, initialTab: tab)
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: height),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "提示词细化 · 设置"
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.contentMinSize = NSSize(width: 680, height: height)
            window.setContentSize(NSSize(width: 680, height: height))
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            window.displayIfNeeded()
            guard let frame = window.contentView?.superview,
                  let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else {
                throw CocoaError(.fileWriteUnknown)
            }
            frame.cacheDisplay(in: frame.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: output.appendingPathComponent(name + ".png"))
            window.close()
        }
    }
}
