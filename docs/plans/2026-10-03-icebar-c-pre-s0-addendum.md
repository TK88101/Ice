# Route C pre-registration, pre-S0 addendum (draft for review)

2026-10-03 · branch `wip/icebar-runner` · **approved by the owner 2026-10-03 and written to the pre-registration's section 9** (sha256 now `a4e8b31b714b3acf2972fbfb3573f08ea41f9935ccaa25561606b6d6346fa572`); this file is the reviewed draft, kept as written. Section 6
of `2026-09-30-icebar-c-prereg.md` schedules this addendum ("appended to section 9 as an
addendum ... reviewed, and this document re-hashed"). After review and the owner's
approval it is appended under section 9's ledger, the pre-registration is re-hashed,
and the new sha256 is recorded in the claim plan section 8 row 5, route C rule 6 and
the runner plan section 9. Nothing here changes a rule, a threshold or an expectation.

## Pre-S0 freeze addendum (to be appended to section 9)

**Manifest.** `docs/plans/2026-10-03-icebar-c-pre-s0-manifest.json`, sha256
`41b91f4db1622ca97fb7c3a9c6dd8c298e00c50c55868d04c13bcc2f075e5db5`, written by `icebarfreeze write` at git revision `1d671d324ad206e19866d73ac8a8c6b8ad52f4ca` under
pre-registration `e693654c39f61313ce37fb36a547b3cf9a30083136960ea2cbdbcb39e63eb7e3`. It holds the sha256 of
173 source files: section 6's list (the glyphs' source `VZGlyphs`, the
generator `IceBarCorpus`, the oracle `IceBarOracle`) and `IceBarClaim`, and, fail-closed,
everything that runs in a sitting (`IceBarRunCore`, `IceBarStage`, `vizprobe`, `vzhelper`,
`C1Core`, `C1Live`, `C1Stage`, `C2Core`, `icebarfreeze`, the local packages' sources,
`Package.swift`, `build.sh`, `stage-icebar.sh`, `run-icebar.sh`, `check-a3a4.sh`);
`stage-icebar.sh` refuses to stage unless every one still matches (`icebarfreeze verify`).

**Section 6's sources and `IceBarClaim`** (paths under `docs/macos-27/probes/visibility/`):

| file | sha256 |
|---|---|
| `Sources/IceBarClaim/Claim.swift` | `3a9a54bb68e290979c3a370fd37f7a29a69da6c1977072aa25c9b114ea372314` |
| `Sources/IceBarClaim/ClaimParameters.swift` | `d911c13c7552048454cbcbe2890d35a7be10cc8f22f169e94ad9b0f7d7d94780` |
| `Sources/IceBarClaim/ClaimRegion.swift` | `8f7659a8c5ac86cb001fd82bc739c80b0fb9b613f4188d35bb84e1a5498beaf2` |
| `Sources/IceBarClaim/ContrastGate.swift` | `ec7a3c9286e5c14408cc36c455786c0946c8a56756d56103d4dee9ec23f0b834` |
| `Sources/IceBarClaim/HiddenBaseline.swift` | `b9bb8c605fd485c9f9b58cf401dc8101e0ef94a5b2fddcfc4e0df299ef964cfa` |
| `Sources/IceBarClaim/PixelKit.swift` | `89a8673518119f8dd780d7f4f9b1bd5c40351ac390eea7e7ed4ef70514c1afd2` |
| `Sources/IceBarClaim/RegionClear.swift` | `980ed1f6c61947a93b505523fc1fc6ad964ae2c7bca43c7a0c94794120a7d000` |
| `Sources/IceBarCorpus/CorpusGeometry.swift` | `25830bf9f0604ecc7511a3b4b39d0de2ec17684773ee1deb23fa510a07968cac` |
| `Sources/IceBarCorpus/CorpusRecipe.swift` | `6e0a3007009e26b1deec25ac717160f146b448da5b20072df640fa2ad662e109` |
| `Sources/IceBarCorpus/CorpusRenderer.swift` | `3a7c03c111ebee428b60d7696818044b41e98885d3b34e5424c1c3f3f3ddf709` |
| `Sources/IceBarCorpus/CorpusRows.swift` | `9b98970210a9aa2fc79af7e5bc774d5fc98f9416e880228aac9f75f1407f2dc0` |
| `Sources/IceBarCorpus/CorpusSpec.swift` | `d4108d5595b8bcd56965f8ec98dee23c98ffa07be8eb85ed75a9c251281e4874` |
| `Sources/IceBarCorpus/CorpusTemplates.swift` | `54902bf9472b4d71b38310caeb662b39727d49db6a375743de2226ade20733b0` |
| `Sources/IceBarCorpus/Freeze.swift` | `269a343a368b141ab1453eb53c3e2da3ba2d9a1c95b651857a56c4ea61030595` |
| `Sources/IceBarCorpus/S13Rows.swift` | `2b3bad3ff8235748e328922ac7fd93d4e73f28803bf12ed679f81c52a9b61618` |
| `Sources/IceBarCorpus/Support.swift` | `b1caa48ed9cf906cb2918c79319a8c0bfa5084dd578f501dffd266ffd050608b` |
| `Sources/IceBarOracle/Chevron.swift` | `92b0dc43decdd782af114fa759cc582b0b6445a49b2de46cd3e6749856f09993` |
| `Sources/IceBarOracle/Controls.swift` | `0efecfdeb2238df28db4a484004849faf9ca383d64549d65fe6c009dd0e62923` |
| `Sources/IceBarOracle/Kernels.swift` | `b8ad973911facff9dc28e1c62e8cb46a128f9519b06897f08688f7d7179a882e` |
| `Sources/IceBarOracle/Oracle.swift` | `e099da52d32bb17968a93c5b7855f60ec241a89545abd1dac178eaf753b9c8cf` |
| `Sources/IceBarOracle/OracleGeometry.swift` | `b39b44698d6f0314d891d638f63148712f662272a45253db786f4946896ca547` |
| `Sources/IceBarOracle/OracleTypes.swift` | `b26a10c3e8206e70931f976b2f1516b968e26c180b70dc18fed203a41ddd5f0c` |
| `Sources/IceBarOracle/Searcher.swift` | `04b881d6053d313b28a1d80cc7d2207b928d2b429afa29a1667b9f34fc7e058a` |
| `Sources/VZGlyphs/GlyphCheck.swift` | `86f3a52fc228a244ecc8a85910b00749096229d900de88add60a76fa0ddc61b7` |
| `Sources/VZGlyphs/GlyphRenderer.swift` | `6ce3f91ffc57610a5980c3cf662a95fe9807295f443b88d91b8c52370986a77a` |
| `Sources/VZGlyphs/Glyphs.swift` | `96e6ebaafa6fdf55f8836f619c9561d6c6085e54c2913423776e36e67386652f` |

