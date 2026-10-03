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
        setLength(target.length)
        guard hiddenNow("B-hidden") else { return (nil, "the member is not hidden clean at \(Band.format(target.length)) pt") }
        var pushedOff = [PressTrial]()
        for i in 1...SpikeBRules.trials {
            pushedOff.append(trial(helper, pid: pid, identifier: identifier, label: "off-\(i)"))
            clock.sleep(until: clock.now() + plan.trialGap)
        }
        var fallback = [PressTrial]()
        if SpikeBRules.openedCount(pushedOff) < SpikeBRules.needed {
            for i in 1...SpikeBRules.trials {
                rest()
                clock.sleep(until: lastChange + plan.settle)
                fallback.append(trial(helper, pid: pid, identifier: identifier, label: "shown-\(i)"))
                setLength(target.length)
                let hidden = hiddenNow("B-rehide-\(i)")
                evidence.record("rehide", ["trial": i, "hidden": hidden])
                clock.sleep(until: clock.now() + plan.trialGap)
            }
        }
        rest()
        return (SpikeBResult(length: target.length, pushedOff: pushedOff, fallback: fallback), nil)
    }

    /// Two brackets after the settle read hidden clean.
    private func hiddenNow(_ label: String) -> Bool {
        var brackets = [StepObservation]()
        for i in 1...2 {
            let notBefore = i == 1 ? lastChange + plan.settle : clock.now() + plan.bracketGap
            if let read = bracket("\(label)-\(i)", notBefore: notBefore) { brackets.append(read.observation) }
        }
        let outcome = SpikeRules.outcome(brackets, controlPassed: true)
        evidence.record("hidden", ["label": label, "outcome": "\(outcome)"])
        return outcome.isClean
    }

    /// One press: watch the helper's `menu open` line and the window server
    /// for a pop-up menu window of its pid, then close the menu again.
    private func trial(_ helper: IceBarHelper, pid: pid_t, identifier: String, label: String) -> PressTrial {
        let replies = helper as? SpikeReplyReading
        let start = clock.now()
        press.beginPress(pid: pid, identifier: identifier)
        var openedAfter: Double?
        var signals = [String]()
        let deadline = start + SpikeBRules.openTimeout + 0.5
        while clock.now() <= deadline, signals.count < 2 {
            if !signals.contains("helper"), let reply = replies?.awaitReply(SpikeHelperFlags.menuReply, timeout: Self.pollSeconds),
               reply["event"] as? String == "open" {
                signals.append("helper")
                openedAfter = openedAfter ?? clock.now() - start
            }
            if !signals.contains("window"),
               environment.windows.windows(owners: [pid]).contains(where: { $0.layer == SpikeBRules.popUpMenuWindowLayer }) {
                signals.append("window")
                openedAfter = openedAfter ?? clock.now() - start
            }
            if signals.count < 2 { clock.sleep(until: clock.now() + Self.pollSeconds) }
        }
        if let image = environment.capturer.capture() {
            sequence += 1
            evidence.keep(image, label: "\(sequence)-press-\(label)")
        }
        helper.send(SpikeHelperFlags.closeMenu)
        var closed = false
        if openedAfter != nil {
            closed = replies?.awaitReply(SpikeHelperFlags.menuReply, timeout: 1.0)?["event"] as? String == "close"
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
