// T0: `vizprobe spike-run`'s arguments and vzhelper's `--menu` flag.
import C2Core
import SpikeCore
import Testing

@Suite("T0: spike arguments")
struct SpikeArgumentsTests {
    static let required = ["spike-run", "--apps", "/a", "--evidence-root", "/e", "--expect-user", "icetest", "--owner-user", "me", "--expect-geometry", "1728x32:771.5-956.5"]

    @Test("the required options parse with the standard plan")
    func standard() throws {
        let parsed = try SpikeArguments.parse(Self.required).get()
        #expect(parsed.appsPath == "/a")
        #expect(parsed.evidenceRoot == "/e")
        #expect(parsed.expectedUser == "icetest")
        #expect(parsed.ownerUser == "me")
        #expect(parsed.expectedGeometry == "1728x32:771.5-956.5")
        #expect(parsed.members == [1, 2, 4, 8])
        #expect(parsed.menus == [.short, .mid])
        #expect(parsed.lengths == .standard)
        #expect(parsed.runB)
    }

    @Test("members, menus, lengths and --no-b override the plan")
    func overrides() throws {
        let parsed = try SpikeArguments.parse(Self.required + ["--members", "1,2", "--menus", "mid", "--lengths", "600:896:16", "--no-b"]).get()
        #expect(parsed.members == [1, 2])
        #expect(parsed.menus == [.mid])
        #expect(parsed.lengths.values.count == 19)
        #expect(!parsed.runB)
    }

    @Test("a missing required option or a bad value is refused by name")
    func refused() {
        #expect(SpikeArguments.parse(Array(Self.required.dropLast(2))) == .failure(.missing("--expect-geometry")))
        #expect(SpikeArguments.parse(Self.required + ["--members", "0"]) == .failure(.invalid("--members")))
        #expect(SpikeArguments.parse(Self.required + ["--members", "17"]) == .failure(.invalid("--members")))
        #expect(SpikeArguments.parse(Self.required + ["--menus", "long"]) == .failure(.invalid("--menus")))
        #expect(SpikeArguments.parse(Self.required + ["--lengths", "1:2"]) == .failure(.invalid("--lengths")))
    }

    @Test("the member with a menu gets vzhelper's --menu flag after its base arguments")
    func menuFlag() {
        #expect(SpikeHelperFlags.menu == "--menu")
        #expect(SpikeHelperFlags.withMenu(["--items", "1"]) == ["--items", "1", "--menu"])
        #expect(SpikeHelperFlags.closeMenu == "closemenu")
        #expect(SpikeHelperFlags.menuReply == "menu")
    }
}
