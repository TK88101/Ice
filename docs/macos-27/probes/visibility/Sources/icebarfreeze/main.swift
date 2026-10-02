// icebarfreeze (docs/plans/2026-10-03-icebar-c-runner.md, section 7, T11): the
// pre-S0 freeze manifest of the pre-registration's section 6.
//
//   icebarfreeze write --out <manifest.json>
//       hashes every source the manifest freezes (section 6's list, IceBarClaim,
//       and everything that runs in a sitting), every glyph rendering and the
//       K1 chevron, and binds corpus 3: its freeze.json and check.json, every
//       PNG, every K input, and the equality of the frozen sources, renderings
//       and chevron with what corpus 3 recorded. Refuses a dirty tree and any
//       mismatch; writes nothing then.
//   icebarfreeze verify --manifest <manifest.json>
//       every source hash still equal (stage-icebar.sh runs it before building).
import Foundation
import IceBarCorpus
import IceBarOracle
import VZGlyphs

let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let preregistration = "docs/plans/2026-09-30-icebar-c-prereg.md"
let preregistrationBefore = "e693654c39f61313ce37fb36a547b3cf9a30083136960ea2cbdbcb39e63eb7e3"
let corpus3Run = "20260930-123540-icebar-corpus3"
let corpus3Freeze = "f8a64fbc81dd327897d54b0187e14e6a9af0fbc6dd960406a6bfb7994271853d"
let corpus3Check = "1844ac22b38a002ac26f4528af9a60b95a21cd3db3f483bdcc6887c1763c7c09"
/// Section 6's list (glyphs, renderer, generator, oracle) and IceBarClaim (the owner's addition).
let section6Dirs = ["Sources/VZGlyphs", "Sources/IceBarCorpus", "Sources/IceBarOracle", "Sources/IceBarClaim"]
/// Beyond section 6, fail-closed (Codex r1): everything that runs in a sitting.
let runnerDirs = ["Sources/IceBarRunCore", "Sources/IceBarStage", "Sources/vizprobe", "Sources/vzhelper", "Sources/C1Core", "Sources/C2Core"]
let runnerFiles = ["Package.swift", "build.sh", "stage-icebar.sh", "run-icebar.sh", "../../../plans/checks/check-a3a4.sh"]

struct PreS0Manifest: Codable {
    /// The same fields `FreezeManifest.Rendering` records (its init is internal to IceBarCorpus).
    struct Rendering: Codable, Equatable {
        let glyph: String
        let scale: Int
        let alphaSHA256: String
        let colouredRGBSHA256: String
    }

    struct KCheck: Codable {
        let id: String
        let file: String
        let sha256: String
        let matchesRecordedAndPreregistered: Bool
    }

    struct Corpus3: Codable {
        let run: String
        let freezeSHA256: String
        let checkSHA256: String
        let preregistrationAtFreeze: String
        let items: Int
        let pngsVerified: Int
        let sourcesMatchFreeze: Bool
        let renderingsMatchFreeze: Bool
        let chevronMatchesFreeze: Bool
        let kInputs: [KCheck]
    }

    let gitRevision: String
    let preregistrationSHA256Before: String
    /// Repository-relative path -> sha256.
    let sources: [String: String]
    let renderings: [Rendering]
    let chevronAlphaSHA256: String
    let corpus3: Corpus3
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("icebarfreeze: \(message)\n".utf8))
    exit(code)
}

func git(_ arguments: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", packageDir.path] + arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    do { try process.run() } catch { fail("git: \(error)") }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fail("git \(arguments.joined(separator: " ")) exited \(process.terminationStatus)") }
    return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

let repoRoot = URL(fileURLWithPath: git(["rev-parse", "--show-toplevel"])).standardizedFileURL

func sha256(_ url: URL) -> String {
    guard let data = try? Data(contentsOf: url) else { fail("cannot read \(url.path)") }
    return Digest.sha256(data)
}

func relative(_ url: URL) -> String {
    url.standardizedFileURL.path.replacingOccurrences(of: repoRoot.path + "/", with: "")
}

/// Every `.swift` file of the directories and every listed file, by repository-relative path.
func sourceHashes() -> [String: String] {
    var hashes = [String: String]()
    for dir in section6Dirs + runnerDirs {
        let base = packageDir.appendingPathComponent(dir)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: base.path), !files.isEmpty else { fail("no sources in \(dir)") }
        for file in files where file.hasSuffix(".swift") {
            let url = base.appendingPathComponent(file)
            hashes[relative(url)] = sha256(url)
        }
    }
    for file in runnerFiles {
        let url = packageDir.appendingPathComponent(file)
        hashes[relative(url)] = sha256(url)
    }
    return hashes
}

func argument(_ name: String) -> String {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { fail("missing \(name)", code: 2) }
    return args[i + 1]
}

