import IceCore

/// One process's worth of the AX walk (plan section 4.2): everything
/// `MenuBarDiscoverer` needs to know about one pid's `AXExtrasMenuBar`, as a
/// single call so a fake can drive every test in `MenuBarDiscovererTests`
/// without touching Accessibility.
///
/// `interrupt` is polled before every child of the walk (2026-09-25
/// responsiveness-quarantine plan, 3.7): when it answers `true` the read returns
/// at once with `walkInterrupted` set. There is deliberately no overload without
/// it -- every caller says whether its walks can be cut short, and those that
/// cannot pass `{ false }`.
public protocol ExtrasReading: Sendable {
    func read(_ process: ProcessInfoRecord, timeout: Double, interrupt: () -> Bool) -> RawRead
}
