import AppKit
import ApplicationServices
import Darwin
import Foundation
import Testing
import IceCore
@testable import MenuBarDetectorFeed

/// The application menu's frame on macOS 27, read from the menu bar owner's
/// own `AXMenuBar` instead of a hit test at the display origin, which there
/// returns a `MenuBarAgent` window (plan 2026-10-07-icebar-menu-frame-fix, E5
/// and F1).
@Suite("ApplicationMenuReader")
struct ApplicationMenuReaderTests {
    final class FakeAXReader: ApplicationMenuAXReading, @unchecked Sendable {
        let result: [ApplicationMenuChild]?
        private(set) var calls: [(pid: pid_t, timeout: Double)] = []

        init(_ result: [ApplicationMenuChild]?) {
            self.result = result
        }

        func menuBarChildren(pid: pid_t, timeout: Double) -> [ApplicationMenuChild]? {
            calls.append((pid, timeout))
            return result
        }
    }

    static func child(_ minX: Double, _ width: Double, enabled: Bool = true) -> ApplicationMenuChild {
        ApplicationMenuChild(isEnabled: enabled, frame: BarRect(minX: minX, minY: 0, width: width, height: 24))
    }

    func frame(_ children: [ApplicationMenuChild]?, pid: pid_t? = 42) -> BarRect? {
        ApplicationMenuReader(reader: FakeAXReader(children)).frame(owningPID: pid)
    }

    @Test("the enabled children's frames are united")
    func union() {
        let result = frame([Self.child(10, 30), Self.child(40, 60), Self.child(100, 50)])
        #expect(result == BarRect(minX: 10, minY: 0, width: 140, height: 24))
    }

    @Test("a disabled child is left out")
    func disabledLeftOut() {
        #expect(frame([Self.child(10, 30), Self.child(40, 400, enabled: false)]) == BarRect(minX: 10, minY: 0, width: 30, height: 24))
    }

    @Test("a child with no frame or a frame that is not a number is skipped on its own")
    func unusableChildSkipped() {
        let children = [
            Self.child(10, 30),
            ApplicationMenuChild(isEnabled: true, frame: nil),
            ApplicationMenuChild(isEnabled: true, frame: BarRect(minX: .nan, minY: 0, width: 20, height: 24)),
            ApplicationMenuChild(isEnabled: true, frame: BarRect(minX: 60, minY: 0, width: .infinity, height: 24)),
            Self.child(40, 20),
        ]
        #expect(frame(children) == BarRect(minX: 10, minY: 0, width: 50, height: 24))
    }

    @Test("no pid, no menu bar, no usable child or no width is no frame")
    func noFrame() {
        #expect(frame([Self.child(10, 30)], pid: nil) == nil)
        #expect(frame(nil) == nil)
        #expect(frame([]) == nil)
        #expect(frame([Self.child(10, 30, enabled: false)]) == nil)
        #expect(frame([ApplicationMenuChild(isEnabled: true, frame: nil)]) == nil)
        #expect(frame([Self.child(10, 0)]) == nil)
        #expect(frame([Self.child(-1e308, 1), Self.child(1e308, 1)]) == nil)
        #expect(frame([Self.child(1e308, 1e308)]) == nil)
    }

    @Test("no pid reads nothing; a pid is read once, with the messaging timeout")
    func readsTheOwnerOnly() {
        let none = FakeAXReader([Self.child(10, 30)])
        _ = ApplicationMenuReader(reader: none).frame(owningPID: nil)
        #expect(none.calls.isEmpty)

        let fake = FakeAXReader([Self.child(10, 30)])
        _ = ApplicationMenuReader(reader: fake).frame(owningPID: 42)
        #expect(fake.calls.count == 1)
        #expect(fake.calls.first?.pid == 42)
        #expect(fake.calls.first?.timeout == ApplicationMenuReader.messagingTimeout)
        #expect(ApplicationMenuReader.messagingTimeout == 0.25)
    }
}

@Suite("LiveApplicationMenuAXReader")
struct LiveApplicationMenuAXReaderTests {
    /// The live read answers nil, not an empty list, when there is no menu bar
    /// to read: here a pid no process has. Its success path is checked live
    /// (`icewatch menu-frame`, plan F4), as no fake can stand in for AX.
    @Test("no process, no menu bar: nil")
    func noProcess() {
        #expect(LiveApplicationMenuAXReader().menuBarChildren(pid: 999_999, timeout: 0.25) == nil)
    }

    /// Finder always runs and has a menu bar; read-only. Needs this process to
    /// be trusted for Accessibility (a trusted Terminal's child is), so it is
    /// skipped elsewhere.
    @Test("Finder's menu bar: enabled children with frames", .enabled(if: AXIsProcessTrusted() && Self.finderPID != nil))
    func finder() throws {
        let pid = try #require(Self.finderPID)
        let children = try #require(LiveApplicationMenuAXReader().menuBarChildren(pid: pid, timeout: 0.25))
        #expect(children.contains { $0.isEnabled && $0.frame != nil })
        #expect(ApplicationMenuReader.live.frame(owningPID: Self.finderPID) != nil)
    }

    static var finderPID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.processIdentifier
    }
}

@Suite("MenuBarOwnerPID")
struct MenuBarOwnerPIDTests {
    @Test("the owner given at creation is there at once, before any change")
    func initialValue() {
        #expect(MenuBarOwnerPID(initial: 501).current == 501)
        #expect(MenuBarOwnerPID(initial: nil).current == nil)
    }

    @Test("a change is seen by a reader on another thread")
    func updateSeenFromBackground() async {
        let holder = MenuBarOwnerPID(initial: 501)
        holder.update(777)
        let seen = await Task.detached { holder.current }.value
        #expect(seen == 777)
        holder.update(nil)
        #expect(await Task.detached { holder.current }.value == nil)
    }
}
