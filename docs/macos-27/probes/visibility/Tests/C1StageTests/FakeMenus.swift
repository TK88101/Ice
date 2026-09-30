// C2 T3 (docs/plans/2026-09-28-c2-protocol.md 6.1 item 4): the fake frontmost
// app and its menu titles. Titles are abstract: the app menu ends at 50 pt,
// each of `count` titles adds 60 pt (the last title's right edge is
// 50 + 60 * count), so mid (700...770) is 11 menus and long (>= 1000) is 16.
import C1Core
import C1Stage
import C2Core
import Darwin
import Foundation

final class FakeFrontmost: C1FrontmostControlling, @unchecked Sendable {
    static let menusPID: pid_t = 9010
    /// Whatever was frontmost before (a terminal, say).
    static let otherPID: pid_t = 4242

    private let lock = NSLock()
    private var menusUp = false
    private var count = 0
    private var frontmost: pid_t = otherPID
    /// When set, `frontmostPID()` answers `otherPID` from this read on --
    /// the "something else came forward mid-run" fault.
    private var stealAtRead: Int?
    private var reads = 0
    /// When set, titles are only laid out while Menus is frontmost; otherwise
    /// only the app menu reads back -- the 2026-09-29 rehearsal's suspected
    /// cause (docs/plans/2026-09-29-c2-rehearsal-fixes.md).
    private var titlesNeedFrontmost = false
    private(set) var commands: [String] = []

    func setStealAtRead(_ read: Int) { lock.withLock { stealAtRead = read } }
    func setTitlesNeedFrontmost() { lock.withLock { titlesNeedFrontmost = true } }
    func up() { lock.withLock { menusUp = true } }
    func down() { lock.withLock { menusUp = false; if frontmost == Self.menusPID { frontmost = Self.otherPID } } }
    func handle(_ line: String) {
        lock.withLock {
            commands.append(line)
            if let value = C2MenusCommand.parse(line) { count = value }
        }
    }

    func frontmostPID() -> pid_t? {
        lock.withLock {
            reads += 1
            if let stealAtRead, reads >= stealAtRead { return Self.otherPID }
            return frontmost
        }
    }

    func menuTitleRightEdges(pid: pid_t) -> [Double]? {
        lock.withLock {
            guard menusUp, pid == Self.menusPID else { return nil }
            if titlesNeedFrontmost, frontmost != Self.menusPID { return [50] }
            return [50] + (0..<count).map { 50 + 60 * Double($0 + 1) }
        }
    }

    func activate(pid: pid_t) -> Bool {
        lock.withLock {
            guard menusUp, pid == Self.menusPID else { return false }
            frontmost = pid
            return true
        }
    }
}

/// The Menus helper's own control: `menus <n>` goes to `FakeFrontmost`, not
/// the bar world (it draws no status item).
final class FakeMenusControl: C1HelperControlling, @unchecked Sendable {
    let pid = FakeFrontmost.menusPID
    let frontmost: FakeFrontmost
    let world: FakeBarWorld
    private let lock = NSLock()
    private var running = true

    init(frontmost: FakeFrontmost, world: FakeBarWorld) {
        self.frontmost = frontmost
        self.world = world
        frontmost.up()
    }

    var isRunning: Bool { lock.withLock { running } }
    func awaitReply(_ kind: String, timeout: Double) -> [String: Any]? { kind == "up" ? [:] : nil }
    func send(_ line: String) {
        guard isRunning else { return }
        frontmost.handle(line)
    }
    func quit(timeout: Double) {
        stop()
        world.setDown("menus")
    }

    func requestQuit() {
        stop()
        world.setDownNonBlocking("menus")
    }

    private func stop() {
        lock.withLock { running = false }
        frontmost.down()
    }
}
