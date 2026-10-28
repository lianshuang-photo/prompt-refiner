import XCTest
import CSQLite
@testable import RefinerCore

final class ConversationTests: XCTestCase {
    private var home: URL!
    private var db: URL!
    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        db = home.appendingPathComponent("Library/Application Support/com.conductor.app/conductor.db")
        try FileManager.default.createDirectory(at: db.deletingLastPathComponent(), withIntermediateDirectories: true)
        try sql("""
        CREATE TABLE sessions(id TEXT, title TEXT, claude_session_id TEXT, workspace_id TEXT, is_hidden INTEGER, updated_at TEXT);
        CREATE TABLE workspaces(local_id TEXT, directory_name TEXT, workspace_name TEXT, active_session_id TEXT);
        CREATE TABLE session_messages(session_id TEXT,role TEXT,content TEXT,sent_at TEXT,cancelled_at TEXT,created_at TEXT);
        INSERT INTO sessions VALUES('one','Example task review','native-one','workspace',0,'2026-10-08');
        INSERT INTO workspaces VALUES('workspace','sample-workspace',NULL,'one');
        INSERT INTO session_messages VALUES('one','user','不要过度设计','2026-10-08',NULL,'2026-10-08');
        INSERT INTO session_messages VALUES('two','user','不应读取的其他聊天','2026-10-08',NULL,'2026-10-08');
        """)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }
    private func sql(_ text: String) throws {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(db.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        XCTAssertEqual(sqlite3_exec(handle, text, nil, nil, nil), SQLITE_OK)
    }
    func testReadsOnlyUniquelyMatchedSession() throws {
        let store = ConversationStore(home: home)
        let result = try XCTUnwrap(store.lookup(bundleID: "com.conductor.app", anchors: ["Example task review"]))
        XCTAssertEqual(result.key, "conductor:one:native-one")
        XCTAssertTrue(result.text.contains("不要过度设计"))
        XCTAssertFalse(result.text.contains("不应读取的其他聊天"))
    }
    func testDuplicateTitlesAreRejected() throws {
        try sql("INSERT INTO sessions VALUES('two','Example task review','native-two','other',0,'2026-10-08');")
        XCTAssertNil(ConversationStore(home: home).lookup(bundleID: "com.conductor.app", anchors: ["Example task review"]))
    }
    func testUnknownWindowDoesNotFallBackToMostRecentSession() {
        XCTAssertNil(ConversationStore(home: home).lookup(bundleID: "com.conductor.app", anchors: ["Conductor"]))
    }
    func testActualConductorSelectedTabLabelMapsToOriginalSession() throws {
        let result = try XCTUnwrap(ConversationStore(home: home).lookup(bundleID: "com.conductor.app", anchors: ["Conductor", "Close chat Example task review", "Terminal 1"]))
        XCTAssertEqual(result.key, "conductor:one:native-one")
        XCTAssertTrue(result.text.contains("不要过度设计"))
    }
    func testActiveWorkspaceMapping() throws {
        let result = try XCTUnwrap(ConversationStore(home: home).lookup(bundleID: "com.conductor.app", anchors: ["sample-workspace — Conductor"]))
        XCTAssertEqual(result.key, "conductor:one:native-one")
    }
    func testMatchedNativeSessionProvidesItsProjectWithoutGuessingAnotherSession() throws {
        let project = home.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let state = home.appendingPathComponent(".codex-conductor/state_5.sqlite")
        try FileManager.default.createDirectory(at: state.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(state.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        let path = project.path.replacingOccurrences(of: "'", with: "''")
        XCTAssertEqual(sqlite3_exec(handle, "CREATE TABLE threads(id TEXT,cwd TEXT); INSERT INTO threads VALUES('native-one','\(path)'); INSERT INTO threads VALUES('native-two','/unrelated');", nil, nil, nil), SQLITE_OK)
        let result = try XCTUnwrap(ConversationStore(home: home).lookup(bundleID: "com.conductor.app", anchors: ["Close chat Example task review"]))
        XCTAssertEqual(result.projectDirectory, project.resolvingSymlinksInPath())
        XCTAssertNil(ConversationStore(home: home).lookup(bundleID: "com.conductor.app", anchors: ["Unknown chat"]))
    }
    func testReadOnlyConnectionCannotWriteSource() throws {
        let connection = try XCTUnwrap(ReadOnlyDatabase(path: db))
        XCTAssertTrue(connection.query("DELETE FROM sessions RETURNING id").isEmpty)
        XCTAssertEqual(connection.query("SELECT COUNT(*) AS count FROM sessions").first?["count"], "1")
    }
    func testClosedWALDatabaseInReadOnlyDirectoryCanBeReadWithoutChangingSource() throws {
        let location = home.appendingPathComponent("readonly-source")
        try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
        let database = location.appendingPathComponent("source.sqlite")
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.path, &handle), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(handle, "PRAGMA journal_mode=WAL; CREATE TABLE records(value TEXT); INSERT INTO records VALUES('kept');", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(handle, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_close(handle), SQLITE_OK)
        // The fixture is fully checkpointed and closed. Remove any empty,
        // persisted sidecars to reproduce a database that needs initialization.
        for suffix in ["-wal", "-shm"] where FileManager.default.fileExists(atPath: database.path + suffix) {
            try FileManager.default.removeItem(atPath: database.path + suffix)
        }
        let before = try Data(contentsOf: database)
        let originalFiles = Set(try FileManager.default.contentsOfDirectory(atPath: location.path))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: location.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: location.path) }
        let connection = try XCTUnwrap(ReadOnlyDatabase(path: database))
        XCTAssertEqual(connection.query("SELECT value FROM records").first?["value"], "kept")
        XCTAssertTrue(connection.query("DELETE FROM records RETURNING value").isEmpty)
        XCTAssertEqual(try Data(contentsOf: database), before)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: location.path)), originalFiles)
    }
    func testLongHistoryKeepsEndingConstraintsAndMarksOmission() throws {
        let text = "起始目标" + String(repeating: "中", count: 10_000) + "末尾约束：只读，禁止发布"
        try sql("INSERT INTO session_messages VALUES('one','user','" + text + "','2026-10-09',NULL,'2026-10-09');")
        let result = try XCTUnwrap(ConversationStore(home: home).lookup(bundleID: "com.conductor.app", anchors: ["Example task review"]))
        XCTAssertTrue(result.text.contains("末尾约束：只读，禁止发布"))
        XCTAssertTrue(result.text.contains("历史消息中段已省略"))
    }
}
