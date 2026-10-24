# Draft 2 results: v1 vs v2 pattern sets

Sources: `out/palette_scores.md` (1425 palettes, 1349 chromatic, 5 sets × modes A/B, reserve_diag on; off as sensitivity),
`out/ladder.md`, `out/static_checks.md`, `out/renders/`. How to rerun: `harness/README.md` Job D, "Draft 2".
Sets: **landmark**, **hybrid** = draft 2; **landmark_v1**, **hybrid_v1** = draft 1, mapped exactly as before; **label** = control.
Unless stated otherwise, numbers are for mode A with reserve_diag on.

## What changed in the harness

- Tiers quiet / dim / loud / strong / popout as specified (`mapper.quiet_colour`, `dim_faded`, `spare_accent`). Only loud/strong use counts against capacity, and loud needs C ≥ 0.08.
- (a) For hue families, D2 now requires a different hue name, so reserve_diag reserves the whole error hue name. This applies to draft 2 only.
- (b) C6 = pair confusion + λ·Σ beacon·ink·loss. λ_disc = 0.00182 (λ_raw = 0.399) is the value at which dropping every draft-2 landmark family costs the same in beacon loss as in pair confusion.
- (c) Families are ranked by `keep`, with ascending rank dropped first. This is numerically the same direction as the v1 harness.
- (d) Salience = a·max(0,|Lc|−|Lc_fg|)/100 + b·C/0.15 + c·bold − d·max(0,|Lc_fg|−|Lc|)/100, with **a = d = 1, b = 0.5, c = 0.15**. The weights are set so the declared order holds with margin 0.075 (7.5 Lc) on an ideal palette with every tier at its target and loud at the corpus-median C of 0.128. The tightest constraint is loud > quiet, which needs b ≥ 0.462. S1 and C1 use this model for all five sets.
- (e) recoverability.py was rerun after the docstring → comment.doc move. comment.doc recall went from 0.71 to 0.77 (Python: 0.00 → 0.99), and macro.call from 0.75 to 0.90. Pair separabilities moved by ≤ 0.002.
- Draft-1 mappings reproduce: capacity, kept families, raw confusion and coloured ink are identical in every row. Mode-B ties used to be broken by hash-seed-dependent set order; they are now broken deterministically, which changes ≤ 2% of mode-B assignments.

## Numbers per hypothesis

| | landmark (v2) | hybrid (v2) | label | landmark_v1 | hybrid_v1 |
|---|---:|---:|---:|---:|---:|
| loud families required / median available | 4 / 4 | 4 / 4 | 8 / 5 | 6 / 5 | 8 / 5 |
| % palettes keeping every family (normal) | 68% | 68% | 5% | 33% | 5% |
| % keeping every family (deutan) | 0% | 0% | 0% | 1% | 0% |
| coloured ink (C2, v1 definition) | 0.093 | 0.238 | 0.624 | 0.481 | 0.624 |
| loud / quiet / dim ink | .093 / .154 / .241 | .093 / .306 / .241 | .624 / 0 / 0 | .481 / 0 / 0 | .624 / 0 / 0 |
| salience-weighted ink (C2 headline = budget) | **0.065** | 0.076 | 0.126 | 0.093 | 0.088 |
| C1 ρ (salience model), median / % ≤ −0.5 | **−0.45** / 40% | −0.44 / 27% | −0.20 / 8% | −0.38 / 12% | −0.38 / 24% |
| C1 ρ (tier rank) | −0.57 | −0.53 | −0.01 | −0.25 | −0.16 |
| disc. confusion normal / deutan | .00209 / .00218 | .00216 / .00301 | .00247 / .00260 | .00214 / .00217 | .00267 / .00276 |
| beacon loss | 0.034 | 0.042 | 0.156 | 0.086 | 0.173 |
| C6 total (disc., λ) | **0.00215** | 0.00223 | 0.00276 | 0.00230 | 0.00299 |
| beacon coverage | 0.86 | 0.91 | 0.66 | 0.71 | 0.71 |
| L1–L3 ≥ default | 75% | 75% | 42% | 47% | 45% |
| S1 (all adjacent tiers, margin .075) | 1% | 1% | 1% | 8% | 6% |

