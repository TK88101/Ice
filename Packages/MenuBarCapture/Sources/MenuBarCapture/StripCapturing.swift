import IceCore

/// Captures the menu bar strip.
///
/// Read-only by contract: a conforming type may look at the screen and
/// nothing else. Nothing in this package launches an app, adds or moves a
/// menu bar item, posts a mouse or keyboard event, or writes an
/// Accessibility attribute.
public protocol StripCapturing: Sendable {
    /// `nil` on any failure: no permission, no display, or the underlying
    /// capture API returning nothing. A failed capture never throws -- the
    /// caller (`Sampler`) treats every failure the same way, by producing no
    /// sample.
    func capture() -> StripImage?
}
