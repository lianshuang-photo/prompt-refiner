import Foundation
import Darwin

public final class CodexClient: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var completedReads = 0
    public var completedProjectReadCommands: Int { lock.lock(); defer { lock.unlock() }; return completedReads }
    public init() {}

    public static func locateExecutable() -> String {
        let standalone = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path
        for candidate in ["/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                          "/Applications/Codex.app/Contents/Resources/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex", standalone] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return ""
    }

    public func cancel() {
        lock.lock(); cancelled = true; let running = process; lock.unlock()
        if running?.isRunning == true { running?.interrupt() }
    }
    /// App shutdown cannot leave an inference process running after the menu-bar
    /// process exits. Normal cancellation remains asynchronous for responsiveness.
    public func shutdown() {
        lock.lock(); cancelled = true; let running = process; lock.unlock()
        guard let running, running.isRunning else { return }
        running.interrupt()
        let first = Date().addingTimeInterval(0.3)
        while running.isRunning && Date() < first { Thread.sleep(forTimeInterval: 0.02) }
        if running.isRunning { kill(running.processIdentifier, SIGTERM) }
        let last = Date().addingTimeInterval(0.3)
        while running.isRunning && Date() < last { Thread.sleep(forTimeInterval: 0.02) }
        if running.isRunning { kill(running.processIdentifier, SIGKILL) }
    }

    public func run(_ request: RewriteRequest, screenshotData: Data?, configuration: CodexConfiguration, onProgress: (@Sendable (GenerationEvent) -> Void)? = nil) async throws -> RewriteResult {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do { continuation.resume(returning: try self.runBlocking(request, screenshotData: screenshotData, configuration: configuration, onProgress: onProgress)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { self.cancel() })
    }

    public func runBlocking(_ request: RewriteRequest, screenshotData: Data?, configuration: CodexConfiguration, onProgress: (@Sendable (GenerationEvent) -> Void)? = nil) throws -> RewriteResult {
        let project = RewriteRequest.validatedProjectDirectory(request.projectDirectory)
        if request.projectDirectory != nil && project == nil { throw RefinerError.message("原工程目录已不可用，本次未检索项目。") }
        guard FileManager.default.isExecutableFile(atPath: configuration.executable) else {
            throw RefinerError.message("找不到 Codex。请在设置中选择本机的 Codex 程序。")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("prompt-refiner-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = directory.appendingPathComponent("result.schema.json")
        let output = directory.appendingPathComponent("result.json")
        try Data(RewriteRequest.outputSchema.utf8).write(to: schema)
        var screenshot: URL?
        if let screenshotData {
            let path = directory.appendingPathComponent("window.png")
            try screenshotData.write(to: path, options: .atomic); screenshot = path
        }

        let child = Process(); let stdin = Pipe(); let stdout = Pipe(); let stderr = Pipe()
        child.executableURL = URL(fileURLWithPath: configuration.executable)
        child.arguments = configuration.arguments(directory: directory, screenshot: screenshot, schema: schema, output: output, projectDirectory: project)
        child.currentDirectoryURL = directory
        child.standardInput = stdin; child.standardOutput = stdout; child.standardError = stderr
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        child.environment = environment
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        process = child; completedReads = 0
        lock.unlock()
        defer { lock.lock(); process = nil; lock.unlock() }
        try child.run()
        onProgress?(.processStarted)
        defer {
            if child.isRunning {
                child.terminate()
                let deadline = Date().addingTimeInterval(0.4)
                while child.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
                child.waitUntilExit()
            }
        }

        // Never wait for pipe EOF: a Codex helper may inherit a descriptor after
        // the main invocation exits. Drain both streams without blocking instead.
        try? stdout.fileHandleForWriting.close(); try? stderr.fileHandleForWriting.close()
        let inputFD = stdin.fileHandleForWriting.fileDescriptor
        for fd in [inputFD, stdout.fileHandleForReading.fileDescriptor, stderr.fileHandleForReading.fileDescriptor] {
            let flags = fcntl(fd, F_GETFL)
            guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else {
                throw RefinerError.message("无法准备后台输入输出。原稿已保留。")
            }
        }
        _ = fcntl(inputFD, F_SETNOSIGPIPE, 1)
        defer {
            try? stdin.fileHandleForWriting.close()
            try? stdout.fileHandleForReading.close(); try? stderr.fileHandleForReading.close()
        }
        let inputData = Data(request.prompt.utf8)
        var inputOffset = 0; var inputClosed = false
        var captured = Data(); var discardedErrors = Data()
        var parsedBytes = 0; var progressParser = GenerationEventParser()
        let deadline = Date().addingTimeInterval(configuration.timeout)
        var timedOut = false
        while child.isRunning {
            lock.lock(); let stopped = cancelled; lock.unlock()
            if stopped || Date() >= deadline {
                timedOut = !stopped
                child.interrupt()
                let stopAt = Date().addingTimeInterval(2)
                while child.isRunning && Date() < stopAt { Thread.sleep(forTimeInterval: 0.04) }
                if child.isRunning { child.terminate() }
                let finalStop = Date().addingTimeInterval(0.4)
                while child.isRunning && Date() < finalStop { Thread.sleep(forTimeInterval: 0.02) }
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
                break
            }
            try Self.drain(stdout.fileHandleForReading, into: &captured, limit: 8_000_000, rejectOverflow: true)
            if captured.count > parsedBytes {
                for event in progressParser.consume(Data(captured[parsedBytes...])) { onProgress?(event) }
                parsedBytes = captured.count
            }
            try Self.drain(stderr.fileHandleForReading, into: &discardedErrors, limit: 0, rejectOverflow: false)
            if !inputClosed {
                let written = inputData.withUnsafeBytes { raw in
                    Darwin.write(inputFD, raw.baseAddress!.advanced(by: inputOffset), min(32_768, raw.count-inputOffset))
                }
                if written > 0 { inputOffset += written }
                else if written < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
                    throw RefinerError.message("Codex 未接收完整输入。原稿已保留。")
                }
                if inputOffset == inputData.count { try? stdin.fileHandleForWriting.close(); inputClosed = true; onProgress?(.inputSubmitted) }
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        child.waitUntilExit()
        try Self.drain(stdout.fileHandleForReading, into: &captured, limit: 8_000_000, rejectOverflow: true)
        if captured.count > parsedBytes {
            for event in progressParser.consume(Data(captured[parsedBytes...])) { onProgress?(event) }
        }
        try Self.drain(stderr.fileHandleForReading, into: &discardedErrors, limit: 0, rejectOverflow: false)
        lock.lock(); let stopped = cancelled; lock.unlock()
        if stopped { throw CancellationError() }
        if timedOut { throw RefinerError.message("改写超过等待时间。原稿已保留，可以重试或切换模型。") }
        guard child.terminationStatus == 0 else {
            // Do not expose raw CLI stderr: it can contain prompts, paths or credentials.
            throw RefinerError.message("Codex 未完成改写（退出码 \(child.terminationStatus)）。请检查登录、模型与网络。")
        }
        var completedIDs: Set<String> = []
        for (index, line) in captured.split(separator: 10).enumerated() {
            guard let event = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let item = event["item"] as? [String: Any], let type = item["type"] as? String else { continue }
            if type == "command_execution", project != nil {
                if event["type"] as? String == "item.completed", item["exit_code"] as? Int == 0 {
                    completedIDs.insert(item["id"] as? String ?? String(index))
                }
                continue
            }
            if ["command_execution", "file_change", "mcp_tool_call", "web_search", "collab_agent_tool_call"].contains(type) {
                throw RefinerError.message("改写调用出现了非文本操作，结果未应用。请检查 Codex 配置。")
            }
        }
        lock.lock(); completedReads = completedIDs.count; lock.unlock()
        onProgress?(.validating)
        let answer = try RewriteResult.decode(Data(contentsOf: output))
        onProgress?(.finished)
        return answer
    }
    private static func drain(_ handle: FileHandle, into data: inout Data, limit: Int, rejectOverflow: Bool) throws {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        for _ in 0..<128 {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(handle.fileDescriptor, $0.baseAddress, $0.count) }
            if count == 0 { return }
            if count < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                throw RefinerError.message("后台输出读取失败，结果未应用。")
            }
            if rejectOverflow && count > limit-data.count { throw RefinerError.message("后台输出超出限制，结果未应用。") }
            if data.count < limit { data.append(contentsOf: buffer.prefix(min(count, limit-data.count))) }
        }
    }
}
