# Route C pre-registration, second pre-S0 addendum (draft for review)

2026-10-03 · branch `wip/icebar-runner` · **approved by the owner 2026-10-03 and written to the pre-registration's section 9** (sha256 now `0780e997b7b5ed5eae6ea69f5df451413c99d48ec5e51a94c3e7617edb8e5420`); this file is the reviewed draft, kept as written. It
replaces the pre-S0 freeze manifest only. After review and the owner's approval it is
appended under section 9's ledger of `2026-09-30-icebar-c-prereg.md` (sha256 now
`a4e8b31b714b3acf2972fbfb3573f08ea41f9935ccaa25561606b6d6346fa572`), the pre-registration is
re-hashed, and the new sha256 is recorded in the claim plan section 8 row 5, route C
rule 6 and the runner plan section 9. Nothing here changes a rule, a threshold or an
expectation.

## Second pre-S0 freeze addendum (to be appended to section 9)

**Why.** Deviation 5 D5.2 (approved; `2026-10-03-icebar-c-deviation5.md`) has the runner
set the desktop picture between S-adv variants and restore it before S1. Its
implementation changes runner sources that the first pre-S0 manifest froze, so
`icebarfreeze verify` refuses to stage (as designed) until a manifest of the new
sources is registered.

**Manifest.** `docs/plans/2026-10-03-icebar-c-pre-s0-manifest-v2.json`, sha256
`18187e2c9f217497ad4e12ccf10a9c04747fa84a7ff5d3ba555149580b8955c5`, written by
`icebarfreeze write` at git revision `d8e05a5e4ec8cd6d3d90e1e198281a492459876c` under
pre-registration `a4e8b31b714b3acf2972fbfb3573f08ea41f9935ccaa25561606b6d6346fa572`. It
**replaces** the first manifest (`2026-10-03-icebar-c-pre-s0-manifest.json`, sha256
`41b91f4db1622ca97fb7c3a9c6dd8c298e00c50c55868d04c13bcc2f075e5db5`, revision `1d671d3`,
kept in the repository unchanged) as the one `stage-icebar.sh` verifies against. Same
173 source files, same tool, same fields.

**What differs from the first manifest.** Exactly seven source hashes, listed below; the
recorded git revision and pre-registration hash, as stated above; every other field is
equal. Paths under `docs/macos-27/probes/visibility/`:

