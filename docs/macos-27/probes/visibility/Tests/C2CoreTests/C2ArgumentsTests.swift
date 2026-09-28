import C2Core
import Testing

@Suite("C2ConfigArguments")
struct C2ArgumentsTests {
    let good = ["c2-config", "--apps", "/Users/Shared/IceReverse-c2/apps", "--k", "3", "--menus", "mid", "--lengths", "600,616.5,1000", "--evidence-dir", "/Users/Shared/IceReverse-c2/evidence/x"]

    @Test("a complete argument list parses, and round-trips through `arguments`")
    func parsesAndRoundTrips() throws {
        let parsed = try C2ConfigArguments.parse(good).get()
        #expect(parsed.configuration == C2Configuration(hiddenCount: 3, width: .mid))
        #expect(parsed.lengths == [600, 616.5, 1000])
        #expect(parsed.arguments == good)
    }

    @Test("each missing or invalid argument is refused with its own reason")
    func refusals() {
        func without(_ name: String) -> [String] {
            guard let index = good.firstIndex(of: name) else { return good }
            var copy = good
            copy.removeSubrange(index...(index + 1))
            return copy
        }
        func with(_ name: String, _ value: String) -> [String] {
            var copy = good
            copy[copy.firstIndex(of: name)! + 1] = value
            return copy
        }
        #expect(C2ConfigArguments.parse(without("--apps")) == .failure(.missing("--apps")))
        #expect(C2ConfigArguments.parse(without("--evidence-dir")) == .failure(.missing("--evidence-dir")))
        #expect(C2ConfigArguments.parse(without("--lengths")) == .failure(.missing("--lengths")))
        #expect(C2ConfigArguments.parse(with("--k", "5")) == .failure(.invalid("--k must be 1...4")))
        #expect(C2ConfigArguments.parse(with("--menus", "wide")) == .failure(.invalid("--menus must be short, mid or long")))
        #expect(C2ConfigArguments.parse(with("--lengths", "600,1001")) == .failure(.invalid("--lengths must be comma-separated numbers in 0...1000")))
        #expect(C2ConfigArguments.parse(with("--lengths", "600,x")) == .failure(.invalid("--lengths must be comma-separated numbers in 0...1000")))
        #expect(C2ConfigArguments.parse(["c2-config", "--apps"]) == .failure(.missing("--apps")))
    }
}
