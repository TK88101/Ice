import IceCore

/// One process's worth of the AX walk (plan section 4.2): everything
/// `MenuBarDiscoverer` needs to know about one pid's `AXExtrasMenuBar`, as a
/// single call so a fake can drive every test in `MenuBarDiscovererTests`
/// without touching Accessibility.
public protocol ExtrasReading: Sendable {
    func read(_ process: ProcessInfoRecord, timeout: Double) -> RawRead
}
