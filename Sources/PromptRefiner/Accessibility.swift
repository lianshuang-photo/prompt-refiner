import AppKit
import ApplicationServices
import RefinerCore

enum Accessibility {
    static var trusted: Bool { AXIsProcessTrusted() }
    static func requestPermission() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    static func string(_ element: AXUIElement, _ name: String) -> String? { attribute(element, name) as? String }
    static func label(_ element: AXUIElement) -> String? {
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute] {
            if let text = string(element, attribute), !text.isEmpty { return text }
        }
        return nil
    }
    static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
    static func selection(_ element: AXUIElement) -> NSRange? {
        guard let raw = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = unsafeBitCast(raw, to: AXValue.self); var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
    static func setSelection(_ element: AXUIElement, _ range: NSRange) -> Bool {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }
    static func canSet(_ element: AXUIElement, _ name: String) -> Bool {
        var writable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name as CFString, &writable) == .success && writable.boolValue
    }
    static func focused(for pid: pid_t) -> AXUIElement? {
        element(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute)
    }
    static func anchors(_ window: AXUIElement) -> [String] {
        var titles: [String] = []
        if let title = string(window, kAXTitleAttribute), !title.isEmpty { titles.append(title) }
        var queue: [(AXUIElement, Int)] = [(window, 0)]; var visited = 0
        while !queue.isEmpty && visited < 350 {
            let (node, depth) = queue.removeFirst(); visited += 1
            if let selected = attribute(node, kAXSelectedAttribute) as? Bool, selected,
               let label = label(node),
               !label.isEmpty && label.count < 180 { titles.append(label) }
            if let selected = attribute(node, kAXSelectedChildrenAttribute) as? [AXUIElement] {
                for item in selected {
                    if let label = label(item),
                       !label.isEmpty && label.count < 180 { titles.append(label) }
                }
            }
            if depth < 9, let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] {
                queue += children.prefix(60).map { ($0, depth + 1) }
            }
        }
        return Array(Set(titles)).sorted()
    }
    static func windowBounds(_ window: AXUIElement) -> CGRect? {
        guard let p = attribute(window, kAXPositionAttribute), let s = attribute(window, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(p, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(s, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
}

final class TargetSnapshot {
    let application: NSRunningApplication
    let field: AXUIElement
    let window: AXUIElement
    let originalText: String
    let selection: NSRange
    let editRange: NSRange
    let identity: TargetIdentity
    let anchors: [String]
    let conversation: ConversationContext?

    init(useConversation: Bool, suppliedSelection: String? = nil, originApplication: NSRunningApplication? = nil) throws {
        guard Accessibility.trusted else { throw RefinerError.message("请先在系统设置中允许“提示词细化”使用辅助功能，以读取和回填原输入框。") }
        guard let app = originApplication ?? NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let focused = Accessibility.focused(for: app.processIdentifier),
              let window = Accessibility.element(focused, kAXWindowAttribute)
                ?? Accessibility.element(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute) else {
            throw RefinerError.message("请把光标放到要改写的输入框，再按快捷键。")
        }
        let role = Accessibility.string(focused, kAXRoleAttribute) ?? ""
        let subrole = Accessibility.string(focused, kAXSubroleAttribute) ?? ""
        guard subrole != kAXSecureTextFieldSubrole,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role),
              let text = Accessibility.string(focused, kAXValueAttribute), !text.isEmpty,
              text.utf16.count <= 40_000,
              let range = Accessibility.selection(focused), range.location <= text.utf16.count,
              range.length <= text.utf16.count - range.location else {
            throw RefinerError.message("暂时无法读取这个输入框。可以通过右键服务选择文字，或在菜单栏中手动输入。")
        }
        application = app; field = focused; self.window = window
        originalText = text; selection = range
        editRange = range.length > 0 ? range : NSRange(location: 0, length: text.utf16.count)
        let selected = (text as NSString).substring(with: editRange)
        guard !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RefinerError.message("请先输入要细化的任务。") }
        _ = try TextEdit(original: text, range: editRange, replacement: selected)
        if let suppliedSelection, selected != suppliedSelection { throw RefinerError.message("右键传入的选区与当前输入框不一致。结果将通过卡片展示。") }
        anchors = Accessibility.anchors(window)
        conversation = useConversation ? ConversationStore().lookup(bundleID: app.bundleIdentifier ?? "", anchors: anchors) : nil
        identity = TargetIdentity(processID: app.processIdentifier, windowTitle: Accessibility.string(window, kAXTitleAttribute) ?? "",
                                  contextKey: conversation?.key ?? anchors.joined(separator: "\u{1f}"))
    }
    var draft: String { (originalText as NSString).substring(with: editRange) }
    var appName: String { application.localizedName ?? "当前应用" }

    func currentIdentity() -> TargetIdentity {
        let currentAnchors = Accessibility.anchors(window)
        let currentConversation = conversation == nil ? nil : ConversationStore().lookup(bundleID: application.bundleIdentifier ?? "", anchors: currentAnchors)
        return TargetIdentity(processID: application.processIdentifier,
                              windowTitle: Accessibility.string(window, kAXTitleAttribute) ?? "",
                              contextKey: currentConversation?.key ?? currentAnchors.joined(separator: "\u{1f}"))
    }
    func currentText() -> String? { Accessibility.string(field, kAXValueAttribute) }
    func validationFailures(requireFrontmost: Bool, requireFocus: Bool = true, requireSelection: Bool = true) -> [String] {
        var failures: [String] = []
        if application.isTerminated { failures.append("application_closed") }
        if currentIdentity() != identity { failures.append("context_changed") }
        if currentText() != originalText { failures.append("draft_changed") }
        if requireSelection && Accessibility.selection(field) != selection { failures.append("selection_changed") }
        if requireFrontmost && NSWorkspace.shared.frontmostApplication?.processIdentifier != application.processIdentifier { failures.append("frontmost_changed") }
        if requireFocus {
            if let focused = Accessibility.focused(for: application.processIdentifier) {
                if !CFEqual(focused, field) { failures.append("focused_element_changed") }
            } else { failures.append("focused_element_unavailable") }
        }
        return failures
    }
    func contentStillOriginal() -> Bool {
        validationFailures(requireFrontmost: false, requireFocus: false, requireSelection: false).isEmpty
    }
    func restoreFocusForExplicitApply() -> Bool {
        if let focused = Accessibility.focused(for: application.processIdentifier), CFEqual(focused, field) { return true }
        guard Accessibility.canSet(field, kAXFocusedAttribute),
              AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success,
              let focused = Accessibility.focused(for: application.processIdentifier) else { return false }
        return CFEqual(focused, field)
    }
    func isStillOriginal(interactionChanged: Bool, requireFrontmost: Bool) -> Bool {
        !interactionChanged && validationFailures(requireFrontmost: requireFrontmost).isEmpty
    }

    func replace(with value: String, range: NSRange? = nil, expectedText: String, allowPaste: Bool = true) async throws {
        guard let before = currentText() else { throw RefinerError.message("原输入框已经不可用。请复制结果。") }
        guard before == expectedText else { throw RefinerError.message("原稿刚刚发生变化，结果未自动应用。请复制结果。") }
        let changing = range ?? NSRange(location: 0, length: before.utf16.count)
        let edit = try TextEdit(original: before, range: changing, replacement: value)
        if Accessibility.canSet(field, kAXValueAttribute),
           AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, edit.result as CFString) == .success {
            _ = Accessibility.setSelection(field, NSRange(location: changing.location + value.utf16.count, length: 0))
        } else if Accessibility.canSet(field, kAXSelectedTextAttribute), Accessibility.setSelection(field, changing),
                  AXUIElementSetAttributeValue(field, kAXSelectedTextAttribute as CFString, value as CFString) == .success {
            // The native element owns selection/undo behavior for this route.
        } else {
            guard allowPaste, NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier,
                  let focused = Accessibility.focused(for: application.processIdentifier), CFEqual(focused, field),
                  Accessibility.setSelection(field, changing) else { throw RefinerError.message("这个输入框不支持自动回填。请复制结果后粘贴。") }
            let saved = ClipboardSnapshot()
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
            let ownedCount = NSPasteboard.general.changeCount
            defer { saved.restore(ifUnchangedSince: ownedCount) }
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { throw RefinerError.message("无法向原输入框粘贴。请复制结果。") }
            down.flags = .maskCommand; up.flags = .maskCommand
            down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
            for _ in 0..<15 {
                try await Task.sleep(nanoseconds: 30_000_000)
                if currentText() == edit.result { break }
            }
        }
        guard currentText() == edit.result else { throw RefinerError.message("未能确认结果已写入原输入框。请查看结果卡片。") }
    }
}

