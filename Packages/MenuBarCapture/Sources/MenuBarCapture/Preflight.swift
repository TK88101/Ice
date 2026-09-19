import ApplicationServices
import IceCore

/// Why the environment is not ready to sample. Each reason names exactly one
/// of the plan's four checks (docs/plans/2026-09-19-visibility-adapter.md
/// section 4).
public enum PreflightReason: Equatable, Sendable {
    case captureUnavailable
    case accessibilityNotTrusted
    case menuBarAgentUnreadable
    case menuBarAutoHidden
}

public enum PreflightResult: Equatable, Sendable {
    case ready(geometry: BarGeometry)
    case unavailable(PreflightReason)
}

/// Four checks, in order, before anything is launched. The first failure
/// stops the chain: nothing after it runs, and no matcher or fold verdict is
/// ever produced from an environment that failed here.
public enum Preflight {
    public static func run(
        capturer: any StripCapturing,
        axReader: any MenuBarAXReading,
        geometry: BarGeometry,
        isTrusted: () -> Bool = { AXIsProcessTrusted() }
    ) -> PreflightResult {
        // 1. Screen capture works: a strip that is not uniformly zero.
        guard let strip = capturer.capture(), !strip.bytes.allSatisfy({ $0 == 0 }) else {
            return .unavailable(.captureUnavailable)
        }
        // 2. Accessibility is trusted for this process.
        guard isTrusted() else {
            return .unavailable(.accessibilityNotTrusted)
        }
        // 3. MenuBarAgent's extras are readable at all.
        guard let snapshot = axReader.read(items: [:]), !snapshot.agentFrames.isEmpty else {
            return .unavailable(.menuBarAgentUnreadable)
        }
        // 4. The bar is visible, not auto-hidden. MenuBarAgent's own items
        // sit inside the bar row when the bar is showing; this reuses facts
        // already gathered above rather than an undocumented defaults key.
        guard snapshot.agentFrames.allSatisfy({ $0.minY >= 0 && $0.minY < geometry.heightPt }) else {
            return .unavailable(.menuBarAutoHidden)
        }
        return .ready(geometry: geometry)
    }
}
