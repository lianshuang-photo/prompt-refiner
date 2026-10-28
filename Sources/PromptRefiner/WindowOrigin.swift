import AppKit

struct WindowOrigin {
    let application: NSRunningApplication
    let windowID: CGWindowID?
    let title: String
    let bounds: CGRect?
    var name: String { application.localizedName ?? "原应用" }
    var key: String { "\(application.processIdentifier):\(windowID ?? 0):\(title)" }

    static func capture(application preferred: NSRunningApplication? = nil) -> WindowOrigin? {
        guard let app = preferred ?? NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let window = windows.first { row in
            guard row[kCGWindowOwnerPID as String] as? Int32 == app.processIdentifier,
                  row[kCGWindowLayer as String] as? Int == 0,
                  let dictionary = row[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: dictionary), frame.width > 100, frame.height > 100 else { return false }
            return true
        }
        let frame = (window?[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) }
        return WindowOrigin(application: app, windowID: (window?[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                            title: window?[kCGWindowName as String] as? String ?? "", bounds: frame)
    }
}
