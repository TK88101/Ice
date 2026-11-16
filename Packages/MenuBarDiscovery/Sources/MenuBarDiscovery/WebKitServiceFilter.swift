import Foundation
import IceCore

/// Leaves WebKit's services out of the live enumeration (plan
/// 2026-11-16-webkit-services, D2): a process is left out only when its kernel
/// path matches `WebKitServiceRule` and its signature is Apple's for that
/// service's own identifier. Anything unread or failed is kept, and the
/// quarantine handles it as before.
///
/// The verdict is kept per process identity (pid and kernel start time), so
/// the signature is asked once per process, not every pass; verdicts of
/// processes no longer enumerated are dropped.
final class WebKitServiceFilter: @unchecked Sendable {
    private var verdicts = [ProcessIdentity: Bool]()
    private let lock = NSLock()

    /// `records` less the WebKit services among them.
    func keeping(
        _ records: [ProcessInfoRecord],
        executablePath: (Int32) -> String?,
        isAppleSigned: (Int32, String) -> Bool
    ) -> [ProcessInfoRecord] {
        lock.withLock {
            let live = Set(records.compactMap(ProcessIdentity.init))
            verdicts = verdicts.filter { live.contains($0.key) }
            return records.filter { record in
                !isService(record, executablePath: executablePath, isAppleSigned: isAppleSigned)
            }
        }
    }

    /// Called under the lock.
    private func isService(
        _ record: ProcessInfoRecord,
        executablePath: (Int32) -> String?,
        isAppleSigned: (Int32, String) -> Bool
    ) -> Bool {
        guard let bundleID = record.bundleID, WebKitServiceRule.serviceIDs.contains(bundleID) else {
            return false
        }
        let identity = ProcessIdentity(record)
        if let identity, let verdict = verdicts[identity] {
            return verdict
        }
        let verdict = WebKitServiceRule.matches(bundleID: bundleID, executablePath: executablePath(record.pid))
            && isAppleSigned(record.pid, bundleID)
        if let identity {
            verdicts[identity] = verdict
        }
        return verdict
    }
}
