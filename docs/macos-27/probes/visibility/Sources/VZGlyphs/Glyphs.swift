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

public enum Glyph: String, CaseIterable, Sendable, Codable {
    /// Open on the right, accent bottom-left. Also the twin's glyph: the
    /// 2026-09-19 ambiguity control depends on the two being identical.
    case target
    /// The target's mirror: open on the left, accent top-right.
    case reference
    /// Open at the bottom, accent hanging from the top bar -- the third
    /// glyph the 2026-09-23 plan's section 6 asks for, so a helper's second
    /// item never collides with the reference (Appendix E).
    case alt
    /// C2's extra hidden-section items (docs/plans/2026-09-28-c2-protocol.md,
    /// T2), each a shape none of the others shares: open at the top with an
    /// accent rising from the bottom bar (alt's mirror) ...
    case hidden2
    /// ... an H: two posts and a crossbar ...
    case hidden3
    /// ... and an N: two posts joined by a diagonal.
    case hidden4
    /// Route C's thirteen more (docs/plans/2026-10-01-icebar-c-instrument.md,
    /// 19 in all: 16 members + 3 visible), same rule -- stroked, open,
    /// accented, pairwise distinct under the oracle's own match rule
    /// (GlyphSetTests). An L with a tick falling from the top-right corner.
    case ell
    /// A gamma (post and top bar) with a stub on the bottom-right.
    case gamma
    /// A Z with a tick hanging from its top-left end.
    case zed
    /// A V with a tick hanging from the top centre.
    case vee
    /// An inverted V with a tick rising from the bottom centre.
    case wedge
    /// An arrow: a diagonal rising to the top-right corner, with its head.
    case arrow
    /// An X with a stub across the bottom centre.
    case cross
    /// A T with a stub on the bottom-left.
    case tee
    /// An F: post, top bar and a shorter middle bar.
    case eff
    /// A stepped S: three bars joined left then right.
    case ess
    /// A W.
    case wave
    /// A question-mark hook: top bar, right post to the middle, back to the
    /// centre, down to the bottom.
    case hook
    /// A slanted step: top-left bar, a diagonal through the centre,
    /// bottom-right bar.
    case bolt
}

public enum Glyphs {
    public static let lineWidth: CGFloat = 1.6

