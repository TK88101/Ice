import Foundation
import IceCore

/// Reads swctl's `assess`/`baseline` fields into IceCore's plain-value frame
/// types. Nothing here is a guess about pixels — only about which JSON field
/// holds which fact, per docs/macos-27/probes/safewidth's `Evidence.swift` and
/// `LiveWorld.swift`.
enum Frames {
    /// `ownAX`: our helpers' Accessibility frames (`IceSpike4-target`,
    /// `IceSpike4-spacer`, `IceSpike4-protected`), each `{id, x, y, w}`.
    static func ownAX(_ assess: Record) throws -> [String: ItemFrame] {
        let entries = try assess.recordArray("ownAX", context: "assess.ownAX")
        var frames: [String: ItemFrame] = [:]
        for entry in entries {
            let id = try entry.string("id", context: "ownAX entry")
            let x = try entry.double("x", context: "ownAX entry")
            let y = try entry.double("y", context: "ownAX entry")
            let w = try entry.double("w", context: "ownAX entry")
            frames[Self.shortID(id)] = ItemFrame(id: Self.shortID(id), minX: x, minY: y, width: w, height: 20)
        }
        return frames
    }

    /// `IceSpike4-target` -> `target`, `IceSpike4-protected` -> `protected`.
    static func shortID(_ ownAXID: String) -> String {
        String(ownAXID.dropFirst("IceSpike4-".count))
    }

    /// `newAgentItems`: `[[x, w], ...]` — `MenuBarAgent` items not already in
    /// the baseline set (LiveWorld.swift `newAgentItems`). `minY` is not
    /// carried; 0 is always on-bar, which is all any rule checks.
    static func newAgentItems(_ assess: Record) throws -> [AgentFrame] {
        let pairs = try assess.array("newAgentItems", context: "assess.newAgentItems")
        return try pairs.map { pair in
            guard let list = pair as? [Any], list.count == 2,
                  let x = (list[0] as? Double) ?? (list[0] as? Int).map(Double.init),
                  let w = (list[1] as? Double) ?? (list[1] as? Int).map(Double.init)
            else {
                throw ReplayError.decodeFailed("newAgentItems entry")
            }
            return AgentFrame(minX: x, minY: 0, width: w)
        }
    }

    /// One user item's frame from the `baseline` record's `items` array
    /// (`{id, x, w, kind, presence}` — no `y`, so 0 is used; see `RunContext`).
    static func userItemFrame(id: String, in baseline: Record) throws -> ItemFrame {
        let items = try baseline.recordArray("items", context: "baseline")
        guard let entry = try items.first(where: { try $0.string("id", context: "baseline item") == id }) else {
            throw ReplayError.reconstructionFailed("baseline record has no item '\(id)'")
        }
        return ItemFrame(
            id: id,
            minX: try entry.double("x", context: "baseline item \(id)"),
            minY: 0,
            width: try entry.double("w", context: "baseline item \(id)"),
            height: 20
        )
    }
}
