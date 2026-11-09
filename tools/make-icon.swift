// Renders Resources/AppIcon.icns.  Run: swift tools/make-icon.swift
import AppKit

func render(_ size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    let ctx = NSGraphicsContext.current!.cgContext

    // Body: macOS icon grid, 824pt squircle-ish rounded rect inside 1024.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s,
                  color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill(); bodyPath.fill()
    ctx.restoreGState()
    NSGradient(colors: [NSColor(red: 0.20, green: 0.24, blue: 0.33, alpha: 1),
                        NSColor(red: 0.09, green: 0.10, blue: 0.15, alpha: 1)])!
        .draw(in: bodyPath, angle: -90)

    // Two keycaps.
    func keycap(_ center: CGPoint, _ label: String) {
        let w = 300 * s, h = 300 * s
        let outer = NSRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
        let outerPath = NSBezierPath(roundedRect: outer, xRadius: 56 * s, yRadius: 56 * s)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -14 * s), blur: 20 * s,
                      color: NSColor.black.withAlphaComponent(0.5).cgColor)
        NSColor(white: 0.80, alpha: 1).setFill(); outerPath.fill()
        ctx.restoreGState()
        NSGradient(colors: [NSColor(white: 0.93, alpha: 1), NSColor(white: 0.74, alpha: 1)])!
            .draw(in: outerPath, angle: -90)
        let top = outer.insetBy(dx: 30 * s, dy: 30 * s).offsetBy(dx: 0, dy: 12 * s)
        let topPath = NSBezierPath(roundedRect: top, xRadius: 40 * s, yRadius: 40 * s)
        NSGradient(colors: [NSColor(white: 1.0, alpha: 1), NSColor(white: 0.90, alpha: 1)])!
            .draw(in: topPath, angle: -90)

        let font = NSFont.systemFont(ofSize: 150 * s, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font,
            .foregroundColor: NSColor(red: 0.13, green: 0.15, blue: 0.21, alpha: 1)]
        let str = NSAttributedString(string: label, attributes: attrs)
        let b = str.size()
        str.draw(at: CGPoint(x: top.midX - b.width / 2, y: top.midY - b.height / 2 + 4 * s))
    }
    keycap(CGPoint(x: 330 * s, y: 548 * s), "§")
    keycap(CGPoint(x: 694 * s, y: 548 * s), "<")

    // Seatbelt strapping both keys in place (ISOFIX, after the child-seat anchors).
    let beltY = 418 * s, beltH = 80 * s
    func shadowed(_ path: NSBezierPath, y: CGFloat, blur: CGFloat, _ alpha: CGFloat) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: y * s), blur: blur * s,
                      color: NSColor.black.withAlphaComponent(alpha).cgColor)
        NSColor.black.setFill(); path.fill()
        ctx.restoreGState()
    }
    // Woven nylon webbing: twill ribs instead of stitching.
    func webbing(_ x0: CGFloat, _ x1: CGFloat) {
        let r = NSRect(x: x0, y: beltY - beltH / 2, width: x1 - x0, height: beltH)
        let path = NSBezierPath(rect: r)
        ctx.saveGState()
        bodyPath.addClip()
        shadowed(path, y: -8, blur: 16, 0.5)
        NSGradient(colors: [NSColor(white: 0.36, alpha: 1), NSColor(white: 0.26, alpha: 1),
                            NSColor(white: 0.18, alpha: 1)])!.draw(in: path, angle: -90)
        path.addClip()
        let step = 9 * s
        var x = r.minX - r.height
        while x < r.maxX {
            for (dx, color) in [(0.0, NSColor(white: 1, alpha: 0.10)), (step / 2, NSColor(white: 0, alpha: 0.22))] {
                let rib = NSBezierPath()
                rib.move(to: CGPoint(x: x + dx, y: r.minY))
                rib.line(to: CGPoint(x: x + dx + r.height * 0.5, y: r.maxY))
                rib.lineWidth = 3 * s
                color.setStroke(); rib.stroke()
            }
            x += step
        }
        for y in [r.minY, r.maxY] { // denser selvedge along both edges
            let edge = NSBezierPath()
            edge.move(to: CGPoint(x: r.minX, y: y)); edge.line(to: CGPoint(x: r.maxX, y: y))
            edge.lineWidth = 7 * s
            NSColor(white: 0, alpha: 0.35).setStroke(); edge.stroke()
        }
        ctx.restoreGState()
    }

    // Right strap runs into the buckle housing.
    webbing(600 * s, body.maxX)

    // Metal latch plate; the left strap loops through its slot.
    let plate = NSBezierPath(roundedRect: NSRect(x: 366 * s, y: beltY - 54 * s, width: 150 * s, height: 108 * s),
                             xRadius: 18 * s, yRadius: 18 * s)
    shadowed(plate, y: -6, blur: 12, 0.5)
    NSGradient(colors: [NSColor(white: 0.97, alpha: 1), NSColor(white: 0.78, alpha: 1),
                        NSColor(white: 0.58, alpha: 1)])!.draw(in: plate, angle: -90)
    NSColor(white: 0.18, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 392 * s, y: beltY - 44 * s, width: 20 * s, height: 88 * s),
                 xRadius: 8 * s, yRadius: 8 * s).fill()
    webbing(body.minX, 404 * s)

    // Black buckle housing with the red PRESS button at the tongue end.
    let housing = NSBezierPath(roundedRect: NSRect(x: 482 * s, y: beltY - 68 * s, width: 170 * s, height: 136 * s),
                               xRadius: 30 * s, yRadius: 30 * s)
    shadowed(housing, y: -10, blur: 18, 0.6)
    NSGradient(colors: [NSColor(white: 0.26, alpha: 1), NSColor(white: 0.11, alpha: 1),
                        NSColor(white: 0.05, alpha: 1)])!.draw(in: housing, angle: -90)
    let rim = NSBezierPath(roundedRect: NSRect(x: 484 * s, y: beltY - 66 * s, width: 166 * s, height: 132 * s),
                           xRadius: 28 * s, yRadius: 28 * s)
    rim.lineWidth = 3 * s
    NSColor(white: 1, alpha: 0.14).setStroke(); rim.stroke()
    let button = NSRect(x: 500 * s, y: beltY - 46 * s, width: 92 * s, height: 92 * s)
    let buttonPath = NSBezierPath(roundedRect: button, xRadius: 14 * s, yRadius: 14 * s)
    NSGradient(colors: [NSColor(red: 0.96, green: 0.30, blue: 0.26, alpha: 1),
                        NSColor(red: 0.74, green: 0.10, blue: 0.10, alpha: 1)])!.draw(in: buttonPath, angle: -90)
    let press = NSAttributedString(string: "PRESS", attributes: [
        .font: NSFont.systemFont(ofSize: 18 * s, weight: .heavy), .kern: 1.2 * s,
        .foregroundColor: NSColor(white: 1, alpha: 0.92)])
    let ps = press.size()
    press.draw(at: CGPoint(x: button.midX - ps.width / 2, y: button.midY - ps.height / 2))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(CGFloat(base)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(CGFloat(base * 2)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let resources = root.appendingPathComponent("Resources")
try! FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try! render(1024).write(to: resources.appendingPathComponent("AppIcon-preview.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")
