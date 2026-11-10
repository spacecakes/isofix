import AppKit

/// "§ <" in a rounded box, as a menu bar template. Drawn as vectors so it's sharp at any scale.
enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 22, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.set()
            let box = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: 4, yRadius: 4)
            box.lineWidth = 1.5
            box.stroke()
            let text = NSAttributedString(string: "§ <", attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: NSColor.black])
            let t = text.size()
            text.draw(at: NSPoint(x: (size.width - t.width) / 2, y: (size.height - t.height) / 2))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "ISOFix"
        return image
    }()
}