    /// The glyph's inset inside its image, in points (x, y).
    public static let inset = (dx: CGFloat(1.5), dy: CGFloat(2))
    /// The coloured variant's ink (route C pre-registration section 5): far
    /// from both inks the bar uses, so the frozen detector cannot see it.
    public static let colouredInk = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)

    /// The ordinary variant is a template image (the bar inks it); the
    /// coloured one is the same shape as a non-template image in `colouredInk`.
    public static func image(_ glyph: Glyph, side: CGFloat, coloured: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            draw(glyph, in: rect.insetBy(dx: inset.dx, dy: inset.dy), colour: coloured ? colouredInk : .black)
            return true
        }
        image.isTemplate = !coloured
        return image
    }

    /// Strokes `glyph` into `box` with the current graphics context.
    public static func draw(_ glyph: Glyph, in box: NSRect, colour: NSColor = .black) {
        colour.setStroke()

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
        case .hidden2:
            bracket.move(to: NSPoint(x: box.minX, y: box.maxY))
            bracket.line(to: NSPoint(x: box.minX, y: box.minY))
            bracket.line(to: NSPoint(x: box.maxX, y: box.minY))
            bracket.line(to: NSPoint(x: box.maxX, y: box.maxY))
            accent.move(to: NSPoint(x: midX, y: box.minY + 1))
            accent.line(to: NSPoint(x: midX, y: midY + 1))
        case .hidden3:
            bracket.move(to: NSPoint(x: box.minX, y: box.minY))
            bracket.line(to: NSPoint(x: box.minX, y: box.maxY))
            bracket.move(to: NSPoint(x: box.maxX, y: box.minY))
            bracket.line(to: NSPoint(x: box.maxX, y: box.maxY))
            accent.move(to: NSPoint(x: box.minX, y: midY))
            accent.line(to: NSPoint(x: box.maxX, y: midY))
        case .hidden4:
            bracket.move(to: NSPoint(x: box.minX, y: box.minY))
            bracket.line(to: NSPoint(x: box.minX, y: box.maxY))
            bracket.line(to: NSPoint(x: box.maxX, y: box.minY))
            bracket.line(to: NSPoint(x: box.maxX, y: box.maxY))
        default:
            drawRouteC(glyph, in: box, bracket: bracket, accent: accent)
        }
        bracket.stroke()
        accent.stroke()
    }

    /// The thirteen route C glyphs, split out to keep `draw` short.
    private static func drawRouteC(_ glyph: Glyph, in box: NSRect, bracket: NSBezierPath, accent: NSBezierPath) {
        let (minX, maxX, minY, maxY) = (box.minX, box.maxX, box.minY, box.maxY)
        let (midX, midY) = (box.midX, box.midY)
        func path(_ p: NSBezierPath, _ points: [(CGFloat, CGFloat)]) {
            guard let first = points.first else { return }
            p.move(to: NSPoint(x: first.0, y: first.1))
            for point in points.dropFirst() { p.line(to: NSPoint(x: point.0, y: point.1)) }
        }
        switch glyph {
        case .ell:
            path(bracket, [(minX, maxY), (minX, minY), (maxX, minY)])
            path(accent, [(maxX, maxY), (maxX - 2.5, maxY - 2.5)])
        case .gamma:
            path(bracket, [(minX, minY), (minX, maxY), (maxX, maxY)])
            path(accent, [(maxX - 3, minY), (maxX, minY)])
        case .zed:
            path(bracket, [(minX, maxY), (maxX, maxY), (minX, minY), (maxX, minY)])
            path(accent, [(minX, maxY), (minX, maxY - 2.5)])
        case .vee:
            path(bracket, [(minX, maxY), (midX, minY), (maxX, maxY)])
            path(accent, [(midX, maxY), (midX, maxY - 2.5)])
        case .wedge:
            path(bracket, [(minX, minY), (midX, maxY), (maxX, minY)])
            path(accent, [(midX, minY), (midX, minY + 2.5)])
        case .arrow:
            path(bracket, [(minX, minY), (maxX, maxY)])
            path(accent, [(maxX - 3.5, maxY), (maxX, maxY), (maxX, maxY - 3.5)])
        case .cross:
            path(bracket, [(minX, minY), (maxX, maxY)])
            path(bracket, [(minX, maxY), (maxX, minY)])
            path(accent, [(midX - 1.5, minY), (midX + 1.5, minY)])
        case .tee:
            path(bracket, [(minX, maxY), (maxX, maxY)])
            path(bracket, [(midX, maxY), (midX, minY)])
            path(accent, [(minX, minY), (minX + 2.5, minY)])
        case .eff:
            path(bracket, [(minX, minY), (minX, maxY), (maxX, maxY)])
            path(accent, [(minX, midY), (maxX - 2, midY)])
        case .ess:
            path(bracket, [(maxX, maxY), (minX, maxY), (minX, midY), (maxX, midY), (maxX, minY), (minX, minY)])
        case .wave:
            path(bracket, [(minX, maxY), (minX + 2.25, minY), (midX, maxY - 2), (maxX - 2.25, minY), (maxX, maxY)])
        case .hook:
            path(bracket, [(minX, maxY), (maxX, maxY), (maxX, midY), (midX, midY), (midX, minY)])
        case .bolt:
            path(bracket, [(minX, maxY), (midX - 1, maxY), (midX + 1, minY), (maxX, minY)])
        case .target, .reference, .alt, .hidden2, .hidden3, .hidden4:
            break
        }
    }
}
