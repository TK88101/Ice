# Route C pre-registration, deviation 5: `«` (b) for the live control; appearance variants within one sitting

2026-10-03 · branch `wip/icebar-runner` · **approved by the owner 2026-10-03, in force** (pre-registration section 9, deviation 5) ·
amends `2026-09-30-icebar-c-prereg.md` (sha256 `e693654c…`, v3 + deviations 1-4):
deviation 2's C5 (the live (b) control) and section 1's E3.

Labels: MEASURED (file, test, run id) or INFERRED (reasoning).

## Why

- **F1, C5 cannot hold as written** (MEASURED, `Tests/IceBarStageTests/CallSiteTests.swift`
  `ChevronFrameTests`): section 5's edge rule passes the attempt's on-bar agent frames to
  the oracle, and their columns are never visible (instrument plan D6). A `«` that AX
  lists has its own 17.5 pt frame among them, so (b) cannot see it: the same capture
  reads `«` absent with its frame in the context and present without it. Deviation 2
  C5's live control ("every capture whose read shows `«` by (a) must also show it by
  (b)") can therefore never pass, and every sitting would stop before S1.
- **F2, E3 vs S-adv** (registered text): E3 keeps the desktop picture static for the
  whole sitting; route C's S-adv needs a dark and a light bar; O3 puts S0, S-adv and S1
  in one sitting; E5 says the variant is produced by the desktop picture and named by
  the baseline's median luma.

## Changes

**D5.1 (deviation 2 C5)**: for C5's live control only, (b) is evaluated with every
chevron-width AX frame left out of the oracle's agent frames -- the case (b) exists for,
a chevron AX does not list -- with the same oracle, templates and D3.1 rule. The
attempt's verdict ("oracle sees `«`" by (a) or (b)) keeps the registered context, so no
safety reading changes. C5's thresholds (>= 10 captures, >= 2 episodes, one miss stops
the sitting before S1) are unchanged.

**D5.2 (E3)**: E3 holds within each stage profile and each S-adv variant. Between S-adv
variants only, the runner sets the desktop picture to one of two staged solid images
(dark grey, light grey), records each image's path and sha256 and the time of the
change, then repeats the 24-capture warm-up and the settle before the next variant's
first sample. The variant is still named by E5's median luma (a step whose baseline
names another variant stays inconclusive, runner plan Q18). The original desktop
picture is restored before S1. No other stage changes the picture.

## Review (Codex gpt-5.6-terra, thecure, 2026-10-03)

D5.1 judged right: it narrows only C5's calibration control to the condition (b) was
registered to establish, and keeps the registered-context safety verdicts. D5.2 judged
right: an explicit deviation bounding E3 to a profile or variant, with recorded and
hashed staged images, re-warm and settle after each switch, and restoration before S1.
Converged with the pre-S0 addendum review (runner plan section 9 row 11).
