// C2 (docs/plans/2026-09-28-c2-protocol.md 6.1 item 4): the Menus helper --
// launched first in step 2, calibrated to its width class, activated, and
// checked frontmost with the same title edges before every cycle. Its titles
// are never observed items (that would collapse the frozen fold region).
import C1Core
import C2Core
import Darwin
import Foundation

extension StageC1 {
    /// Tolerance for "the same title edges" between calibration and preflight.
    static let menuEdgeTolerancePt = 1.0
    static let menuSettleSeconds = 0.3

    /// `.ok` with no Menus configured (C1).
    func launchAndCalibrateMenus(channel: HelperControlChannel) -> StepResult {
        guard let menus = apps.menus else { return .ok }
        guard !isTerminal else { return .abort("terminal before launching Menus") }
        let lifetime = String(Int(StageC1.effectiveHelperLifetimeSeconds))
        guard let helper = environment.helperLauncher.launch(appURL: menus.app, bundleID: C1HelperRole.protected, role: "menus", arguments: ["--role", "menus", "--lifetime", lifetime], controllerPID: getpid()) else {
            return .abort("could not launch Menus")
        }
        channel.register(helper)
        menusHelper = helper
        guard !isTerminal else { return .abort("terminal while launching Menus") }
        guard helper.awaitReply("up", timeout: 5) != nil else { return .abort("Menus never came up") }

        // A background app's titles are not laid out on the bar, so Menus
        // comes forward before its titles are measured (2026-09-29
        // rehearsal: calibrating behind Terminal never reached long).
        _ = environment.frontmost.activate(pid: helper.pid)
        var calibration = C2MenuCalibration(width: menus.width)
        var step = C2MenuCalibration.Step.send(calibration.count)
        while case .send(let count) = step {
            guard !isTerminal else { return .abort("terminal while calibrating Menus") }
            helper.send("menus \(count)")
            environment.pump.run(Self.menuSettleSeconds)
            let lastTitleEnd = environment.frontmost.menuTitleRightEdges(pid: helper.pid)?.last
            evidence?.record("menus.calibrationRead", ["count": count, "lastTitleEnd": lastTitleEnd ?? NSNull()])
            step = calibration.next(lastTitleEnd: lastTitleEnd)
        }
        guard case .done(let count) = step else {
            if case .failed(let why) = step { evidence?.record("menus.calibrationFailed", ["width": menus.width.rawValue, "reason": why]) }
            return .abort("Menus calibration failed")
        }

        _ = environment.frontmost.activate(pid: helper.pid)
        environment.pump.run(Self.menuSettleSeconds)
        guard environment.frontmost.frontmostPID() == helper.pid, let edges = environment.frontmost.menuTitleRightEdges(pid: helper.pid) else {
            return .abort("Menus is not frontmost after activation")
        }
        menusCalibratedEdges = edges
        evidence?.record("menus.calibrated", ["width": menus.width.rawValue, "count": count, "rightEdges": edges])
        return .ok
    }

    /// Before every cycle's preflight: Menus still frontmost, same title edges.
    /// `true` with no Menus configured (C1).
    func menusStillInPlace(label: String) -> Bool {
        guard let helper = menusHelper else { return true }
        let edges = environment.frontmost.menuTitleRightEdges(pid: helper.pid)
        let frontmost = environment.frontmost.frontmostPID() == helper.pid
        let same = edges.map { $0.count == menusCalibratedEdges.count && zip($0, menusCalibratedEdges).allSatisfy { abs($0 - $1) <= Self.menuEdgeTolerancePt } } ?? false
        guard frontmost, same else {
            evidence?.record("preflight.frontmostLost", ["label": label, "frontmost": frontmost, "rightEdges": edges ?? []])
            return false
        }
        return true
    }
}
