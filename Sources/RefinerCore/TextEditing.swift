import Foundation

public enum RefinerError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        if case .message(let message) = self { return message }
        return nil
    }
}

public struct TextEdit: Equatable {
    public let original: String
    public let range: NSRange
    public let replacement: String
    public let result: String

    public init(original: String, range: NSRange, replacement: String) throws {
        guard range.location != NSNotFound,
              range.location >= 0, range.length >= 0,
              range.location <= original.utf16.count,
              range.length <= original.utf16.count - range.location,
              let stringRange = Range(range, in: original),
              Self.isBoundary(stringRange.lowerBound, in: original),
              Self.isBoundary(stringRange.upperBound, in: original) else {
            throw RefinerError.message("原稿的选区已经失效，请重新选择文字。")
        }
        guard !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RefinerError.message("模型没有返回可用的改写文字。原稿已保留。")
        }
        self.original = original
        self.range = range
        self.replacement = replacement
        self.result = (original as NSString).replacingCharacters(in: range, with: replacement)
    }

    public var selectedOriginal: String { (original as NSString).substring(with: range) }
    public var insertedRange: NSRange { NSRange(location: range.location, length: replacement.utf16.count) }

    /// Restore only the owned replacement. Edits after it remain intact. If the
    /// replacement or its position changed, refuse rather than overwrite edits.
    public func undo(in current: String) throws -> String {
        let prefix = (original as NSString).substring(to: range.location)
        guard current.hasPrefix(prefix),
              insertedRange.location <= current.utf16.count,
              insertedRange.length <= current.utf16.count - insertedRange.location,
              let stringRange = Range(insertedRange, in: current),
              Self.isBoundary(stringRange.lowerBound, in: current),
              Self.isBoundary(stringRange.upperBound, in: current),
              (current as NSString).substring(with: insertedRange) == replacement else {
            throw RefinerError.message("你已编辑过改写内容，无法自动撤销。可以在结果卡片中复制原稿。")
        }
        return (current as NSString).replacingCharacters(in: insertedRange, with: selectedOriginal)
    }
    private static func isBoundary(_ index: String.Index, in text: String) -> Bool {
        index == text.endIndex || text.indices.contains(index)
    }
}

public struct TargetIdentity: Equatable {
    public var processID: Int32
    public var windowTitle: String
    public var contextKey: String
    public init(processID: Int32, windowTitle: String, contextKey: String) {
        self.processID = processID; self.windowTitle = windowTitle; self.contextKey = contextKey
    }
}

public enum WritebackGuard {
    public static func allows(originalIdentity: TargetIdentity, currentIdentity: TargetIdentity,
                              originalText: String, currentText: String,
                              originalSelection: NSRange, currentSelection: NSRange,
                              interactionChanged: Bool) -> Bool {
        !interactionChanged && originalIdentity == currentIdentity && originalText == currentText
            && originalSelection == currentSelection
    }
}
