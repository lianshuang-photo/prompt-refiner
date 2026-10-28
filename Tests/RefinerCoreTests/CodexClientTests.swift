import XCTest
@testable import RefinerCore

final class CodexClientTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("refiner-client-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    private func executable(_ body: String) throws -> String {
        let url = directory.appendingPathComponent("fake-codex")
        try Data(("#!/bin/sh\n" + body).utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url.path
    }
    private var request: RewriteRequest { RewriteRequest(draft: "只改写，不执行", applicationName: "测试", windowTitle: "测试") }
    func testLargeStderrDoesNotDeadlockAndResultIsParsed() throws {
        let path = try executable("""
        output=''
        while [ "$#" -gt 0 ]; do
          if [ "$1" = '--output-last-message' ]; then shift; output="$1"; fi
          shift
        done
        /bin/dd if=/dev/zero bs=65536 count=32 2>/dev/null >&2
        /bin/cat >/dev/null
        /usr/bin/printf '%s' '{"rewritten_prompt":"请细化范围并验证。","suggestions":[],"assumptions":[],"clarification_needed":false}' > "$output"
        /usr/bin/printf '%s\\n' '{"type":"item.completed","item":{"type":"agent_message","text":"完成"}}'
        """)
        let result = try CodexClient().runBlocking(request, screenshotData: nil, configuration: CodexConfiguration(executable: path, timeout: 5))
        XCTAssertEqual(result.rewrittenPrompt, "请细化范围并验证。")
    }
    func testTimeoutStopsProcess() throws {
        let path = try executable("exec /bin/sleep 10\n")
        let start = Date()
        XCTAssertThrowsError(try CodexClient().runBlocking(request, screenshotData: nil, configuration: CodexConfiguration(executable: path, timeout: 0.15)))
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
    }
    func testCancellationStopsProcessAndReturnsCancellation() throws {
        let path = try executable("exec /bin/sleep 10\n")
        let client = CodexClient()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { client.cancel() }
        XCTAssertThrowsError(try client.runBlocking(request, screenshotData: nil, configuration: CodexConfiguration(executable: path))) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }
    func testUnexpectedToolEventPreventsApplyingOutput() throws {
        let path = try executable("""
        output=''
        while [ "$#" -gt 0 ]; do
          if [ "$1" = '--output-last-message' ]; then shift; output="$1"; fi
          shift
        done
        /bin/cat >/dev/null
        /usr/bin/printf '%s' '{"rewritten_prompt":"结果","suggestions":[],"assumptions":[],"clarification_needed":false}' > "$output"
        /usr/bin/printf '%s\\n' '{"type":"item.started","item":{"type":"command_execution"}}'
        """)
        XCTAssertThrowsError(try CodexClient().runBlocking(request, screenshotData: nil, configuration: CodexConfiguration(executable: path)))
    }
    func testProjectQueriesAreAcceptedAndCountedOnlyWhenCompletedSuccessfully() throws {
        let path = try executable("""
        output=''
        while [ "$#" -gt 0 ]; do
          if [ "$1" = '--output-last-message' ]; then shift; output="$1"; fi
          shift
        done
        /bin/cat >/dev/null
        /usr/bin/printf '%s' '{"rewritten_prompt":"检查已定位的重试入口。","suggestions":[],"assumptions":[],"clarification_needed":false}' > "$output"
        /usr/bin/printf '%s\\n' '{"type":"item.started","item":{"id":"read-1","type":"command_execution"}}' '{"type":"item.completed","item":{"id":"read-1","type":"command_execution","exit_code":0}}' '{"type":"item.completed","item":{"id":"read-1","type":"command_execution","exit_code":0}}' '{"type":"item.completed","item":{"id":"read-2","type":"command_execution","exit_code":1}}'
        """)
        let client = CodexClient()
        let scoped = RewriteRequest(draft: "修下重试问题", applicationName: "测试", windowTitle: "测试", projectDirectory: directory)
        _ = try client.runBlocking(scoped, screenshotData: nil, configuration: CodexConfiguration(executable: path))
        XCTAssertEqual(client.completedProjectReadCommands, 1)
    }
    func testFileChangesStillRejectOutputInProjectMode() throws {
        let path = try executable("""
        output=''
        while [ "$#" -gt 0 ]; do
          if [ "$1" = '--output-last-message' ]; then shift; output="$1"; fi
          shift
        done
        /bin/cat >/dev/null
        /usr/bin/printf '%s' '{"rewritten_prompt":"结果","suggestions":[],"assumptions":[],"clarification_needed":false}' > "$output"
        /usr/bin/printf '%s\\n' '{"type":"item.completed","item":{"type":"file_change"}}'
        """)
        let scoped = RewriteRequest(draft: "只改写", applicationName: "测试", windowTitle: "测试", projectDirectory: directory)
        XCTAssertThrowsError(try CodexClient().runBlocking(scoped, screenshotData: nil, configuration: CodexConfiguration(executable: path)))
    }
    func testInheritedPipeDoesNotKeepFinishedRequestWaiting() throws {
        let path = try executable("""
        output=''
        while [ "$#" -gt 0 ]; do
          if [ "$1" = '--output-last-message' ]; then shift; output="$1"; fi
          shift
        done
        /bin/sleep 4 &
        /bin/cat >/dev/null
        /usr/bin/printf '%s' '{"rewritten_prompt":"完成","suggestions":[],"assumptions":[],"clarification_needed":false}' > "$output"
        """)
        let start = Date()
        _ = try CodexClient().runBlocking(request, screenshotData: nil, configuration: CodexConfiguration(executable: path, timeout: 5))
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
    func testShutdownStopsAnInterruptIgnoringChild() throws {
        let path = try executable("trap '' INT TERM\nexec /bin/sleep 10\n")
        let client = CodexClient()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { client.shutdown() }
        let start = Date()
        XCTAssertThrowsError(try client.runBlocking(request, screenshotData: nil, configuration: CodexConfiguration(executable: path))) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
}
