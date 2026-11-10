import SwiftUI

extension Text {
    /// A key name drawn as a small keycap inside running text. It's an image so it
    /// wraps with the line, and a template so it takes the surrounding text colour.
    @MainActor static func key(_ label: String) -> Text {
        guard let image = keycaps[label] ?? renderKeycap(label) else { return Text(label) }
        keycaps[label] = image
        return Text(Image(nsImage: image)).baselineOffset(-4)
    }

    /// Rendered once per label, not on every body evaluation.
    @MainActor private static var keycaps: [String: NSImage] = [:]

    @MainActor private static func renderKeycap(_ label: String) -> NSImage? {
        let cap = Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.black)
            .frame(minWidth: 18, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(0.45)))
            .padding(.horizontal, 1)
        let renderer = ImageRenderer(content: cap)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage
        image?.isTemplate = true
        return image
    }
}

/// The left edge of an ISO keyboard. The key the board reported lights up,
/// labelled with what macOS typed, and pops on every press.
struct KeyTestView: View {
    let press: AppModel.Press?

    private let unit: CGFloat = 28

    var body: some View {
        // Just the two rows that hold the keys, with a torn edge where the rows between are cut out.
        HStack(spacing: 8) {
            HStack(spacing: 4) { watched(.leftOfOne); key("1"); key("2") }
            Zigzag()
                .stroke(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                .frame(width: 5, height: unit)
            HStack(spacing: 4) { key("⇧", width: 1.25); watched(.besideShift); key("Z") }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: press?.id)
    }

    /// Each press has a new id, so the lit key is re-inserted and its transition
    /// plays again even when the same key is pressed twice.
    private func watched(_ position: Detector.Key) -> some View {
        ZStack {
            if let press, press.pressed == position {
                key(press.typed.label, color: press.correct ? .green : .orange)
                    .id(press.id)
                    // Only the new key animates; the old one goes at once so they don't overlap.
                    .transition(.asymmetric(insertion: .scale(scale: 0.7), removal: .identity))
            } else {
                key(position.label)
            }
        }
    }

    /// Width in key units, counting the gaps a wider key spans.
    private func keyWidth(_ width: CGFloat) -> CGFloat { unit * width + 4 * (width - 1) }

    private func key(_ label: String, width: CGFloat = 1, color: Color? = nil) -> some View {
        let tint = color ?? .secondary, lit = color != nil
        return Text(label)
            .font(.system(size: 12, weight: lit ? .semibold : .regular))
            .foregroundStyle(tint)
            .frame(width: keyWidth(width), height: unit)
            .background(RoundedRectangle(cornerRadius: 5).fill(tint.opacity(lit ? 0.2 : 0.08)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(tint.opacity(lit ? 1 : 0.3)))
    }
}

/// A vertical zigzag spanning the frame, like a torn-off edge.
private struct Zigzag: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let step: CGFloat = 5
        var y = rect.minY
        var left = true
        p.move(to: CGPoint(x: rect.maxX, y: y))
        while y < rect.maxY {
            y = min(y + step, rect.maxY)
            p.addLine(to: CGPoint(x: left ? rect.minX : rect.maxX, y: y))
            left.toggle()
        }
        return p
    }
}