private struct ClipboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]
    init() {
        items = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }
    func restore(ifUnchangedSince count: Int) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == count else { return }
        pasteboard.clearContents()
        let restored = items.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem(); for (type, data) in values { item.setData(data, forType: type) }; return item
        }
        pasteboard.writeObjects(restored)
    }
}

final class TargetMonitor {
    private var observer: AXObserver?
    private var registrations: [(AXUIElement, CFString)] = []
    private var workspaceObserver: NSObjectProtocol?
    private(set) var changed = false
    private(set) var reasons: [String] = []
    private let target: TargetSnapshot
    init(target: TargetSnapshot) {
        self.target = target
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, name, reference in
            guard let reference else { return }
            Unmanaged<TargetMonitor>.fromOpaque(reference).takeUnretainedValue().observe(name as String)
        }
        if AXObserverCreate(target.application.processIdentifier, callback, &created) == .success, let created {
            observer = created
            for (element, notification) in [(target.field, kAXValueChangedNotification), (target.field, kAXSelectedTextChangedNotification),
                                            (AXUIElementCreateApplication(target.application.processIdentifier), kAXFocusedUIElementChangedNotification),
                                            (AXUIElementCreateApplication(target.application.processIdentifier), kAXFocusedWindowChangedNotification)] {
                let name = notification as CFString
                if AXObserverAddNotification(created, element, name, Unmanaged.passUnretained(self).toOpaque()) == .success {
                    registrations.append((element, name))
                }
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.processIdentifier != target.application.processIdentifier && app.processIdentifier != ProcessInfo.processInfo.processIdentifier { self?.mark("external_application_changed") }
        }
    }
    private func mark(_ reason: String) {
        changed = true
        if !reasons.contains(reason) { reasons.append(reason) }
    }
    private func observe(_ name: String) {
        // Some web editors emit accessibility notifications during layout even
        // when text/focus is unchanged. Compare actual state before invalidating.
        if name == kAXValueChangedNotification && target.currentText() != target.originalText { mark("draft_edited") }
        if name == kAXSelectedTextChangedNotification && Accessibility.selection(target.field) != target.selection { mark("selection_moved") }
        if name == kAXFocusedWindowChangedNotification && target.currentIdentity() != target.identity { mark("source_context_changed") }
        if name == kAXFocusedUIElementChangedNotification {
            if let focused = Accessibility.focused(for: target.application.processIdentifier), !CFEqual(focused, target.field) { mark("source_focus_moved") }
        }
    }
    func stop() {
        if let observer {
            for (element, name) in registrations { AXObserverRemoveNotification(observer, element, name) }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil; registrations = []
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        workspaceObserver = nil
    }
    deinit { stop() }
}
