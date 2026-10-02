// Q20: the one argument list the sitting's sequencer hands each `vizprobe
// icebar-step` process, parsed back into the step's plan (round trip).
import C2Core
import IceBarRunCore
@testable import IceBarStage
import Testing

@Suite("Q20: icebar-step arguments")
struct StepArgumentsTests {
    static let kinds: [StepKind] = [
        .s0, .sAdvSweep(SAdvVariant(appearance: .light, colouredMembers: true)), .sAdvChevron(SAdvVariant(appearance: .dark, colouredMembers: false)),
        .s1Bracket([520, 536, 551.5]), .s1Confirm(650),
    ]

    @Test("every kind round-trips", arguments: kinds)
    func roundTrip(kind: StepKind) throws {
        let step = StepArguments(kind: kind, members: 4, menu: .mid, appsPath: "/a", evidencePath: "/e/001-x")
        #expect(step.arguments.first == "icebar-step")
        #expect(try StepArguments.parse(step.arguments).get() == step)
    }

    @Test("the coloured members of a coloured S-adv variant only")
    func coloured() {
        #expect(StepArguments(kind: .sAdvSweep(SAdvVariant(appearance: .dark, colouredMembers: true)), members: 4, menu: .short, appsPath: "/a", evidencePath: "/e").colouredMembers)
        #expect(!StepArguments(kind: .s1Confirm(650), members: 4, menu: .short, appsPath: "/a", evidencePath: "/e").colouredMembers)
    }

    @Test("a malformed list is refused", arguments: [
        ["icebar-step"],
        ["icebar-step", "--kind", "s9", "--members", "2", "--menu", "short", "--apps", "/a", "--evidence", "/e"],
        ["icebar-step", "--kind", "s0", "--members", "0", "--menu", "short", "--apps", "/a", "--evidence", "/e"],
        ["icebar-step", "--kind", "s0", "--members", "2", "--menu", "wide", "--apps", "/a", "--evidence", "/e"],
        ["icebar-step", "--kind", "s1-bracket", "--members", "2", "--menu", "short", "--apps", "/a", "--evidence", "/e"],
        ["icebar-step", "--kind", "s1-bracket", "--lengths", "1,x", "--members", "2", "--menu", "short", "--apps", "/a", "--evidence", "/e"],
        ["icebar-step", "--kind", "sadv-sweep", "--variant", "grey-ordinary", "--members", "4", "--menu", "short", "--apps", "/a", "--evidence", "/e"],
        ["icebar-step", "--kind", "s1-confirm", "--members", "2", "--menu", "short", "--apps", "/a", "--evidence", "/e"],
    ])
    func refused(arguments: [String]) {
        guard case .failure = StepArguments.parse(arguments) else { Issue.record("accepted \(arguments)"); return }
    }

    @Test("the watchdog fits inside the helpers' 30 min lifetime cap")
    func watchdog() {
        for kind in Self.kinds {
            let step = StepArguments(kind: kind, members: 2, menu: .short, appsPath: "/a", evidencePath: "/e")
            #expect(step.watchdogMinutes * 60 < Double(StepArguments.helperLifetimeSeconds))
        }
        #expect(StepArguments.helperLifetimeSeconds <= 1800)
    }
}
