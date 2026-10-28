import AppKit

// Original vector companion to the mascot's pen-nib hair ornament.
final class StatusMark: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        let nib = NSBezierPath()
        nib.windingRule = .evenOdd
        nib.move(to: NSPoint(x: 2, y: 2))
        for point in [NSPoint(x: 3.5, y: 8.8), NSPoint(x: 8.5, y: 13.8), NSPoint(x: 13.5, y: 8.8), NSPoint(x: 8.6, y: 3.8)] {
            nib.line(to: point)
        }
        nib.close()
        nib.appendOval(in: NSRect(x: 6.4, y: 6.4, width: 2, height: 2))
        let slit = NSBezierPath()
        slit.move(to: NSPoint(x: 1.8, y: 2.6)); slit.line(to: NSPoint(x: 7.3, y: 8.1))
        slit.line(to: NSPoint(x: 8.1, y: 7.3)); slit.line(to: NSPoint(x: 2.6, y: 1.8)); slit.close()
        nib.append(slit); nib.fill()

        let star = NSBezierPath()
        let points = [NSPoint(x: 14.6, y: 17.6), NSPoint(x: 15.3, y: 15.4), NSPoint(x: 17.5, y: 14.7), NSPoint(x: 15.3, y: 14), NSPoint(x: 14.6, y: 11.8), NSPoint(x: 13.9, y: 14), NSPoint(x: 11.7, y: 14.7), NSPoint(x: 13.9, y: 15.4)]
        star.move(to: points[0]); for point in points.dropFirst() { star.line(to: point) }; star.close(); star.fill()
    }
}

let destination = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/StatusIcon.pdf"
let view = StatusMark(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
try view.dataWithPDF(inside: view.bounds).write(to: URL(fileURLWithPath: destination))