func write() throws {
    let dirty = git(["status", "--porcelain", "--", ".", repoRoot.appendingPathComponent(preregistration).path,
                     repoRoot.appendingPathComponent("docs/plans/checks").path])
    guard dirty.isEmpty else { fail("uncommitted changes:\n\(dirty)") }
    var problems = [String]()
    let current = sha256(repoRoot.appendingPathComponent(preregistration))
    if current != preregistrationBefore { problems.append("pre-registration is \(current), not \(preregistrationBefore)") }

    let corpusDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("IceReverse-evidence/\(corpus3Run)")
    let freezeURL = corpusDir.appendingPathComponent("freeze.json")
    if sha256(freezeURL) != corpus3Freeze { problems.append("corpus 3 freeze.json changed") }
    if sha256(corpusDir.appendingPathComponent("check.json")) != corpus3Check { problems.append("corpus 3 check.json changed") }
    let freeze = try JSONDecoder().decode(FreezeManifest.self, from: Data(contentsOf: freezeURL))
    if freeze.preregistrationSHA256 != preregistrationBefore { problems.append("corpus 3 was frozen under \(freeze.preregistrationSHA256)") }

    var verified = 0
    for record in freeze.items {
        let png = corpusDir.appendingPathComponent("items/\(record.spec.id).png")
        if let data = try? Data(contentsOf: png), Digest.sha256(data) == record.pngSHA256 { verified += 1 } else { problems.append("png \(record.spec.id)") }
    }
    let sources = sourceHashes()
    let frozenDirs = ["Sources/VZGlyphs", "Sources/IceBarCorpus", "Sources/IceBarOracle"]
    let prefix = relative(packageDir) + "/"
    let now = sources.filter { path, _ in frozenDirs.contains { path.hasPrefix(prefix + $0 + "/") } }
        .reduce(into: [String: String]()) { $0[String($1.key.dropFirst(prefix.count))] = $1.value }
    let recorded = freeze.sources.filter { path, _ in frozenDirs.contains { path.hasPrefix($0 + "/") } }
    let sourcesMatch = now == recorded
    if !sourcesMatch { problems.append("VZGlyphs / IceBarCorpus / IceBarOracle sources differ from corpus 3's") }

    let templates = try CorpusTemplates(kDirectory: KCaptures.directory)
    var renderings = [PreS0Manifest.Rendering]()
    for scale in CorpusGeometry.scales {
        for glyph in Glyph.allCases {
            let ordinary = try templates.coverage(glyph, scale: scale)
            let coloured = try templates.coverage(glyph, scale: scale, coloured: true)
            renderings.append(PreS0Manifest.Rendering(glyph: glyph.rawValue, scale: scale, alphaSHA256: Digest.sha256(ordinary.alpha),
                                                      colouredRGBSHA256: Digest.sha256(coloured.rgb ?? [])))
        }
    }
    let renderingsMatch = renderings == freeze.renderings.map {
        PreS0Manifest.Rendering(glyph: $0.glyph, scale: $0.scale, alphaSHA256: $0.alphaSHA256, colouredRGBSHA256: $0.colouredRGBSHA256)
    }
    if !renderingsMatch { problems.append("renderings differ from corpus 3's") }
    let chevron = Digest.sha256(templates.chevron.alpha)
    let chevronMatch = chevron == freeze.chevronTemplate.alphaSHA256
    if !chevronMatch { problems.append("chevron template differs from corpus 3's") }

    let kChecks = KCaptures.inputs.map { input -> PreS0Manifest.KCheck in
        let measured = sha256(KCaptures.directory.appendingPathComponent(input.file))
        let record = freeze.kInputs.first { $0.id == input.id }
        let matches = measured == input.sha256 && record?.measuredSHA256 == measured && record?.expectedSHA256 == input.sha256
        if !matches { problems.append("K input \(input.id) changed") }
        return .init(id: input.id, file: input.file, sha256: measured, matchesRecordedAndPreregistered: matches)
    }
    guard problems.isEmpty else { fail("not frozen:\n" + problems.prefix(40).joined(separator: "\n")) }

    let manifest = PreS0Manifest(
        gitRevision: git(["rev-parse", "HEAD"]), preregistrationSHA256Before: preregistrationBefore, sources: sources,
        renderings: renderings, chevronAlphaSHA256: chevron,
        corpus3: .init(run: corpus3Run, freezeSHA256: corpus3Freeze, checkSHA256: corpus3Check, preregistrationAtFreeze: freeze.preregistrationSHA256,
                       items: freeze.items.count, pngsVerified: verified, sourcesMatchFreeze: sourcesMatch,
                       renderingsMatchFreeze: renderingsMatch, chevronMatchesFreeze: chevronMatch, kInputs: kChecks)
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(manifest)
    let out = URL(fileURLWithPath: argument("--out"))
    try data.write(to: out)
    print("icebarfreeze: \(sources.count) sources, \(renderings.count) renderings, corpus 3 \(verified)/\(freeze.items.count) PNGs; \(out.path) sha256 \(Digest.sha256(data))")
}

func verify() throws {
    let manifest = try JSONDecoder().decode(PreS0Manifest.self, from: Data(contentsOf: URL(fileURLWithPath: argument("--manifest"))))
    let now = sourceHashes()
    let changed = Set(manifest.sources.keys).union(now.keys).filter { manifest.sources[$0] != now[$0] }.sorted()
    guard changed.isEmpty else { fail("sources differ from the pre-S0 manifest:\n" + changed.joined(separator: "\n")) }
    print("icebarfreeze: \(now.count) sources equal the pre-S0 manifest")
}

do {
    switch CommandLine.arguments.dropFirst().first {
    case "write": try write()
    case "verify": try verify()
    default: fail("usage: icebarfreeze write --out <manifest.json> | verify --manifest <manifest.json>", code: 2)
    }
} catch {
    fail("\(error)")
}
