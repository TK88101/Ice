// T4/T5 (docs/plans/2026-09-28-c2-protocol.md section 2): reading a
// finished `c2-config` process back -- the pure half; file and JSON I/O stay
// in `vizprobe`.

extension C2Reading {
    /// A `c2.point` record's `reading` field (`"\(reading)"`).
    public init?(name: String) {
        switch name {
        case "hiddenNoFold": self = .hiddenNoFold
        case "hiddenFolded": self = .hiddenFolded
        case "stillDrawn": self = .stillDrawn
        case "notShown": self = .notShown
        default: return nil
        }
    }
}

extension C2ProcessResult.Status {
    /// The process's own `run.verdict`: `pass` means every listed length was
    /// measured; any safety stop is one; everything else is inconclusive.
    public init(verdict: String?) {
        guard let verdict else {
            self = .safetyStop
            return
        }
        if verdict == "pass" {
            self = .completed
        } else if verdict.hasPrefix("safetyStop") {
            self = .safetyStop
        } else {
            self = .inconclusive(verdict)
        }
    }
}

public enum C2Manifest {
    /// `recorded`: the final manifest's own file -> SHA-256 map; `actual`:
    /// the same, hashed now. Equal, and non-empty, or the directory is not
    /// trusted.
    public static func verify(recorded: [String: String], actual: [String: String]) -> Bool {
        !recorded.isEmpty && recorded == actual
    }
}
