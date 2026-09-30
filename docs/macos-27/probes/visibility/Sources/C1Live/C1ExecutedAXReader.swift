import Darwin
import MenuBarCapture

/// Adapts one `MenuBarAXReading` to run through a shared `C1AXExecutor`
/// (item 2). Several of these, each wrapping a different underlying
/// reader (the owner observer's `LiveMenuBarAXReader`,
/// `HidingVerification`'s own `DiscoveredFrameReader`), share one
/// executor so the stage's "no two AX reads overlap, and one stuck read
/// stucks every later one" holds across all of them, not just within a
/// single reader instance.
public struct C1ExecutedAXReader: MenuBarAXReading {
    private let executor: C1AXExecutor
    private let wrapped: any MenuBarAXReading

    public init(executor: C1AXExecutor, wrapping reader: any MenuBarAXReading) {
        self.executor = executor
        self.wrapped = reader
    }

    public func read(items: [String: pid_t]) -> MenuBarAXSnapshot? {
        executor.run { wrapped.read(items: items) }
    }
}
