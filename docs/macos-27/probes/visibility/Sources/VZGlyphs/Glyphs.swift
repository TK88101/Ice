// The sacrificial helpers' glyphs, shared by vzhelper (which draws them in
// the bar) and vizprobe (whose dry run checks, with IceCore's own baseline
// rules, that they are pairwise distinct -- T8a's DoD in
// docs/plans/2026-09-23-ax-discovery.md).
//
// Every glyph is a stroked template shape -- never a filled block. Deviation
// 6 of the 2026-09-19 plan's ledger records that a solid square has no
// background pixel inside its own ink bounding box, so IceCore's
// core-background invariant (Template.swift, `.tooLittleBackground`) rejects
// it outright. Each shape below is an open bracket with a real gap and an
// accent, so its own bounding box always keeps clear background pixels.
// `target` and `reference` are stroke for stroke the shapes vzhelper drew
// on 2026-09-19.
import AppKit

public enum Glyph: String, CaseIterable {
    /// Open on the right, accent bottom-left. Also the twin's glyph: the
    /// 2026-09-19 ambiguity control depends on the two being identical.
    case target
    /// The target's mirror: open on the left, accent top-right.
    case reference
    /// Open at the bottom, accent hanging from the top bar -- the third
    /// glyph the 2026-09-23 plan's section 6 asks for, so a helper's second
    /// item never collides with the reference (Appendix E).
    case alt
}

public enum Glyphs {
    public static let lineWidth: CGFloat = 1.6

    public static func image(_ glyph: Glyph, side: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            draw(glyph, in: rect.insetBy(dx: 1.5, dy: 2))
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Strokes `glyph` into `box` with the current graphics context.
    public static func draw(_ glyph: Glyph, in box: NSRect) {
        NSColor.black.setStroke()

        let bracket = NSBezierPath()
        bracket.lineWidth = lineWidth
        bracket.lineCapStyle = .round
        bracket.lineJoinStyle = .round
        let accent = NSBezierPath()
        accent.lineWidth = lineWidth
        accent.lineCapStyle = .round
        let midX = box.midX
        let midY = box.midY

        switch glyph {
        case .target:
            bracket.move(to: NSPoint(x: box.maxX, y: box.maxY))
            bracket.line(to: NSPoint(x: box.minX, y: box.maxY))
            bracket.line(to: NSPoint(x: box.minX, y: box.minY))
            bracket.line(to: NSPoint(x: box.maxX, y: box.minY))
            accent.move(to: NSPoint(x: box.minX + 1, y: box.minY + 1))
            accent.line(to: NSPoint(x: box.minX + 3.5, y: midY))
        case .reference:
            bracket.move(to: NSPoint(x: box.minX, y: box.maxY))
            bracket.line(to: NSPoint(x: box.maxX, y: box.maxY))
            bracket.line(to: NSPoint(x: box.maxX, y: box.minY))
            bracket.line(to: NSPoint(x: box.minX, y: box.minY))
            accent.move(to: NSPoint(x: box.maxX - 1, y: box.maxY - 1))
            accent.line(to: NSPoint(x: box.maxX - 3.5, y: midY))
        case .alt:
            bracket.move(to: NSPoint(x: box.minX, y: box.minY))
            bracket.line(to: NSPoint(x: box.minX, y: box.maxY))
            bracket.line(to: NSPoint(x: box.maxX, y: box.maxY))
            bracket.line(to: NSPoint(x: box.maxX, y: box.minY))
            accent.move(to: NSPoint(x: midX, y: box.maxY - 1))
            accent.line(to: NSPoint(x: midX, y: midY - 1))
        }
        bracket.stroke()
        accent.stroke()
    }
}