- **H1 / C1, C2.** Moving strings to quiet and comments to dim cuts coloured ink from 0.48 to 0.09; all palettes are now ≤ 35%. Salience-weighted ink falls from 0.093 to 0.065. Median C1 ρ improves from −0.38 to −0.45 under the same salience model (the draft-1 report gave −0.35 under the old model), and 40% of palettes reach ρ ≤ −0.5 (v1: 12%). The tier-rank ρ is −0.57, so the design meets C1. Rendered palettes miss it by a little, because loud accents sit about 19 Lc below fg (corpus median) and lose salience.
- **H8 (ladder).** With beacon loss included, one order is optimal at every level for all five sets. The landmark `keep` order (meta → exit → value → definition) is 7% above optimal at λ (v1 order: 20%). At λ/3 and λ the optimum drops **definition first**, because its fallback keeps bold. At 3λ it is meta → exit → definition → value. **Value should be kept longest at every λ.** Dropping it sends strings to dim, the comment tier, so string/comment (w = 3) loses its last channel. hybrid's YAML order is optimal at 3λ and within 0.01% at λ.
- **H9 revised.** 68% of chromatic palettes reach all 4 loud families (target 80%), 83% reach ≥ 3, and 3% reach ≥ 3 under deutan (target 60%). **H9 fails.** Turning reserve_diag off gives 80% in normal vision. Under deutan, if a lightness difference may also satisfy D2 (draft-1 rule), 58% reach ≥ 3 and 23% reach 4. For comparison, draft-1 landmark reached all 6 families in 33% (deutan 1%).
- **H10 (mode A vs B).** On draft 2 the modes are indistinguishable. C1 ρ is −0.448 vs −0.458; A has lower ρ in 56% of palettes. Discounted confusion is equal: A is lower in 1% and higher in 1%. C6 total is the same, and deutan disc. is .00218 vs .00223. Habit fit is 0.19 for A vs 0.70 for B. Mode A gives up all cross-theme consistency for nothing measurable, so for draft 2 the evidence favours B. On v1, A still wins on ρ in 71% of palettes.
- **H11 / C9.** Draft-2 landmark has 0 single-channel w ≥ 2 pairs (v1: 4) and the same 3 pairs with no channel (variable.use/field, function.call/type.use, variable.use/parameter). comment/default and string/comment now also differ in lightness, and string/default in chroma. Removing weight or slant costs nothing. Removing lightness adds 1 pair (+0.0000 disc.; v1 +0.00006). Removing hue confuses 205 pairs (disc. 0.00265; v1 187, 0.00260).
- **H12 (landmark vs label).** Landmark has lower C6 total in 92% of palettes, lower discounted confusion in 68%, lower deutan confusion in 78%, lower salience-weighted ink in 84% and lower coloured ink in 94%. It keeps all its families in 65% of palettes vs 5% for label, and beacon coverage is 0.86 vs 0.66. Against landmark_v1, it has lower C6 in 58% (lower disc. confusion in 54%, higher in 15%), and keeps every family in 65% vs 31%. Hybrid costs more than landmark on every measure except beacon coverage (0.91), and its deutan confusion is higher (.00301 vs .00218) because the two quiet tints merge under deutan.
- **λ sensitivity.** Beacon loss is 3% (landmark) to 11% (hybrid_v1) of mean C6 at λ. The set ranking landmark < hybrid < landmark_v1 < label < hybrid_v1 is the same at λ/3, λ and 3λ.
- **Quiet tier.** A passing quiet colour exists for value in 100% of kept cases (hybrid A: 99%) and for definition in 100%. The median quiet C is 0.035. Dim passes its floor and the 10-below-fg rule in 95% of palettes. Faded is D1-distinct from dim in 96%. Popout finds a spare accent in 65%.

