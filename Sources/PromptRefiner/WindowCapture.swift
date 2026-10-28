import AppKit
import ScreenCaptureKit
import RefinerCore

enum WindowCapture {
    static var permitted: Bool { CGPreflightScreenCaptureAccess() }
    static func requestPermission() { _ = CGRequestScreenCaptureAccess() }
    static func screenshot(origin: WindowOrigin) async throws -> Data {
        guard permitted else { throw RefinerError.message("屏幕录制尚未授权，本次仅使用文字。") }
        guard let windowID = origin.windowID else { throw RefinerError.message("未能确定原窗口，本次仅使用文字。") }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID && $0.owningApplication?.processID == origin.application.processIdentifier }) else {
            throw RefinerError.message("原窗口已变化，未截取其他窗口。")
        }
        return try await encode(window: window)
    }
    static func screenshot(target: TargetSnapshot) async throws -> Data {
        guard permitted else { throw RefinerError.message("屏幕录制尚未授权。本次可以只根据文字改写。") }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let bounds = Accessibility.windowBounds(target.window)
        let windows = content.windows.filter { $0.owningApplication?.processID == target.application.processIdentifier && $0.windowLayer == 0 && $0.frame.width > 100 && $0.frame.height > 100 }
        let sorted = windows.sorted { a, b in
            guard let bounds else { return a.windowID < b.windowID }
            func distance(_ rect: CGRect) -> CGFloat {
                abs(rect.minX-bounds.minX) + abs(rect.minY-bounds.minY) + abs(rect.width-bounds.width) + abs(rect.height-bounds.height)
            }
            return distance(a.frame) < distance(b.frame)
        }
        guard let window = sorted.first, let bounds,
              abs(window.frame.width-bounds.width) + abs(window.frame.height-bounds.height)
                + abs(window.frame.minX-bounds.minX) + abs(window.frame.minY-bounds.minY) < 20 else {
            throw RefinerError.message("无法确定原窗口的截图，本次仅使用文字上下文。")
        }
        return try await encode(window: window)
    }
    private static func encode(window: SCWindow) async throws -> Data {
        let config = SCStreamConfiguration()
        let scale = min(2, 2200 / max(window.frame.width, 1))
        config.width = Int(window.frame.width * scale); config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw RefinerError.message("截图编码失败，本次仅使用文字上下文。")
        }
        return data
    }
}
