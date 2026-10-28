import XCTest
@testable import RefinerCore

final class GenerationTests: XCTestCase {
    func testSplitJSONLProgressArrivesBeforeCompletion() {
        var parser = GenerationEventParser()
        XCTAssertEqual(parser.consume(Data("{\"type\":\"thread.st".utf8)), [])
        XCTAssertEqual(parser.consume(Data("arted\"}\n{\"type\":\"turn.started\"}\n".utf8)), [.taskCreated, .modelStarted])
        XCTAssertEqual(parser.consume(Data("{\"type\":\"item.started\",\"item\":{\"type\":\"agent_message\"}}\n".utf8)), [.writing])
    }
    func testReasoningBodyIsNeverExposedAsProgress() {
        var parser = GenerationEventParser()
        let body = "{\"type\":\"item.completed\",\"item\":{\"type\":\"reasoning\",\"text\":\"PRIVATE_SCRATCHPAD_123 secret deliberation\"}}\n"
        let events = parser.consume(Data(body.utf8))
        XCTAssertEqual(events, [.analyzing])
        XCTAssertFalse(events.map(\.publicMessage).joined().contains("PRIVATE_SCRATCHPAD"))
    }
    func testRepeatedEventsDoNotFloodProgressAndMalformedLinesIgnored() {
        var parser = GenerationEventParser()
        let line = "{\"type\":\"item.updated\",\"item\":{\"type\":\"reasoning\"}}\n"
        XCTAssertEqual(parser.consume(Data(("bad-json\n" + line + line).utf8)), [.analyzing])
    }
    func testNormalContextInferenceDoesNotRequireBlockingReview() throws {
        let json = "{\"rewritten_prompt\":\"请回顾当前会话中的已完成工作与结果。\",\"suggestions\":[],\"assumptions\":[\"你指原会话中的助手\"],\"clarification_needed\":false,\"review_level\":\"context\"}"
        let result = try RewriteResult.decode(Data(json.utf8))
        XCTAssertFalse(result.requiresReview)
    }
    func testScopeChangingInferenceAndClarificationRequireReview() {
        XCTAssertTrue(RewriteResult(rewrittenPrompt: "发布到线上", reviewLevel: .blocking).requiresReview)
        XCTAssertTrue(RewriteResult(rewrittenPrompt: "缺少目标", clarificationNeeded: true, reviewLevel: .context).requiresReview)
    }
    func testLegacyResultStillDecodesWithoutTreatingEveryAssumptionAsBlocking() throws {
        let json = "{\"rewritten_prompt\":\"回顾工作\",\"suggestions\":[],\"assumptions\":[\"当前会话\"],\"clarification_needed\":false}"
        XCTAssertFalse(try RewriteResult.decode(Data(json.utf8)).requiresReview)
    }
    func testServiceTriggerNeverLabelsItselfManual() {
        XCTAssertEqual(TriggerKind.service.displayName, "右键服务")
        XCTAssertNotEqual(TriggerKind.service.displayName, TriggerKind.manual.displayName)
    }
}
