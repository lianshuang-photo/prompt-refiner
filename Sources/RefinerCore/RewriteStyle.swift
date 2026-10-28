import Foundation

public enum RewriteStyle: String, CaseIterable, Sendable {
    case augment, anthropic
    case openAI = "openai"

    public var title: String {
        switch self {
        case .augment: return "Augment"
        case .anthropic: return "Anthropic"
        case .openAI: return "OpenAI"
        }
    }

    public var summary: String {
        switch self {
        case .augment: return "先按原稿查找相关上下文与代码，再细化指令。推荐用于工程任务。"
        case .anthropic: return "精选关键上下文，按简单询问、复杂实施、已经明确三类示例控制补充程度。"
        case .openAI: return "优先保留原有结构和用户约束，只补真实缺口，并对照原稿检查。"
        }
    }

    public var sourceURL: URL {
        switch self {
        case .augment: return URL(string: "https://github.com/augmentcode/auggie/blob/5f9e4efafbdd052b6f1aa8855e0067ccdc181040/examples/typescript-sdk/context/prompt-enhancer-server/enhance-handler.ts")!
        case .anthropic: return URL(string: "https://www.anthropic.com/research/effective-context-engineering-for-ai-agents")!
        case .openAI: return URL(string: "https://developers.openai.com/api/docs/guides/prompt-generation")!
        }
    }

    public var instructions: String {
        let resource: String
        switch self {
        case .augment: resource = "AugmentInstructions"
        case .anthropic: resource = "AnthropicInstructions"
        case .openAI: resource = "OpenAIInstructions"
        }
        let common = RewriteRequest.resourceInstructions(named: "RewriteInstructions") ?? "只增强原稿，不执行任务；保留原意和约束，只返回符合输出 schema 的 JSON。"
        return common + "\n\n" + (RewriteRequest.resourceInstructions(named: resource) ?? summary)
    }
}
