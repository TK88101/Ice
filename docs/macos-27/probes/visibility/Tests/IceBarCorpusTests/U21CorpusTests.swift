// U21 (pre-registration section 7): every S and K item yields its expected
// label. Enabled only with ICEBAR_FREEZE=<freeze.json>: the corpus must be
// frozen before the oracle first runs on it (section 6; instrument plan T6).
// Run in release: `swift test -c release -Xswiftc -enable-testing`.
import Foundation
import IceBarCorpus
import IceBarOracle
import Testing

@Suite("U21 corpus")
struct U21CorpusTests {
    static let freezePath = ProcessInfo.processInfo.environment["ICEBAR_FREEZE"] ?? ""

    @Test("every frozen item regenerates byte for byte and is labelled as expected", .enabled(if: !freezePath.isEmpty))
    func corpus() throws {
        let manifest = try JSONDecoder().decode(FreezeManifest.self, from: Data(contentsOf: URL(fileURLWithPath: Self.freezePath)))
        let templates = try CorpusTemplates(kDirectory: KCaptures.directory)
        let salt = manifest.items.first?.spec.seedSalt ?? ""
        let specs = try CorpusRecipe.specs(templates: templates, salt: salt).items
        #expect(specs == manifest.items.map(\.spec), "the recipe changed since the freeze")

        let lock = NSLock()
        var failures = [String]()
        DispatchQueue.concurrentPerform(iterations: manifest.items.count) { i in
            let record = manifest.items[i]
            var problems: [String]
            do {
                let item = try CorpusRenderer.render(record.spec, templates: templates)
                problems = Digest.sha256(item.image.bytes) == record.rawSHA256 ? [] : ["pixels differ from the freeze"]
                if problems.isEmpty {
                    problems = try CorpusCheck.problems(item, templates: templates)
                }
            } catch {
                problems = ["\(error)"]
            }
            guard !problems.isEmpty else { return }
            lock.lock()
            failures.append("\(record.spec.id): \(problems.joined(separator: "; "))")
            lock.unlock()
        }
        #expect(failures.isEmpty, "\(failures.count) mislabels:\n\(failures.sorted().prefix(50).joined(separator: "\n"))")
    }
}
