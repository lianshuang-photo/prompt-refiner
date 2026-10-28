import Foundation

public enum GenerationEvent: String, Sendable, Codable {
    case processStarted, inputSubmitted, taskCreated, modelStarted, readingProject, analyzing, writing, received, validating, finished
    public var publicMessage: String {
        switch self {
        case .processStarted: return "已启动改写引擎"
        case .inputSubmitted: return "原稿与可用上下文已提交"
        case .taskCreated: return "独立改写任务已创建"
        case .modelStarted: return "模型开始处理本次请求"
        case .readingProject: return "正在只读查看相关工程文件"
        case .analyzing: return "正在分析输入素材"
        case .writing: return "正在生成细化文本"
        case .received: return "已收到模型文本"
        case .validating: return "正在检查格式与应用条件"
        case .finished: return "改写结果已准备好"
        }
    }
}

/// Translate only event metadata into public progress. Never forward raw
/// reasoning bodies, prompts, tools, credentials or model-private deliberation.
public struct GenerationEventParser {
    private var pending = Data()
    private var emitted: Set<String> = []
    public init() {}
    public mutating func consume(_ bytes: Data) -> [GenerationEvent] {
        pending.append(bytes); var result: [GenerationEvent] = []
        while let end = pending.firstIndex(of: 10) {
            let line = Data(pending[..<end]); pending.removeSubrange(...end)
            guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let type = event["type"] as? String else { continue }
            var mapped: GenerationEvent?
            if type == "thread.started" { mapped = .taskCreated }
            if type == "turn.started" { mapped = .modelStarted }
            if type == "turn.completed" { mapped = .validating }
            if let item = event["item"] as? [String: Any], let itemType = item["type"] as? String {
                if itemType == "reasoning" { mapped = .analyzing }
                if itemType == "command_execution" { mapped = .readingProject }
                if itemType == "agent_message" { mapped = type == "item.completed" ? .received : .writing }
            }
            if let mapped, emitted.insert(mapped.rawValue).inserted { result.append(mapped) }
        }
        if pending.count > 1_000_000 { pending.removeAll() }
        return result
    }
}

public enum TriggerKind: String, Codable, Sendable {
    case hotkey, service, manual
    public var displayName: String {
        switch self { case .hotkey: return "快捷键"; case .service: return "右键服务"; case .manual: return "手动输入" }
    }
}