| file | first manifest | this manifest | change |
|---|---|---|---|
| `Sources/IceBarRunCore/Sitting.swift` | `64e2a86158869a02b252c3fa26536f7f0d950e67b8e7a8fa3f5bdb8b9f0b91bd` | `8ae60edca695ef3358ba765f24b3fd1437ce611a8ad3af841e0639a721cf43f0` | the K2 gate (`beforeSAdv`) removed; `SAdvStep.variant` |
| `Sources/IceBarRunCore/SittingDriver.swift` | `ca1ed1c95fc053ac484e6310557913b653a5b0a3b8609b4e2a31c553f3583d0d` | `2e83bd7450179f63182a5728e7d575d708a34fca0706946ec22d4c318fbcdf85` | D5.2's sequencing: the staged picture before each S-adv appearance, the original before S1 and at the sitting's end; a failed change interrupts |
| `Sources/vizprobe/IceBarLive.swift` | `2603ec593a300e8481f782bc98f813bc7fa588f2f105388650d32e24e6d7f819` | `ef1779024eefcbd39ec0f0fa6b22aaa4ee214baf33f817e81299858fed73c6c6` | `LiveDesktopPicture`: the two staged solid images (grey 30, grey 225), path, sha256 and time recorded, the restore |
| `Sources/vizprobe/IceBarRun.swift` | `6377d6f78aad03a427ccdfe406147fb25105f4f7a8728ff0e72a44abba564ee5` | `08f2330b8870981da29559563c477ed38af4591c63c3ddc950b4dac3edd91747` | the sitting performs the driver's picture requests; an unreadable original is refused before S0; SIGINT/SIGTERM/SIGHUP end the sitting on the path that restores |
| `Sources/vizprobe/C2Run.swift` | `9326dfe1a50e1207d26411fd2302a25f97d7009764a6ee815d68c6526ebb0765` | `9236958371cc204ad753c88f11188653e45a18f5fcff8135412527a9ff53454a` | `runChild(stop:)`: the step in progress is terminated on such a signal (default: never; C2's own use unchanged) |
| `Sources/icebarfreeze/main.swift` | `70550b633d2702ea401f7f90cde838afe92583701f6cfec6d0e59f8c731990ba` | `e3a40e38be71963b1fdb92f931d2567ac1db89052804ba19247f373dbe9a055b` | the freeze tool names two pre-registration hashes: the one corpus 3 was frozen under (`e693654c…`) and the current one (`a4e8b31b…`) |
| `stage-icebar.sh` | `327587fbc3c4c771ee74235397322b9b844f75d06b0a5bbd39984c4622194906` | `fb68b84475730b8b34fae6f1f8dfe8100ceb2de3a97f1afda94d1c5535ba9051` | verifies against this manifest's file |

D5.2's implementation is the whole change to what the manifest freezes: the first five
rows are it, the last two are what registering it requires (the tool that writes the
manifest, the script that reads it). The same commits also change three test files,
which the manifest does not freeze (`Tests/IceBarRunCoreTests/SequencerTests.swift`,
`SittingDriverTests.swift`: the driver's picture sequencing and its failure paths;
`Tests/IceBarStageTests/CallSiteTests.swift`: every step warms up before any baseline). The other 166 source hashes equal the first manifest's, among them every file of
section 6's list and `IceBarClaim` (`VZGlyphs`, `IceBarCorpus`, `IceBarOracle`,
`IceBarClaim`), `IceBarStage`, `vzhelper`, `C1Core`, `C1Live`, `C1Stage`, `C2Core`, the
local packages' sources, `Package.swift`, `build.sh`, `run-icebar.sh` and
`check-a3a4.sh`. No rule, threshold, cadence, oracle, claim or accounting code changes.

**Renderings, chevron and corpus 3: equal to the first manifest's.** The 38 glyph
renderings (canonical JSON sha256
`871fc1df2a18b49296b56caef36e0d5e41d58dd2194563d51940b28d0d4eb7e5`), the K1 chevron
template's alpha (`f34511e3e602f5151ffbd378d0eca4dec6dd1515db4438ef99dd1a7cfe352209`) and
the whole corpus 3 record (run `20260930-123540-icebar-corpus3`: `freeze.json`
`f8a64fbc81dd327897d54b0187e14e6a9af0fbc6dd960406a6bfb7994271853d`, `check.json`
`1844ac22b38a002ac26f4528af9a60b95a21cd3db3f483bdcc6887c1763c7c09`, frozen under
`e693654c39f61313ce37fb36a547b3cf9a30083136960ea2cbdbcb39e63eb7e3`; 5749/5749 item PNGs
re-hashed equal and listed one by one; sources, renderings and chevron equal to its
freeze; K1-K4 equal to their recorded and pre-registered sha256) were recomputed at this
write and are field-for-field equal to the first manifest's.

**Corpus 3 is still not re-checked.** As the first addendum registers: its single check
(0 of 5749) ran under `e693654c…` and is the result; a re-run would be a second
experiment; `vzcorpus check` refuses corpus 3 after a re-hash by design and is not run.
None of the seven changed files is a corpus-3 source, a rendering path, the oracle or
the claim, and the equalities above are the ones corpus 3 stands on.

**Limit of D5.2's restore, recorded with it.** The original desktop picture is restored
before S1 and whenever the sitting ends on its normal path (a failed or safety-stopped
step, a console loss, a failed picture change, SIGINT/SIGTERM/SIGHUP to `icebar-run`).
SIGKILL, a crash or a power loss cannot restore it; the sitting's first log record
holds the original's path and sha256.
