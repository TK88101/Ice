// T0, spike B: the k = 1 member with a menu, pushed off at the band's
// midpoint; five AXPress trials there, and if they fail, five on the
// show-press-rehide path. Plan D3: the menu must be on screen within 1 s.
import Darwin
import IceBarStage
import SpikeCore

extension SpikeStage {
    func pressStage(_ target: PressTarget) -> (SpikeBResult?, String?) {
        let body = pressBody(target)
        if let problem = teardown(), body.1 == nil { return (body.0, "teardown: \(problem)") }
        return body
    }

    private func pressBody(_ target: PressTarget) -> (SpikeBResult?, String?) {
        if let problem = launch(target.profile, memberMenu: true) { return (nil, problem) }
        guard restControl() else { return (nil, "rest control failed") }
        guard let member = members.first, let helper = launched.first(where: { $0.id == member })?.helper, let pid = pids[member],
              let identifier = roster.first(where: { $0.id == member })?.identifier
        else { return (nil, "no member") }
        // The helper's `menu` lines are one of the two signs of the menu; a
        // helper that cannot be read for them is refused, not silently ignored.
        guard let replies = helper as? SpikeReplyReading else { return (nil, "the member helper cannot report its menu") }
        setLength(target.length)
        guard hiddenNow("B-hidden") else { return (nil, "the member is not hidden clean at \(Band.format(target.length)) pt") }
        let press = PressSubject(helper: helper, replies: replies, pid: pid, identifier: identifier)
        var pushedOff = [PressTrial]()
        for i in 1...SpikeBRules.trials {
            pushedOff.append(trial(press, label: "off-\(i)"))
            clock.sleep(until: clock.now() + SpikeStagePlan.trialGap)
        }
        var fallback = [PressTrial]()
        if SpikeBRules.openedCount(pushedOff) < SpikeBRules.needed {
            for i in 1...SpikeBRules.trials {
                rest()
                clock.sleep(until: lastChange + settle)
                fallback.append(trial(press, label: "shown-\(i)"))
                setLength(target.length)
                let hidden = hiddenNow("B-rehide-\(i)")
                evidence.record("rehide", ["trial": i, "hidden": hidden])
                clock.sleep(until: clock.now() + SpikeStagePlan.trialGap)
            }
        }
        rest()
        return (SpikeBResult(length: target.length, pushedOff: pushedOff, fallback: fallback), nil)
    }

    /// The member being pressed and the channels its menu is seen on.
    private struct PressSubject {
        let helper: IceBarHelper
        let replies: SpikeReplyReading
        let pid: pid_t
        let identifier: String
    }

    /// Two brackets after the settle read hidden clean.
    private func hiddenNow(_ label: String) -> Bool {
        let outcome = SpikeRules.hidden(twoBrackets(label))
        evidence.record("hidden", ["label": label, "outcome": "\(outcome)"])
        return outcome.isClean
    }

    /// One press: watch the helper's `menu open` line and the window server
    /// for a pop-up menu window of its pid, then close the menu again.
    private func trial(_ subject: PressSubject, label: String) -> PressTrial {
        let (helper, replies, pid, identifier) = (subject.helper, subject.replies, subject.pid, subject.identifier)
        let start = clock.now()
        press.beginPress(pid: pid, identifier: identifier)
        var openedAfter: Double?
        var signals = [String]()
        let deadline = start + SpikeBRules.openTimeout + 0.5
        // `awaitReply` itself waits up to a poll period for the helper's line;
        // the window list is read right after it, and the loop sleeps only
        // once the helper's line has come (nothing left to wait on there).
        while clock.now() <= deadline, signals.count < 2 {
            if !signals.contains("helper"), let reply = replies.awaitReply(SpikeHelperFlags.menuReply, timeout: Self.pollSeconds),
               reply["event"] as? String == "open" {
                signals.append("helper")
                openedAfter = openedAfter ?? clock.now() - start
            }
            if !signals.contains("window"),
               environment.windows.windows(owners: [pid]).contains(where: { $0.layer == SpikeBRules.popUpMenuWindowLayer }) {
                signals.append("window")
                openedAfter = openedAfter ?? clock.now() - start
            }
            if signals.contains("helper"), signals.count < 2 { clock.sleep(until: clock.now() + Self.pollSeconds) }
        }
        if let image = environment.capturer.capture() {
            sequence += 1
            evidence.keep(image, label: "\(sequence)-press-\(label)")
        }
        helper.send(SpikeHelperFlags.closeMenu)
        var closed = false
        if openedAfter != nil {
            closed = replies.awaitReply(SpikeHelperFlags.menuReply, timeout: 1.0)?["event"] as? String == "close"
        }
        var result = press.pressResult()
        let resultDeadline = clock.now() + Self.pressResultWait
        while result == nil, clock.now() < resultDeadline {
            clock.sleep(until: clock.now() + Self.pollSeconds)
            result = press.pressResult()
        }
        evidence.record("press", ["label": label, "pressError": result?.error ?? -1, "pressSeconds": result?.seconds ?? -1,
                                  "openedAfter": openedAfter ?? -1, "signals": signals, "closed": closed])
        return PressTrial(pressError: result?.error, openedAfter: openedAfter, signals: signals, closed: closed)
    }
}
