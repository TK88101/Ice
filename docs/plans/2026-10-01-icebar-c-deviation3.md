# Route C pre-registration, deviation 3 (draft): ambiguous chevron slivers; cut-glyph identity

2026-10-01 · branch `wip/icebar-c` · **approved by the owner 2026-10-01, in force** (pre-registration section 9, deviation 3) ·
amends `2026-09-30-icebar-c-prereg.md` (sha256 `bb10b671…`, v3 + deviations 1, 2)
section 5 (`«` (b)) and the instrument plan's T12.

## Why (MEASURED, development corpus only)

Deviation 2 C6 allows the new oracle to run on a development corpus (salt
`dev`) before corpus 2 exists. Run `20260930-113108-icebar-dev`: 5749 items,
7 not meeting their expectation (freeze 1 under the old rules: 2144).

| items | what happened |
|---|---|
| S5-{target,eff,ess}-under-1x | glyph 2 pt under the capsule (4 <= n < all of P); the oracle identifies **the same glyph** `full` 1 px left (x 1370.5 vs 1371.5), all its P visible there and >= 90 % hit. T12 had encoded the cut glyph's identity as `none`, which deviation 2 C6 does not require |
| S2-hidden4-left25-{4 colours}-2x | the K1 chevron template matches `partial` at x 1537 (box cut by the notch's left edge; visible P 20, hits 18, false 13/138) on the visible sliver of the N glyph, where hidden4's own template also sights it. `«` (b) reports present; truth absent. Deviation 2 C1 made helper-template partial/edge anonymous but left `«` (b) as registered |

## Changes

**D3.1 (section 5, `«` (b))**: a chevron `full` match is `«`. A chevron
`partial` or `edge` match is `«` unless it shares at least one hit pixel with
a helper-template `partial`/`edge` sighting in the same capture; such an
ambiguous chevron match is instead an **unexplained sighting by definition**
(C1's explained-ink test never applies to it), so it counts as a member seen.
Fail-closed: a granted attempt with it is NO-GO exactly as with `«`; no chevron
can become "clean". S14 (a chevron alone, cut or under the capsule) keeps
`«` present by (b) provided no helper template sights it -- checked by a test
before corpus 2 is frozen. C5's live control is unchanged.

**D3.2 (instrument plan T12, cut-glyph identity)**: for a placed glyph with
4 <= n < all of P, the oracle meets its expectation if it identifies **that
same glyph** `full` within 2 pt, **or** some unexplained sighting overlaps its
visible columns. n = all of P still requires exact identity; no other helper
may be identified `full`. `seesMember` = yes whenever a member is placed with
n >= 4; a visible glyph with 4 <= n < all contributes "either".

## Tests before corpus 2 is frozen

- D3.2 disjunction: same glyph `full` within 2 pt passes; another helper's
  `full` fails; neither `full` nor a sighting fails.
- D3.1 counterexample: a chevron partial colliding with a helper sighting whose
  hits all lie on an identified helper's ink -> still an unexplained sighting,
  attempt sees a member.
- S14 regression on the development corpus: each S14 case yields `«` present
  (no helper-sighting collision).
- The oracle keeps the chevron's per-placement hit pixels (today it only asks
  whether any chevron placement exists).

## Review (Codex gpt-5.6-terra, thecure, 2026-10-01)

P1 (D3.2) judged right in substance, owner ratification required because it
changes T12 after a development observation. P2 (D3.1) judged unsound as first
proposed (an ambiguous chevron could be "explained" away) and fixed as written
above ("unexplained by definition"); with that, no further blocker to freezing
corpus 2 once the tests above exist.
