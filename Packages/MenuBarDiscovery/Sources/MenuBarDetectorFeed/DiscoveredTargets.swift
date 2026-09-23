import Darwin
import IceCore

/// Turns a list of `ItemKey`s into the `[String: pid_t]` shape
/// `MenuBarAXReading.read(items:)` and `Sampler.sample(items:)` want: each
/// key's `encoded` string as the caller-chosen id, its `pid` as the pid to
/// read. Positional keys are dropped (D14/D15: `.positional` never names a
/// detector target) -- `key.childIndex != nil` is exactly how `ItemKeying`
/// marks a positional key (plan section 4.1.3), so no separate `basis` field
/// is needed here.
public enum DiscoveredTargets {
    public static func items(_ keys: [ItemKey]) -> [String: pid_t] {
        var result = [String: pid_t]()
        for key in keys where key.childIndex == nil {
            result[key.encoded] = key.pid
        }
        return result
    }
}
