import Testing
@testable import IceWatchCore

/// icewatch's argument parsing is strict: a safety tool must not run with a
/// silently dropped option (Codex, icewatch review round 2).
@Suite("Options")
struct OptionsTests {
    let valued: Set<String> = ["--domain", "--set", "--controller"]
    let flags: Set<String> = ["--detach"]

    @Test("valued options, repeatable; flags; the child's arguments after --")
    func parse() throws {
        let parsed = try Options.parse(["--domain", "d", "--set", "A=false", "--set", "B=true", "--detach", "--controller", "7", "--", "-X", "NO"], valued: valued, flags: flags)
        #expect(parsed.values["--domain"] == ["d"])
        #expect(parsed.values["--set"] == ["A=false", "B=true"])
        #expect(parsed.flags == ["--detach"])
        #expect(parsed.child == ["-X", "NO"])
    }

    @Test("a valued option without its value, or followed by another option, is refused")
    func dangling() {
        #expect(throws: Options.Problem.self) { try Options.parse(["--domain", "d", "--set"], valued: valued, flags: flags) }
        #expect(throws: Options.Problem.self) { try Options.parse(["--set", "--detach"], valued: valued, flags: flags) }
        #expect(throws: Options.Problem.self) { try Options.parse(["--set", "--", "x"], valued: valued, flags: flags) }
    }

    @Test("an unknown option or a stray word is refused")
    func unknown() {
        #expect(throws: Options.Problem.self) { try Options.parse(["--sett", "A=false"], valued: valued, flags: flags) }
        #expect(throws: Options.Problem.self) { try Options.parse(["stray"], valued: valued, flags: flags) }
    }

    @Test("a flag given twice, or a single-valued option given twice, is refused")
    func repeats() {
        #expect(throws: Options.Problem.self) { try Options.parse(["--detach", "--detach"], valued: valued, flags: flags) }
        #expect(throws: Options.Problem.self) { try Options.parse(["--domain", "a", "--domain", "b"], valued: valued, flags: flags, repeatable: ["--set"]) }
    }
}
