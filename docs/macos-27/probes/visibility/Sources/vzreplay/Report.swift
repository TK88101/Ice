import Foundation

enum Report {
    static func print(_ results: [ReplayResult]) {
        for result in results {
            let mark = result.agree ? "AGREE" : "DISAGREE"
            Swift.print("[\(mark)] \(result.entry.id)")
            Swift.print("  expected: \(result.entry.expected)  (from \(result.entry.oracleField) = \(result.entry.oracleValue))")
            Swift.print("  IceCore:  \(result.iceCoreSaid)")
            Swift.print("  diagnosis: \(result.diagnosis)")
        }
        let total = results.count
        let agreed = results.filter(\.agree).count
        Swift.print("--- \(agreed)/\(total) agree ---")
    }
}
