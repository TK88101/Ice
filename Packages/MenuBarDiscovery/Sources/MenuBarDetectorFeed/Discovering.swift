import IceCore
import MenuBarDiscovery

/// The one thing `HidingVerification` needs from a discovery pass (plan
/// section 4.3, T7): a fresh, up-to-date `DiscoveredItemSet` (and everything
/// that came with the pass that produced it), or `nil` when the pass could
/// not produce one at all.
///
/// A separate protocol from `MenuBarDiscoverer` itself so `HidingVerification`
/// can be tested against a fake that never touches Accessibility, AppKit, or
/// a real serial queue.
public protocol Discovering: Sendable {
    func discover(previous: DiscoveredItemSet?) async -> DiscoveryResult?
}

/// `MenuBarDiscoverer` (T5, `MenuBarDiscovery`) already has exactly this
/// shape -- this file only states that it conforms; T5's own source is never
/// edited to add the conformance there.
extension MenuBarDiscoverer: Discovering {}
