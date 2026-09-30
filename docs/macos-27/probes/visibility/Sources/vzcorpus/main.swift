// vzcorpus (docs/plans/2026-10-01-icebar-c-instrument.md, section 4, T6/T7):
//
//   vzcorpus freeze --out <dir> --salt <salt>
//                                      generate every corpus item, write its PNG
//                                      and freeze.json; no oracle matching
//   vzcorpus dev --salt dev            development run (deviation 2 C6): generate
//                                      in memory and check; never corpus 2's salt
//   vzcorpus check --freeze <file>     verify every frozen hash, then run the
//                                      oracle on each item; writes check.json
//
// Output directories must be outside the repository (corpus images live
// only under ~/IceReverse-evidence/<run id>/). K inputs: $ICEBAR_K_DIR or
// the pre-registered run's captures directory.
import Foundation
import IceBarCorpus
import IceBarOracle
import VZGlyphs

let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let preregistrationPath = "docs/plans/2026-09-30-icebar-c-prereg.md"
/// The sources whose hashes `check` requires unchanged; the oracle's own and
/// this tool's are recorded for provenance (oracle bug fixes are logged).
let frozenSourceDirs = ["Sources/VZGlyphs", "Sources/IceBarCorpus"]
let recordedSourceDirs = frozenSourceDirs + ["Sources/IceBarOracle", "Sources/vzcorpus"]

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("vzcorpus: \(message)\n".utf8))
    exit(code)
}

func git(_ arguments: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", packageDir.path] + arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    do { try process.run() } catch { fail("git \(arguments.joined(separator: " ")): \(error)") }
    process.waitUntilExit()
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else { fail("git \(arguments.joined(separator: " ")) exited \(process.terminationStatus)") }
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
}

let repoRoot = URL(fileURLWithPath: git(["rev-parse", "--show-toplevel"]))

func outsideRepository(_ path: String) -> URL {
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.resolvingSymlinksInPath()
    if url.path == repoRoot.path || url.path.hasPrefix(repoRoot.path + "/") {
        fail("\(url.path) is inside the repository; corpus output goes under ~/IceReverse-evidence/<run id>/", code: 2)
    }
    return url
}

func sha256(ofFile url: URL) -> String {
    guard let data = try? Data(contentsOf: url) else { fail("cannot read \(url.path)") }
    return Digest.sha256(data)
}

func sourceHashes(_ dirs: [String]) -> [String: String] {
    var hashes = [String: String]()
    for dir in dirs {
        let base = packageDir.appendingPathComponent(dir)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
        for file in files where file.hasSuffix(".swift") {
            hashes["\(dir)/\(file)"] = sha256(ofFile: base.appendingPathComponent(file))
        }
    }
    return hashes
}

func argument(_ name: String) -> String {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { fail("missing \(name)", code: 2) }
    return args[i + 1]
}

func freeze() throws {
    let out = outsideRepository(argument("--out"))
    let dirty = git(["status", "--porcelain", "--", ".", repoRoot.appendingPathComponent(preregistrationPath).path])
    guard dirty.isEmpty else { fail("uncommitted changes under the package or the pre-registration:\n\(dirty)") }
    let itemsDir = out.appendingPathComponent("items")
    try FileManager.default.createDirectory(at: itemsDir, withIntermediateDirectories: true)
    guard (try FileManager.default.contentsOfDirectory(atPath: itemsDir.path)).isEmpty else { fail("\(itemsDir.path) is not empty") }

    let templates = try CorpusTemplates(kDirectory: KCaptures.directory)
    let (items, unreachable) = try CorpusRecipe.specs(templates: templates, salt: argument("--salt"))
    let manifest = try FreezeBuilder.manifest(
        runId: out.lastPathComponent, gitRevision: git(["rev-parse", "HEAD"]),
        preregistrationSHA256: sha256(ofFile: repoRoot.appendingPathComponent(preregistrationPath)),
        sources: sourceHashes(recordedSourceDirs), items: items, templates: templates, unreachable: unreachable
    ) { item in
        let png = try PNGIO.encode(item.image)
        try png.write(to: itemsDir.appendingPathComponent("\(item.spec.id).png"))
        return Digest.sha256(png)
    }
    for k in manifest.kInputs where k.measuredSHA256 != k.expectedSHA256 { fail("\(k.id) sha256 differs from the pre-registration") }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let json = try encoder.encode(manifest)
    try json.write(to: out.appendingPathComponent("freeze.json"))
    let rows = Dictionary(grouping: items, by: \.row).mapValues(\.count).sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    print("vzcorpus freeze: \(items.count) items (\(rows.map { "\($0.key) \($0.value)" }.joined(separator: ", "))), \(unreachable.count) S13 combinations unreachable")
    print("vzcorpus freeze: \(out.appendingPathComponent("freeze.json").path) sha256 \(Digest.sha256(json))")
}

