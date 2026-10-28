import AppKit
import Combine
import RefinerCore
import SwiftUI

@MainActor final class Coordinator: NSObject, ObservableObject, NSWindowDelegate {
    let settings = Settings()
    @Published var status = "就绪 · 把光标放到输入框，按 ⌃⌥P"
    @Published var busy = false
    @Published var result: RewriteResult?
    @Published var originalDraft = ""
    @Published var resultNote = ""
    @Published var sourceDescription = ""
    @Published var canApply = false
    @Published var manualDraft = ""
    @Published var hasUndo = false
    @Published var editedPrompt = ""
    @Published var progressLines: [String] = []
    @Published var progressStage = "准备改写"
    @Published var elapsedSeconds = 0
    @Published var sourceDetails: [String] = []
    @Published var noticeTone: NoticeTone = .neutral
    private var target: TargetSnapshot?
    private var monitor: TargetMonitor?
    private var worker: CodexClient?
    private var retiringWorkers: [CodexClient] = []
    private var task: Task<Void, Never>?
    private var requestID: UUID?
    private var undoRecord: (TargetSnapshot, TextEdit)?
    private let hotkey = GlobalHotkey()
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var resultWindow: NSWindow?
    private var manualWindow: NSWindow?
    private var toast: NSPanel?
    private var toastDismiss: DispatchWorkItem?
    private var progressPanel: NSPanel?
    private var compactResultPanel: NSPanel?
    private var elapsedTimer: Timer?
    private var startedAt: Date?
    private var originObserver: NSObjectProtocol?
    private var lastExternalApp: NSRunningApplication?
    private var lastExternalAt: Date?
    private var inputIssue = ""
    private var currentTrigger: TriggerKind = .manual
    private var currentRewriteStyle: RewriteStyle = .augment
    private var screenshotUsed = false
    private var contextUsed = false
    private var contextCharacters = 0
    private var projectDirectory: URL?
    private var projectReadCommands = 0
    private var validationIssues: [String] = []
    private static let menuBarIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "StatusIcon", withExtension: "pdf"), let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 18, height: 18); image.isTemplate = true
        image.accessibilityDescription = "提示词细化"
        return image
    }()

    func start() {
        rememberOrigin(NSWorkspace.shared.frontmostApplication)
        originObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.rememberOrigin(app) }
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.menuBarIcon ?? NSImage(systemSymbolName: "text.badge.star", accessibilityDescription: "提示词细化")
        statusItem.button?.toolTip = "提示词细化"
        hotkey.action = { [weak self] in self?.trigger() }
        updateHotkey(); updateMenu()
        if !UserDefaults.standard.bool(forKey: "onboardingShown") {
            UserDefaults.standard.set(true, forKey: "onboardingShown"); showSettings()
        }
    }
    func updateHotkey() {
        do { try hotkey.register(keyCode: settings.keyCode, modifiers: settings.modifiers); status = "就绪 · " + settings.shortcutLabel }
        catch { status = error.localizedDescription }
        updateMenu()
    }
    private func updateMenu() {
        guard statusItem != nil else { return }
        let menu = NSMenu()
        let label = NSMenuItem(title: status, action: nil, keyEquivalent: ""); label.isEnabled = false; menu.addItem(label)
        menu.addItem(.separator())
        add(menu, busy ? "取消本次改写" : "细化当前输入 · " + settings.shortcutLabel, #selector(menuTrigger))
        add(menu, "手动输入…", #selector(menuManual))
        if result != nil { add(menu, "查看最近结果…", #selector(menuResult)) }
        if hasUndo { add(menu, "撤销上次回填", #selector(menuUndo)) }
        menu.addItem(.separator()); add(menu, "设置…", #selector(menuSettings)); add(menu, "退出", #selector(menuQuit))
        statusItem.menu = menu
        statusItem.button?.image = Self.menuBarIcon ?? NSImage(systemSymbolName: busy ? "ellipsis.circle" : "text.badge.star", accessibilityDescription: busy ? "正在细化" : "提示词细化")
        statusItem.button?.toolTip = busy ? "提示词细化 · 正在处理" : "提示词细化 · " + settings.shortcutLabel
    }
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) { let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item) }
    @objc private func menuTrigger() { trigger() }
    @objc private func menuManual() { showManual() }
    @objc private func menuResult() { showResult() }
    @objc private func menuSettings() { showSettings() }
    @objc private func menuUndo() { undoLast() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    private func rememberOrigin(_ app: NSRunningApplication?) {
        guard let app else { return }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            if lastExternalApp != nil { lastExternalAt = Date() }
            return
        }
        lastExternalApp = app; lastExternalAt = Date()
    }
    private func sourceApplication() -> NSRunningApplication? {
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier { return app }
        if let time = lastExternalAt, Date().timeIntervalSince(time) < 5 { return lastExternalApp }
        return nil
    }
    func trigger(suppliedText: String? = nil) {
        if busy { cancel(); return }
        let kind: TriggerKind = suppliedText == nil ? .hotkey : .service
        let origin = WindowOrigin.capture(application: sourceApplication())
        do {
            let snapshot = try TargetSnapshot(useConversation: settings.useConversation, suppliedSelection: suppliedText, originApplication: origin?.application)
            begin(target: snapshot, origin: origin, draft: snapshot.draft, kind: kind)
        } catch {
            if let suppliedText, !suppliedText.isEmpty {
                begin(target: nil, origin: origin, draft: suppliedText, kind: kind, issue: error.localizedDescription)
            } else {
                status = error.localizedDescription; resultNote = status; noticeTone = .warning
                showToast(status, actions: false); updateMenu()
                if !Accessibility.trusted { showSettings() }
            }
        }
    }
    func runManual() {
        let text = manualDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty && text.utf16.count <= 40_000 && !busy else { return }
        manualWindow?.orderOut(nil); begin(target: nil, origin: nil, draft: text, kind: .manual)
    }
    private func begin(target snapshot: TargetSnapshot?, origin: WindowOrigin?, draft: String, kind: TriggerKind, issue: String = "") {
        let id = UUID(); requestID = id
        target = snapshot; originalDraft = draft; result = nil; editedPrompt = ""; canApply = false
        resultNote = ""; noticeTone = .neutral; inputIssue = issue; currentTrigger = kind
        currentRewriteStyle = settings.rewriteStyle
        screenshotUsed = false; contextUsed = false
        let conversation = snapshot?.conversation ?? (settings.useConversation ? origin.flatMap { ConversationStore().lookup(bundleID: $0.application.bundleIdentifier ?? "", anchors: [$0.title]) } : nil)
        sourceDescription = kind.displayName + (origin.map { " · " + $0.name } ?? "")
        sourceDetails = ["原稿：\(draft.count) 字", snapshot == nil ? (issue.isEmpty ? "回填：此模式没有原输入框" : "回填：" + issue) : "回填：已绑定原输入框",
                         conversation == nil ? "会话：未读取原会话，本次不猜测历史" : "会话：已读取原会话 · \(conversation!.title)（\(conversation!.text.count) 字）"]
        contextUsed = conversation != nil
        projectDirectory = conversation?.projectDirectory; projectReadCommands = 0
        sourceDetails.append(projectDirectory.map { "工程：已定位 \($0.lastPathComponent)，可只读检索" } ?? "工程：未定位，本次仅使用已提供的素材")
        contextCharacters = conversation?.text.count ?? 0; validationIssues = []
        progressLines = []; elapsedSeconds = 0; startedAt = Date()
        addProgress("已读取\(kind.displayName)原稿，共 \(draft.count) 字")
        if !issue.isEmpty { addProgress(Accessibility.trusted ? "原输入框绑定不可用，将保留为可复制结果" : "辅助功能未授权，保留右键文字与可用窗口截图") }
        if conversation != nil { addProgress("已找到相关原会话") }
        monitor = snapshot.map(TargetMonitor.init)
        let client = CodexClient(); worker = client; busy = true; status = "正在读取上下文…"; updateMenu()
        startElapsedTimer(); showProgressPanel()
        let config = settings.configuration; let instructions = currentRewriteStyle.instructions
        let capture = settings.captureWindow
        let request = RewriteRequest(draft: draft, applicationName: origin?.name ?? snapshot?.appName ?? kind.displayName,
                                     windowTitle: origin?.title ?? snapshot?.identity.windowTitle ?? "", context: conversation?.text ?? "", instructions: instructions, projectDirectory: projectDirectory)
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.retiringWorkers.removeAll { $0 === client } }
            do {
                var screenshot: Data?
                if capture && kind != .manual {
                    if WindowCapture.permitted {
                        do {
                            if self.monitor?.changed == true { throw RefinerError.message("截图前目标发生变化，未混入新窗口内容。") }
                            if let snapshot { screenshot = try await WindowCapture.screenshot(target: snapshot) }
                            else if let origin { screenshot = try await WindowCapture.screenshot(origin: origin) }
                            else { throw RefinerError.message("未明确识别原窗口，本次仅使用文字。") }
                            if self.monitor?.changed == true { screenshot = nil; throw RefinerError.message("截图期间输入发生变化，本次仅使用原稿文字。") }
                            self.screenshotUsed = screenshot != nil
                            self.sourceDetails.append("截图：已截取原窗口")
                            self.addProgress("原窗口截图已准备好")
                        } catch { self.sourceDetails.append("截图：" + error.localizedDescription); self.addProgress("截图不可用，继续使用已取得的文字上下文") }
                    } else { self.sourceDetails.append("截图：屏幕录制未授权"); self.addProgress("屏幕录制未授权，本次继续文字改写") }
                } else { self.sourceDetails.append(kind == .manual ? "截图：手动输入模式未截屏" : "截图：设置已关闭") }
                try Task.checkCancellation()
                guard self.requestID == id else { return }
                self.status = "正在细化提示词…"; self.updateMenu(); self.writeRunReceipt(event: "generating")
                let answer = try await client.run(request, screenshotData: screenshot, configuration: config, onProgress: { [weak self] event in
                    Task { @MainActor in
                        guard let self, self.requestID == id else { return }
                        self.addProgress(event.publicMessage)
                    }
                })
                guard self.requestID == id else { return }
                self.projectReadCommands = client.completedProjectReadCommands
                if let project = self.projectDirectory {
                    self.sourceDetails.removeAll { $0.hasPrefix("工程：") }
                    self.sourceDetails.append(self.projectReadCommands > 0 ? "工程：\(project.lastPathComponent)，已完成 \(self.projectReadCommands) 次只读查询" : "工程：\(project.lastPathComponent)，本次未调用工程查询")
                }
                let changed = self.monitor?.changed ?? true
                let monitorReasons = self.monitor?.reasons ?? []
                self.monitor?.stop(); self.monitor = nil
                self.result = answer; self.editedPrompt = answer.rewrittenPrompt; self.busy = false; self.worker = nil
                self.finishProgress()
                self.canApply = snapshot?.contentStillOriginal() ?? false
                self.validationIssues = snapshot?.validationFailures(requireFrontmost: true) ?? ["input_unbound"]
                self.validationIssues += monitorReasons
                if self.settings.autoApply, !answer.requiresReview,
                   let snapshot, snapshot.isStillOriginal(interactionChanged: changed, requireFrontmost: true) {
                    do {
                        try await self.write(answer, to: snapshot)
                        self.status = "已细化并回填"; self.showToast("已细化 · 查看改动 / 撤销", actions: true, allowUndo: true)
                    } catch {
                        self.resultNote = error.localizedDescription; self.noticeTone = .warning; self.status = "改写已完成，等待应用"; self.writeRunReceipt(event: "writeback_failed"); self.presentBackgroundResult()
                    }
                } else {
                    self.status = "改写已完成，等待应用"
                    if answer.requiresReview { self.resultNote = "存在影响任务范围的关键歧义，请检查后应用。"; self.noticeTone = .warning }
                    else if !issue.isEmpty { self.resultNote = !Accessibility.trusted ? "辅助功能未授权，暂不能回填。已保留右键原稿和可用上下文，可以复制结果。" : issue }
                    else if changed && snapshot != nil { self.resultNote = "等待期间输入或目标发生变化，原稿没有被覆盖。" }
                    else if snapshot == nil { self.resultNote = "结果已就绪，可编辑后复制。" }
                    else if !answer.assumptions.isEmpty { self.resultNote = "已补充常规语境说明，可按需展开查看。" }
                    self.writeRunReceipt(event: "ready_for_review")
                    self.presentBackgroundResult()
                }
                self.updateMenu()
            } catch {
                guard self.requestID == id else { return }
                self.monitor?.stop(); self.monitor = nil; self.busy = false; self.worker = nil
                self.finishProgress()
                self.status = error is CancellationError ? "已取消 · 原稿保留" : error.localizedDescription
                self.writeRunReceipt(event: error is CancellationError ? "cancelled" : "failed")
                self.showToast(self.status, actions: false); self.updateMenu()
            }
        }
    }
    private func write(_ answer: RewriteResult, to snapshot: TargetSnapshot) async throws {
        let edit = try TextEdit(original: snapshot.originalText, range: snapshot.editRange, replacement: answer.rewrittenPrompt)
        try await snapshot.replace(with: answer.rewrittenPrompt, range: snapshot.editRange, expectedText: snapshot.originalText)
        undoRecord = (snapshot, edit); hasUndo = true; canApply = false
        writeRunReceipt(event: "applied")
    }
    func applyResult() {
        guard var answer = result, let snapshot = target, snapshot.contentStillOriginal() else {
            canApply = false; resultNote = "原输入框或原稿已变化，请复制结果到你需要的位置。"; return
        }
        answer.rewrittenPrompt = editedPrompt
        resultWindow?.orderOut(nil); compactResultPanel?.orderOut(nil)
        snapshot.application.activate(options: [])
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard snapshot.contentStillOriginal(), NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.application.processIdentifier,
                  snapshot.restoreFocusForExplicitApply(), Accessibility.setSelection(snapshot.field, snapshot.selection) else {
                self.validationIssues = snapshot.validationFailures(requireFrontmost: true)
                self.resultNote = "原输入框或原稿已变化，未自动覆盖。"; self.canApply = false; self.presentBackgroundResult(); return
            }
            do { try await self.write(answer, to: snapshot); self.status = "已回填"; self.showToast("已回填 · 查看改动 / 撤销", actions: true, allowUndo: true); self.updateMenu() }
            catch { self.resultNote = error.localizedDescription; self.presentBackgroundResult() }
        }
    }
    func undoLast() {
        guard let (snapshot, edit) = undoRecord, snapshot.currentIdentity() == snapshot.identity,
              let text = snapshot.currentText() else { resultNote = "原窗口已经变化，请在结果卡片中复制原稿。"; showResult(); return }
        do {
            _ = try edit.undo(in: text)
            resultWindow?.orderOut(nil); compactResultPanel?.orderOut(nil)
            snapshot.application.activate(options: [])
            Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard snapshot.currentIdentity() == snapshot.identity,
                      let current = snapshot.currentText(), (try? edit.undo(in: current)) != nil,
                      snapshot.restoreFocusForExplicitApply() else {
                    self.resultNote = "改写内容或原窗口已经变化，未自动撤销。"; self.showResult(); return
                }
                do {
                    try await snapshot.replace(with: edit.selectedOriginal, range: edit.insertedRange, expectedText: current)
                    self.undoRecord = nil; self.hasUndo = false; self.status = "已撤销，保留其他输入"; self.showToast(self.status, actions: false); self.updateMenu()
                } catch { self.resultNote = error.localizedDescription; self.showResult() }
            }
        } catch { resultNote = error.localizedDescription; showResult() }
    }
    func cancel() {
        requestID = nil; task?.cancel()
        if let worker { retiringWorkers.append(worker); worker.cancel() }
        worker = nil
        monitor?.stop(); monitor = nil; busy = false; status = "已取消 · 原稿保留"
        finishProgress(); writeRunReceipt(event: "cancelled")
        toast?.orderOut(nil); updateMenu()
    }
    func shutdown() {
        requestID = nil; task?.cancel(); worker?.shutdown(); worker = nil
        for client in retiringWorkers { client.shutdown() }
        retiringWorkers.removeAll()
        monitor?.stop(); monitor = nil
        finishProgress()
        if let originObserver { NSWorkspace.shared.notificationCenter.removeObserver(originObserver) }; originObserver = nil
    }
    func copyResult() { if result != nil { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(editedPrompt, forType: .string) } }
    func copyOriginal() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(originalDraft, forType: .string) }

    private func addProgress(_ message: String) {
        if progressStage == message && !progressLines.isEmpty { return }
        progressStage = message
        let elapsed = startedAt.map { max(0, Int(Date().timeIntervalSince($0))) } ?? 0
        progressLines.append("\(elapsed)s  " + message)
        if progressLines.count > 12 { progressLines.removeFirst(progressLines.count-12) }
    }
    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let started = self.startedAt else { return }
                self.elapsedSeconds = max(0, Int(Date().timeIntervalSince(started)))
            }
        }
    }
    private func finishProgress() {
        if let startedAt { elapsedSeconds = max(0, Int(Date().timeIntervalSince(startedAt))) }
        elapsedTimer?.invalidate(); elapsedTimer = nil; progressPanel?.orderOut(nil)
    }
    private func writeRunReceipt(event: String) {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/PromptRefiner")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let report: [String: Any] = ["request_id": requestID?.uuidString ?? "", "event": event,
                                       "checked_at_utc": ISO8601DateFormatter().string(from: Date()),
                                       "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
                                       "trigger": currentTrigger.rawValue, "screenshot_used": screenshotUsed,
                                       "session_context_used": contextUsed, "session_context_characters": contextCharacters, "input_bound": target != nil,
                                       "project_context_available": projectDirectory != nil, "project_read_commands": projectReadCommands,
                                       "prompt_version": "0.3.3", "rewrite_style": currentRewriteStyle.rawValue,
                                       "requested_model": settings.model, "reasoning_effort": settings.effort,
                                       "validation_failures": validationIssues, "codex_completed": result != nil,
                                       "binding_issue": inputIssue, "elapsed_seconds": elapsedSeconds,
                                       "output_characters": editedPrompt.count, "accessibility_permission": Accessibility.trusted,
                                       "screen_capture_permission": WindowCapture.permitted]
            let path = directory.appendingPathComponent("last-run.json")
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: path, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        } catch { /* Diagnostic persistence must never prevent the user's rewrite. */ }
    }
    private func showProgressPanel() {
        toast?.orderOut(nil); compactResultPanel?.orderOut(nil)
        if progressPanel == nil {
            let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 228), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.hidesOnDeactivate = false
            panel.contentView = NSHostingView(rootView: GenerationPanelView(coordinator: self)); progressPanel = panel
        }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        if let frame = screen?.visibleFrame { progressPanel?.setFrameOrigin(NSPoint(x: frame.maxX-520, y: frame.maxY-252)) }
        progressPanel?.orderFrontRegardless()
    }

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = window(title: "提示词细化 · 设置", view: SettingsView(settings: settings, coordinator: self), size: NSSize(width: 620, height: 620))
            settingsWindow?.delegate = self
        }
        NSApp.setActivationPolicy(.regular)
        show(settingsWindow)
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }
    func showResult() {
        toast?.orderOut(nil); compactResultPanel?.orderOut(nil)
        if resultWindow == nil { resultWindow = window(title: "提示词细化 · 改写结果", view: ResultView(coordinator: self), size: NSSize(width: 650, height: 520)) }
        show(resultWindow)
    }
    private func presentBackgroundResult() {
        toast?.orderOut(nil)
        if compactResultPanel == nil {
            let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 360), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.hidesOnDeactivate = false
            panel.contentView = NSHostingView(rootView: CompactResultPanelView(coordinator: self)); compactResultPanel = panel
        }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        if let frame = screen?.visibleFrame { compactResultPanel?.setFrameOrigin(NSPoint(x: frame.maxX-520, y: frame.maxY-384)) }
        compactResultPanel?.orderFrontRegardless()
    }
    func dismissResultPanel() { compactResultPanel?.orderOut(nil) }
    func showManual() {
        if manualWindow == nil { manualWindow = window(title: "提示词细化 · 手动输入", view: ManualView(coordinator: self), size: NSSize(width: 580, height: 430)) }
        show(manualWindow)
    }
    private func window<V: View>(title: String, view: V, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false; window.contentView = NSHostingView(rootView: view); window.center(); return window
    }
    private func show(_ window: NSWindow?) { NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil) }
    private func showToast(_ message: String, actions: Bool, allowUndo: Bool = false, duration: TimeInterval = 7) {
        toastDismiss?.cancel()
        if toast == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 66), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.hidesOnDeactivate = false; toast = panel
        }
        let panel = toast!
        panel.contentView = NSHostingView(rootView: ToastView(message: message, actions: actions, allowUndo: allowUndo, view: { [weak self] in self?.showResult() }, undo: { [weak self] in self?.undoLast() }))
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        if let frame = screen?.visibleFrame { panel.setFrameOrigin(NSPoint(x: frame.maxX-440, y: frame.maxY-90)) }
        panel.orderFrontRegardless()
        let dismiss = DispatchWorkItem { [weak panel] in panel?.orderOut(nil) }
        toastDismiss = dismiss; DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: dismiss)
    }
}
