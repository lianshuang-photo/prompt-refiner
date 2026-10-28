import Foundation
import CSQLite
import Darwin

public struct ConversationContext {
    public let key: String
    public let title: String
    public let text: String
    public let projectDirectory: URL?
    public init(key: String, title: String, text: String, projectDirectory: URL? = nil) {
        self.key = key; self.title = title; self.text = text
        self.projectDirectory = RewriteRequest.validatedProjectDirectory(projectDirectory)
    }
}

/// All source databases are opened SQLITE_OPEN_READONLY. A non-unique match is
/// intentionally rejected; a title is a lookup hint, not a stable identity.
public final class ConversationStore {
    private let home: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    public func lookup(bundleID: String, anchors: [String]) -> ConversationContext? {
        let candidates = Set(anchors.flatMap { value -> [String] in
            let cleaned = Self.normalizedTabTitle(value)
            var parts = [cleaned]
            for separator in [" — ", " – ", " · ", " | ", " • "] {
                parts += cleaned.components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            return parts.filter { !$0.isEmpty && $0.count < 180 }
        })
        guard !candidates.isEmpty else { return nil }
        if bundleID.lowercased().contains("conductor") { return conductor(candidates: candidates) }
        if bundleID.lowercased().contains("openai") || bundleID.lowercased().contains("codex") {
            return codex(candidates: candidates)
        }
        return nil
    }
    public static func normalizedTabTitle(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Close chat ", "关闭聊天 ", "关闭对话 "] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
            break
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func conductor(candidates: Set<String>) -> ConversationContext? {
        let path = home.appendingPathComponent("Library/Application Support/com.conductor.app/conductor.db")
        guard let db = ReadOnlyDatabase(path: path) else { return nil }
        let rows = db.query("""
        SELECT s.id, s.title, s.claude_session_id, w.directory_name, w.workspace_name, w.active_session_id
        FROM sessions s LEFT JOIN workspaces w ON s.workspace_id=w.local_id
        WHERE COALESCE(s.is_hidden,0)=0 ORDER BY s.updated_at DESC LIMIT 400
        """)
        let matches = rows.filter { row in
            if let title = row["title"], candidates.contains(title) { return true }
            let active = row["active_session_id"] == row["id"]
            return active && [row["directory_name"], row["workspace_name"]].compactMap { $0 }.contains { candidates.contains($0) }
        }
        guard matches.count == 1, let row = matches.first, let id = row["id"] else { return nil }
        let nativeID = row["claude_session_id"] ?? ""
        var text = nativeMessages(id: nativeID, profile: ".codex-conductor")
        if text.isEmpty {
            let messages = db.query("SELECT role,content FROM session_messages WHERE session_id=? AND role IN ('user','assistant') AND sent_at IS NOT NULL AND cancelled_at IS NULL ORDER BY created_at DESC LIMIT 30", parameters: [id])
            text = format(messages.reversed().compactMap { r in
                guard let role = r["role"], let body = r["content"], !body.isEmpty else { return nil }
                return (role, body)
            })
        }
        guard !text.isEmpty else { return nil }
        let project = nativeProjectDirectory(id: nativeID, profile: ".codex-conductor")
            ?? db.query("SELECT workspace_path FROM workspaces WHERE active_session_id=?", parameters: [id]).first?["workspace_path"].flatMap { URL(fileURLWithPath: $0) }
        return ConversationContext(key: "conductor:" + id + ":" + nativeID, title: row["title"] ?? "当前会话", text: text, projectDirectory: project)
    }

    private func codex(candidates: Set<String>) -> ConversationContext? {
        guard let db = ReadOnlyDatabase(path: home.appendingPathComponent(".codex/state_5.sqlite")) else { return nil }
        let rows = db.query("SELECT id,title,name FROM threads WHERE archived=0 AND COALESCE(thread_source,'user') <> 'subagent' ORDER BY updated_at DESC LIMIT 400")
        let matches = rows.filter { row in [row["name"], row["title"]].compactMap { $0 }.contains { candidates.contains($0) } }
        guard matches.count == 1, let row = matches.first, let id = row["id"] else { return nil }
        let text = nativeMessages(id: id, profile: ".codex")
        guard !text.isEmpty else { return nil }
        return ConversationContext(key: "codex:" + id, title: row["name"] ?? row["title"] ?? "当前会话", text: text, projectDirectory: nativeProjectDirectory(id: id, profile: ".codex"))
    }

    private func nativeProjectDirectory(id: String, profile: String) -> URL? {
        guard let db = ReadOnlyDatabase(path: home.appendingPathComponent(profile + "/state_5.sqlite")),
              let path = db.query("SELECT cwd FROM threads WHERE id=?", parameters: [id]).first?["cwd"],
              path.hasPrefix("/") else { return nil }
        return RewriteRequest.validatedProjectDirectory(URL(fileURLWithPath: path))
    }

    private func nativeMessages(id: String, profile: String) -> String {
        guard !id.isEmpty else { return "" }
        if let db = ReadOnlyDatabase(path: home.appendingPathComponent(profile + "/thread_history_1.sqlite")) {
            let rows = db.query("SELECT item_json FROM thread_items WHERE thread_id=? AND item_type IN ('userMessage','agentMessage') ORDER BY rollout_ordinal DESC LIMIT 60", parameters: [id])
            let messages = rows.reversed().compactMap { row -> (String, String)? in
                guard let raw = row["item_json"], let data = raw.data(using: .utf8),
                      let item = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
                if item["type"] as? String == "agentMessage" {
                    guard item["phase"] as? String == "final_answer" || item["phase"] == nil,
                          let text = item["text"] as? String else { return nil }
                    return ("assistant", text)
                }
                let content = item["content"] as? [[String: Any]] ?? []
                let text = content.compactMap { ($0["text"] as? String) }.joined(separator: "\n")
                return text.isEmpty ? nil : ("user", text)
            }
            let formatted = format(messages)
            if !formatted.isEmpty { return formatted }
        }
        guard let state = ReadOnlyDatabase(path: home.appendingPathComponent(profile + "/state_5.sqlite")),
              let path = state.query("SELECT rollout_path FROM threads WHERE id=?", parameters: [id]).first?["rollout_path"] else { return "" }
        let root = home.appendingPathComponent(profile + "/sessions").standardizedFileURL.path + "/"
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.path.hasPrefix(root), let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size < 50_000_000, let data = try? Data(contentsOf: url) else { return "" }
        var messages: [(String, String)] = []
        for line in data.split(separator: 10) {
            guard let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  record["type"] as? String == "response_item", let item = record["payload"] as? [String: Any],
                  item["type"] as? String == "message", let role = item["role"] as? String,
                  ["user", "assistant"].contains(role),
                  role != "assistant" || item["phase"] as? String == "final_answer" || item["phase"] == nil else { continue }
            let content = item["content"] as? [[String: Any]] ?? []
            let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if !text.isEmpty { messages.append((role, text)) }
        }
        return format(Array(messages.suffix(40)))
    }

    private func format(_ messages: [(String, String)]) -> String {
        var pieces: [String] = []; var remaining = 24_000
        for (role, text) in messages.reversed() {
            if text.hasPrefix("<environment_context>") || text.hasPrefix("<system_instruction>") { continue }
            guard remaining > 0 else { break }
            let allowance = min(remaining, 8_000)
            guard allowance > 100 else { break }
            let marker = "\n[历史消息中段已省略，请勿推断未提供的内容]\n"
            let body: String
            if text.count > allowance {
                let head = min(3_000, (allowance-marker.count)/2)
                body = String(text.prefix(head)) + marker + String(text.suffix(allowance-marker.count-head))
            } else { body = text }
            pieces.append("[\(role == "user" ? "用户" : "助手（建议需结合用户回复判断是否采纳）")]\n" + body)
            remaining -= body.count
        }
        return pieces.reversed().joined(separator: "\n\n")
    }
}

public final class ReadOnlyDatabase {
    private var handle: OpaquePointer?
    private let source: URL
    private var snapshotDirectory: URL?
    private var attemptedSnapshot = false
    public init?(path: URL) {
        source = path
        // Check before SQLite opens the file: even a read-only open can
        // initialize sidecars for a closed WAL database.
        if isClosedWALDatabase() {
            guard usePrivateSnapshotIfNeeded(force: true) else { return nil }
            return
        }
        guard sqlite3_open_v2(path.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }; handle = nil; return nil
        }
        sqlite3_busy_timeout(handle, 500)
    }
    deinit {
        sqlite3_close(handle)
        if let snapshotDirectory { try? FileManager.default.removeItem(at: snapshotDirectory) }
    }
    /// Some SQLite files need writable journal initialization even for a read.
    /// Recover only an APFS clone in private temporary storage; never reopen the
    /// source writable or snapshot a database with a live journal/WAL.
    private func isClosedWALDatabase() -> Bool {
        guard !FileManager.default.fileExists(atPath: source.path + "-wal"),
              let file = try? FileHandle(forReadingFrom: source) else { return false }
        defer { try? file.close() }
        guard let header = try? file.read(upToCount: 20), header.count == 20 else { return false }
        return header[18] == 2 || header[19] == 2
    }
    private func usePrivateSnapshotIfNeeded(force: Bool = false) -> Bool {
        guard !attemptedSnapshot, force || sqlite3_errcode(handle) == SQLITE_CANTOPEN else { return false }
        attemptedSnapshot = true
        let manager = FileManager.default
        func hasJournal() -> Bool { ["-wal", "-journal"].contains { manager.fileExists(atPath: source.path + $0) } }
        guard !hasJournal(), let before = try? manager.attributesOfItem(atPath: source.path),
              before[.type] as? FileAttributeType == .typeRegular else { return false }
        let directory = manager.temporaryDirectory.appendingPathComponent("prompt-refiner-db-" + UUID().uuidString)
        guard (try? manager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])) != nil else { return false }
        var retained = false
        defer { if !retained { try? manager.removeItem(at: directory) } }
        let copy = directory.appendingPathComponent("snapshot.sqlite")
        guard clonefile(source.path, copy.path, 0) == 0, !hasJournal(),
              let after = try? manager.attributesOfItem(atPath: source.path),
              before[.size] as? UInt64 == after[.size] as? UInt64,
              before[.modificationDate] as? Date == after[.modificationDate] as? Date,
              before[.systemFileNumber] as? UInt64 == after[.systemFileNumber] as? UInt64 else { return false }
        var snapshot: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &snapshot, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let snapshot { sqlite3_close(snapshot) }; return false
        }
        guard sqlite3_exec(snapshot, "PRAGMA query_only=ON", nil, nil, nil) == SQLITE_OK else { sqlite3_close(snapshot); return false }
        sqlite3_close(handle); handle = snapshot; snapshotDirectory = directory; retained = true
        sqlite3_busy_timeout(handle, 500)
        return true
    }
    public func query(_ sql: String, parameters: [String] = []) -> [[String: String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            if let statement { sqlite3_finalize(statement) }
            return usePrivateSnapshotIfNeeded() ? query(sql, parameters: parameters) : []
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in parameters.enumerated() { sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) }
        var result: [[String: String]] = []
        var state = sqlite3_step(statement)
        while state == SQLITE_ROW {
            var row: [String: String] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                guard let name = sqlite3_column_name(statement, column), let text = sqlite3_column_text(statement, column) else { continue }
                row[String(cString: name)] = String(cString: text)
            }
            result.append(row)
            state = sqlite3_step(statement)
        }
        if state != SQLITE_DONE {
            // Finalize before swapping connections; the old statement belongs
            // to the source connection and must not outlive it.
            sqlite3_finalize(statement); statement = nil
            return usePrivateSnapshotIfNeeded() ? query(sql, parameters: parameters) : []
        }
        return result
    }
}