/// Everything the freeze fixed must be unchanged before the oracle runs.
func verify(_ manifest: FreezeManifest, dir: URL, templates: CorpusTemplates) throws -> [ItemSpec] {
    var problems = [String]()
    let preregistration = sha256(ofFile: repoRoot.appendingPathComponent(preregistrationPath))
    if preregistration != manifest.preregistrationSHA256 {
        problems.append("pre-registration changed since the freeze: \(manifest.preregistrationSHA256) -> \(preregistration)")
    }
    let current = sourceHashes(frozenSourceDirs)
    for (path, hash) in manifest.sources where frozenSourceDirs.contains(where: { path.hasPrefix($0 + "/") }) && current[path] != hash {
        problems.append("source changed: \(path)")
    }
    for path in current.keys where manifest.sources[path] == nil { problems.append("source added: \(path)") }
    for r in manifest.renderings {
        let glyph = Glyph(rawValue: r.glyph)!
        if Digest.sha256(try templates.coverage(glyph, scale: r.scale).alpha) != r.alphaSHA256 { problems.append("rendering changed: \(r.glyph) \(r.scale)x") }
    }
    if Digest.sha256(templates.chevron.alpha) != manifest.chevronTemplate.alphaSHA256 { problems.append("chevron template changed") }
    let (specs, _) = try CorpusRecipe.specs(templates: templates, salt: manifest.items.first?.spec.seedSalt ?? "")
    if specs != manifest.items.map(\.spec) { problems.append("recipe changed") }
    for record in manifest.items {
        let png = dir.appendingPathComponent("items/\(record.spec.id).png")
        guard let data = try? Data(contentsOf: png) else { problems.append("missing \(png.lastPathComponent)"); continue }
        if Digest.sha256(data) != record.pngSHA256 { problems.append("png changed: \(record.spec.id)") }
    }
    guard problems.isEmpty else { fail("freeze does not verify:\n" + problems.prefix(40).joined(separator: "\n")) }
    return manifest.items.map(\.spec)
}

func check() throws {
    let freezeFile = outsideRepository(argument("--freeze"))
    let dir = freezeFile.deletingLastPathComponent()
    let manifest = try JSONDecoder().decode(FreezeManifest.self, from: Data(contentsOf: freezeFile))
    let templates = try CorpusTemplates(kDirectory: KCaptures.directory)
    let specs = try verify(manifest, dir: dir, templates: templates)
    let raw = Dictionary(uniqueKeysWithValues: manifest.items.map { ($0.spec.id, $0.rawSHA256) })
    try run(specs, templates: templates, raw: raw, out: dir)
}

/// Development runs only (deviation 2 C6): the frozen corpus's salt is refused.
func dev() throws {
    let salt = argument("--salt")
    guard !CorpusSalt.isFrozen(salt) else { fail("\(salt) is a frozen corpus's salt; it is only checked through its freeze", code: 2) }
    let out = outsideRepository(argument("--out"))
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let templates = try CorpusTemplates(kDirectory: KCaptures.directory)
    let specs = try CorpusRecipe.specs(templates: templates, salt: salt).items
    try run(specs, templates: templates, raw: nil, out: out)
}

func run(_ specs: [ItemSpec], templates: CorpusTemplates, raw: [String: String]?, out dir: URL) throws {
    let lock = NSLock()
    var results = [String: [String]]()
    DispatchQueue.concurrentPerform(iterations: specs.count) { i in
        let spec = specs[i]
        let problems: [String]
        do {
            let item = try CorpusRenderer.render(spec, templates: templates)
            if let raw, Digest.sha256(item.image.bytes) != raw[spec.id] {
                problems = ["regenerated pixels differ from the freeze"]
            } else {
                problems = try CorpusCheck.problems(item, templates: templates)
            }
        } catch {
            problems = ["error: \(error)"]
        }
        lock.lock()
        results[spec.id] = problems
        lock.unlock()
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(results).write(to: dir.appendingPathComponent("check.json"))
    let failed = specs.filter { !(results[$0.id] ?? ["missing"]).isEmpty }
    for spec in failed.prefix(200) { print("MISLABEL \(spec.id): \((results[spec.id] ?? []).joined(separator: "; "))") }
    let byRow = Dictionary(grouping: failed, by: \.row).mapValues(\.count)
    print("vzcorpus check: \(specs.count) items, \(failed.count) mislabels \(byRow.sorted { $0.key < $1.key })")
    exit(failed.isEmpty ? 0 : 1)
}

do {
    switch CommandLine.arguments.dropFirst().first {
    case "freeze": try freeze()
    case "check": try check()
    case "dev": try dev()
    default: fail("usage: vzcorpus freeze --out <dir> --salt <salt> | check --freeze <freeze.json> | dev --salt <salt> --out <dir>", code: 2)
    }
} catch {
    fail("\(error)")
}