## Render check (out/renders/grid_python.html, screenshot reviewed)

Bold definitions stand out clearly. Comments and docstrings are dim but legible on normal palettes. Quiet strings are calm but only faintly tinted, because the search returns the most fg-like colour that passes, at C ≈ 0.035 (see problem 4). On base16/tokyo-night-terminal-storm, fg itself is dim, so dim lands at Lc 19.9 and faded at 15.2. The mapper records this, but the result is muddy. To fit six columns in 2900 px, the grid font was reduced to 10 px. No mapping bugs were found.

## Remaining spec problems

1. **Name-only D2 under CVD is structurally unreachable.** Simulated deutan colours fall into about two or three hue names (blue, yellow/brown). So with fix (a), deutan capacity is ≤ 3 almost everywhere (3% ≥ 3). The revised H9 deutan target needs either the ΔL route in the CVD check (58%) or credit for weight/lightness redundancy.
2. **H9 normal misses: 68% vs 80%.** Reserving the whole red hue name accounts for 12 points (80% with reserve off). The C ≥ 0.08 loud floor removes muted palettes; Tomorrow Night drops to capacity 2.
3. **S1 almost never holds (1%).** Each adjacent pair fails for a different reason:
   - default < quiet holds in 41%. The most-fg-like quiet sits just past D1 floor, so on palettes with a tinted fg, or with quiet darker than a very bright fg, the 7.5-Lc margin is gone. A fix: give quiet its own salience floor, e.g. ΔC ≥ 0.02 over fg.
   - quiet < loud (34%) and loud < strong (24%). Loud accents sit about 19 Lc below fg, and strong must out-rank *other families'* loud accents. Mode A deliberately gives the most salient accent to the highest-need family (exit/meta, not definition). The declared tier order and the need ranking contradict each other.
   - strong < popout holds in 14%. Popout is fg bold in 35% of palettes, which is less salient than strong by definition, and a spare accent is not necessarily more chromatic.
4. **Quiet is too faint to be "visibly tinted".** D1 floor (p = .5) means half of viewers notice the tint. Consider D1 reliable vs fg, or a C target of about 0.05 rather than "most fg-like".
5. **The string fallback collides with comments.** `quiet_fallback: dim` puts strings on the comment tier whenever value is dropped (11% of palettes), which collapses the w = 3 string/comment pair. The ladder says value, not definition, should be kept longest.
6. **The `keep` order disagrees with the optimum.** Definition at keep 4 is the first family dropped by the optimum at λ ≤ 1, because bold carries it. Decide whether bold alone is an acceptable definition beacon.
7. **hybrid `definition` lacks `quiet_fallback`.** Read literally, `fallback: strong` would make every call and type use bold once definition is dropped. The harness sends quiet roles to quiet_fallback, else default. Make this explicit in the YAML.
8. **Dim on low-contrast fg.** If |Lc_fg| < 40, dim cannot be both ≥ 30 and ≥ 10 below fg (5% of palettes). This is an L1 problem the pattern cannot fix.
9. **The salience weights are assumed, not measured.** b = 0.5 means C 0.15 counts as 50 Lc. That value is forced by "loud at Lc 45 must out-rank quiet at fg lightness" and has not been validated. The S1 and C1 values depend on it.
10. **C6 is dominated by a fixed baseline.** About 0.002 of every set's discounted cost comes from default-vs-default pairs no pattern separates (variable.use/field, variable.use/parameter). Between-set differences are 5–40% of that. Beacon loss stays small (≤ 11%) even at 3λ, because beacons are rare and ink-weighted.
11. **The C2 v1 "coloured ink" definition (C ≥ 0.04) is ambiguous for quiet.** Quiet colours at C 0.03–0.04 count as grey. Use salience-weighted ink as the headline.
