import AppKit
import Carbon
import RefinerCore
import ServiceManagement
import SwiftUI

@MainActor final class Settings: ObservableObject {
    private let defaults = UserDefaults.standard
    @Published var codexPath: String { didSet { defaults.set(codexPath, forKey: "codexPath") } }
    @Published var model: String { didSet { defaults.set(model, forKey: "model") } }
    @Published var effort: String { didSet { defaults.set(effort, forKey: "effort") } }
    @Published var autoApply: Bool { didSet { defaults.set(autoApply, forKey: "autoApply") } }
    @Published var captureWindow: Bool { didSet { defaults.set(captureWindow, forKey: "captureWindow") } }
    @Published var useConversation: Bool { didSet { defaults.set(useConversation, forKey: "useConversation") } }
    @Published var rewriteStyle: RewriteStyle { didSet { defaults.set(rewriteStyle.rawValue, forKey: "rewriteStyle") } }
    @Published var keyCode: UInt32 { didSet { defaults.set(keyCode, forKey: "keyCode") } }
    @Published var modifiers: UInt32 { didSet { defaults.set(modifiers, forKey: "modifiers") } }
    @Published var shortcutLabel: String { didSet { defaults.set(shortcutLabel, forKey: "shortcutLabel") } }
    init() {
        codexPath = defaults.string(forKey: "codexPath") ?? CodexClient.locateExecutable()
        model = defaults.string(forKey: "model") ?? ""
        effort = defaults.string(forKey: "effort") ?? "low"
        autoApply = defaults.object(forKey: "autoApply") as? Bool ?? true
        captureWindow = defaults.object(forKey: "captureWindow") as? Bool ?? true
        useConversation = defaults.object(forKey: "useConversation") as? Bool ?? true
        rewriteStyle = defaults.string(forKey: "rewriteStyle").flatMap(RewriteStyle.init(rawValue:)) ?? .augment
        // Keep legacy free-form rules in preferences for recovery; current requests use a preset.
        keyCode = UInt32(defaults.object(forKey: "keyCode") as? Int ?? 35)
        modifiers = UInt32(defaults.object(forKey: "modifiers") as? Int ?? Int(controlKey | optionKey))
        shortcutLabel = defaults.string(forKey: "shortcutLabel") ?? "⌃⌥P"
    }
    var configuration: CodexConfiguration { CodexConfiguration(executable: codexPath, model: model, effort: effort) }
}

final class GlobalHotkey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?
    init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, pointer -> OSStatus in
            guard let pointer else { return noErr }
            let instance = Unmanaged<GlobalHotkey>.fromOpaque(pointer).takeUnretainedValue()
            instance.action?(); return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(keyCode: UInt32, modifiers: UInt32) throws {
        if let reference { UnregisterEventHotKey(reference); self.reference = nil }
        let id = EventHotKeyID(signature: 0x50524631, id: 1)
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr else { throw RefinerError.message("快捷键注册失败（\(status)），请换一个组合。") }
    }
    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let label: String
    var recorded: (UInt32, UInt32, String) -> Void
    func makeNSView(context: Context) -> RecorderButton { let view = RecorderButton(); view.recorded = recorded; return view }
    func updateNSView(_ view: RecorderButton, context: Context) { view.normalLabel = label; if !view.recording { view.title = label }; view.recorded = recorded }
}

final class RecorderButton: NSButton {
    var normalLabel = "⌃⌥P"; var recording = false
    var recorded: ((UInt32, UInt32, String) -> Void)?
    private var monitor: Any?
    init() {
        super.init(frame: .zero); bezelStyle = .rounded; target = self; action = #selector(beginRecording)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func beginRecording() {
        guard !recording else { finish(); return }
        recording = true; title = "按下组合键（Esc 取消）"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.finish(); return nil }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !flags.intersection([.command, .control, .option]).isEmpty,
                  let characters = event.charactersIgnoringModifiers, characters.count == 1 else { return nil }
            var modifiers: UInt32 = 0; var label = ""
            if flags.contains(.control) { modifiers |= UInt32(controlKey); label += "⌃" }
            if flags.contains(.option) { modifiers |= UInt32(optionKey); label += "⌥" }
            if flags.contains(.shift) { modifiers |= UInt32(shiftKey); label += "⇧" }
            if flags.contains(.command) { modifiers |= UInt32(cmdKey); label += "⌘" }
            label += characters.uppercased()
            self.recorded?(UInt32(event.keyCode), modifiers, label); self.normalLabel = label; self.finish(); return nil
        }
    }
    private func finish() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; recording = false; title = normalLabel }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
