import AppKit

/// Keep the source application active while allowing the user to edit a preview.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