**Renderings and chevron.** Each glyph's 1x/2x ordinary alpha and coloured RGB rendering
(38 records, `GlyphRenderer`; canonical JSON of the list, sha256 `871fc1df2a18b49296b56caef36e0d5e41d58dd2194563d51940b28d0d4eb7e5`) and the K1
chevron template's alpha (`f34511e3e602f5151ffbd378d0eca4dec6dd1515db4438ef99dd1a7cfe352209`), each equal to corpus 3's record.

**Corpus 3** (run `20260930-123540-icebar-corpus3`): `freeze.json` `f8a64fbc81dd327897d54b0187e14e6a9af0fbc6dd960406a6bfb7994271853d`, `check.json`
`1844ac22b38a002ac26f4528af9a60b95a21cd3db3f483bdcc6887c1763c7c09`, frozen under `e693654c39f61313ce37fb36a547b3cf9a30083136960ea2cbdbcb39e63eb7e3`; 5749/5749
item PNGs re-hashed equal to `freeze.json` and **listed one by one** in the
manifest (`corpus3.pngs`, item id -> sha256: section 6's "every generated corpus image"); the `VZGlyphs`, `IceBarCorpus` and
`IceBarOracle` sources, every rendering and the chevron equal to what corpus 3 recorded;
K1-K4 (K3 included) equal to their recorded and pre-registered sha256.

**R15 (part 2, owner-approved; claim plan section 8 row 5).** U5's and U8's "accepted"
cases mean the named clause (rule 1 (b); the contrast gate's row clause) accepts; the
texture bound (deviation 2 C2) stays an added, independent refusal, so for those inputs
the whole baseline verdict is `.texture`; no threshold, expectation or refusal is loosened.

**Corpus 3 is not re-checked (claim plan section 8 row 6).** Its single check ran under
`e693654c39f61313ce37fb36a547b3cf9a30083136960ea2cbdbcb39e63eb7e3` (instrument plan section 8 row 12) and is the result
(deviation 2 C6, deviation 4 D4.2); a re-run would be a second experiment. After this
re-hash `vzcorpus check` refuses corpus 3 by design (`Sources/vzcorpus/main.swift:109-111`)
and is not run; corpus 3 stands on the equalities above, recorded before the re-hash.
