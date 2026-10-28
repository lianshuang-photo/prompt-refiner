import AppKit
import RefinerCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = Coordinator()
    let services = RefinerServices()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        services.coordinator = coordinator; NSApp.servicesProvider = services
        NSUpdateDynamicServices(); coordinator.start()
        if CommandLine.arguments.contains("--settings") { coordinator.showSettings() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator.showSettings()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) { coordinator.shutdown() }
}

@MainActor final class RefinerServices: NSObject {
    weak var coordinator: Coordinator?
    @objc func refinePrompt(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "请先选择要细化的文字。"; return
        }
        coordinator?.trigger(suppliedText: text)
    }
}

@main struct PromptRefinerMain {
    @MainActor static func main() {
        func option(_ name: String) -> String? {
            guard let index = CommandLine.arguments.firstIndex(of: name), index + 1 < CommandLine.arguments.count else { return nil }
            return CommandLine.arguments[index + 1]
        }
        if CommandLine.arguments.contains("--context-check") {
            guard let bundleID = option("--source-bundle"), let anchor = option("--anchor") else {
                fputs("context-check requires --source-bundle and --anchor.\n", stderr); exit(1)
            }
            let context = ConversationStore().lookup(bundleID: bundleID, anchors: [anchor])
            let report: [String: Any] = ["matched": context != nil, "characters": context?.text.count ?? 0,
                                       "project_available": context?.projectDirectory != nil]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) { print(String(decoding: data, as: UTF8.self)) }
            return
        }
        if CommandLine.arguments.contains("--smoke-check") {
            let client = CodexClient()
            let draft = option("--draft-text") ?? "请以最小改动修复当前问题，并验证相关行为。"
            let imageIndex = CommandLine.arguments.firstIndex(of: "--image")
            let image = imageIndex.flatMap { $0+1 < CommandLine.arguments.count ? try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[$0+1])) : nil }
            do {
                let explicitProject = option("--project").map { URL(fileURLWithPath: $0) }
                if explicitProject != nil && RewriteRequest.validatedProjectDirectory(explicitProject) == nil { throw RefinerError.message("测试工程目录无效。") }
                let request = RewriteRequest(draft: draft, applicationName: "PromptRefiner", windowTitle: "Smoke check", projectDirectory: explicitProject)
                let result = try client.runBlocking(request, screenshotData: image, configuration: CodexConfiguration(executable: CodexClient.locateExecutable()), onProgress: { event in
                    fputs("progress: \(event.rawValue)\n", stderr)
                })
                fputs("project_queries: \(client.completedProjectReadCommands)\n", stderr)
                let encoded = try JSONEncoder().encode(result)
                print(String(decoding: encoded, as: UTF8.self))
            } catch { fputs("smoke-check failed: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        let application = NSApplication.shared
        let delegate = AppDelegate(); application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
