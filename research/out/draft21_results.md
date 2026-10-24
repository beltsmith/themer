# Draft 2.1 results

Sources: `out/palette_scores.md` (1425 palettes, 1349 chromatic; headline mode B, mode A alongside), `out/ladder.md`, `out/static_checks.md`,
`out/renders/`. Rerun: `harness/README.md`, Job D "Draft 2.1". Draft 2 numbers are from `out/draft2_results.md` (mode A unless noted).

## What changed in the harness

- `keep` order value 4 > definition 3 > exit 2 > meta 1 is read from the YAML (no code change). `quiet_fallback: {tier: quiet, family: any_kept, else: default}`:
  when value is dropped, or its own quiet colour fails, strings take the quiet tint of whichever kept family accent has the best D1 margin vs fg and dim (`theme.quiet_borrow`), else default. Never dim.
  Hybrid's definition `quiet_fallback: {tier: default}` is honoured.
- Quiet tier: C in [0.05, 0.09], |Lc| within 15 of fg, D1 at the reliable level (p = .8) vs fg, vs dim and vs any other quiet colour in use; most fg-like passing colour. Failures are recorded (`theme.quiet[f].ok`).
- Dim: lc [45, 20], below_default 10 wins over the target. `fg_limited` = |Lc(fg)| < 50.
- CVD: for draft-2 sets, under deutan/protan/tritan two loud families, and a family vs fg, are distinct if D1 passes at p = .8 (no name rule, lightness counts). The assignment's deutan margin uses the same rule. The confusion cost (C6 deutan) still uses the old name-D2 rule, so capacity and deutan confusion are not on one criterion (see problem 3).
- S1 = S1a (|Lc| faded < dim < default) and S1b (OKLCH C quiet < loud, margin 0.03). S1b is n/a for sets with no quiet tier, and when no quiet tint is drawn.
- Separable cost = confusion excluding the 23 role pairs that no set separates (same family, tier, weight, slant in all five sets at full capacity).
- λ_disc fell from 0.00182 to 0.00148 because the static model now sends dropped-value strings to a quiet tint instead of dim.

## Comparison (mode B headline; A in brackets where it differs)

| | landmark_v1 | landmark draft 2 | landmark draft 2.1 |
|---|---:|---:|---:|
| C1 ρ median (salience model) | -0.27 [A -0.38] | -0.46 [A -0.45] | **-0.46** [A -0.44]; 33% ≤ -0.5 [A 40%] |
| C2 salience-weighted ink | 0.132 [A 0.093] | 0.065 [A] | 0.080 [A 0.074] |
| C2 coloured ink (loud + quiet, C ≥ 0.04) | 0.481 | 0.093 (quiet at C 0.03-0.04 counted as grey) | 0.248 (loud 0.093 + quiet 0.154) |
| H8: YAML order vs optimum (disc., k = 1) | +19% | +7% | **+1%** (optimum definition → meta → exit → value; value kept longest) |
| H9 normal: % keep all loud families | 33% (all 6) | 68% | 68% (all 4, target 80%) |
| H9 deutan: % keep ≥ 3 (≥ 5 for v1) | 8% | 3% | **69%** (target 60%); protan 68%; all 4: deutan 40%, protan 39% |
| H11 single-channel w ≥ 2 pairs / no-channel pairs | 4 / 3 | 0 / 3 | 0 / 3; removing hue confuses 205 pairs, lightness +1, weight/slant 0 |
| H12 landmark vs label: lower C6 / lower disc. confusion / lower deutan | n/a | 92% / 68% / 78% | 93% / 69% / 71% |
| H12 landmark vs label: lower separable disc. confusion | n/a | n/a | 69% |
| H12 landmark vs hybrid (hybrid lower C6) | n/a | hybrid costs more | hybrid lower C6 in 23%; lower disc. in 23%, higher in 22% |
| H12 landmark vs landmark_v1: lower C6 / keeps all families | n/a | 58% / 65% vs 31% | 64% / 65% vs 31% |
| Mean disc. confusion, landmark / hybrid / label / landmark_v1 / hybrid_v1 | | .00209 / .00216 / .00247 / .00214 / .00267 | .00208 / .00236 / .00247 / .00214 / .00267 |
| Mean separable disc. confusion, same order | | n/a | .00177 / .00205 / .00216 / .00183 / .00236 |
| S1a (lightness) | 97% | n/a (old S1: 1%) | 98% |
| S1b (chroma) | n/a | n/a | 84% (A 86%); S1 both 83%; old all-tier S1 still 1% |
| Quiet success (value own accent, when kept) | n/a | 100% (floor level, C ≈ 0.035) | 99% B / 89% A at the reliable level; median C 0.053 |
| Strings with a quiet tint (own / borrowed / none) | n/a | n/a | B 94 / 0 / 6%; A 84 / 10 / 6% |
| Hybrid definition quiet ok | n/a | 100% | 88% B / 94% A (failed use sites go to default) |
| fg_limited (|Lc fg| < 50) | n/a | n/a | **147 of 1425 (10%)**; dim there is below Lc 40 |

Other mode results. Mode B vs A (H10): C1 ρ A -0.440 vs B -0.464 (A lower in 57%); disc. confusion equal (A lower in 1%, higher in 8%); C6 .00215 vs .00213; habit fit 0.22 vs 0.72.
On draft 2.1 the two modes are again close, so B (habit-based) costs nothing, and it loses 0.02 of ρ on landmark. On v1, A beats B on ρ (-0.38 vs -0.27, A lower in 71%).
Beacon loss: landmark 0.035 (B), hybrid 0.064, label 0.156, v1 0.086. Beacon coverage 0.86 / 0.91 / 0.66 / 0.71. The set ranking by C6 is landmark < landmark_v1 < hybrid < label < hybrid_v1 at λ/3, λ and 3λ.
Capacity with reserve_diag off: 80% keep all 4 (normal), 52% under deutan.

## Render check (out/renders/grid_typescript.html)

Quiet strings now read as a calm warm or cool cast distinct from plain fg. They are visibly different from the plain column but never compete with the loud numbers, `true/false` and exit keywords.
Comments are dim and legible. On tokyo-night-terminal-storm (fg limited), dim sits at Lc 19.9, which is muddy; the cell meta shows it.

## Remaining problems

1. **H9 normal still 68% vs 80%.** Reserving the full red hue name costs 12 points (80% with reserve off). This is the only H9 miss.
2. **Hybrid's quiet use sites for definition fail more often (11-12% of palettes) than strings**, because the reliable D1 is also required against the string quiet colour. Hybrid S1b is only 59-71%, and its mean C6 (.00246 B) and sal.-weighted ink (0.102) are above landmark's (.00213, 0.080); it has lower C6 than landmark in only 23% of palettes.
3. **Capacity and confusion use different CVD rules.** The CVD capacity criterion is now D1 reliable, but C6 deutan confusion is still name-D2 for loud pairs. With the capacity rule, deutan confusion would drop. The spec should state which applies to confusion.
4. **fg_limited palettes (10%)** cannot give a 10-Lc-below-fg dim above Lc 40; L1 cannot be fixed by the pattern.
5. **Mode A strings borrow another family's tint in 10% of palettes** (value's own quiet colour fails for the accent mode A picks; B 1%). Strings end as default ink in 6% (no kept family, or no passing quiet tint).
6. **S1b fails in 16% (landmark B).** The usual cause is a palette with muted loud accents at C 0.08-0.10 against a quiet tint at C 0.05-0.09: the 0.03 margin needs quiet ≤ loud - 0.03. Quiet C near the lower bound avoids it. The old all-adjacent-tier S1 still fails (1%) because loud accents sit below fg in Lc.
7. **Salience weights (b = 0.5) remain unvalidated**; C1/C2 depend on them.
8. **C6 baseline.** About 15% of landmark's discounted confusion (0.00031 of 0.00208) comes from 23 pairs no set separates; the separable cost removes it. Differences between sets are then 0.00177 / 0.00183 / 0.00205 / 0.00216 / 0.00236 for landmark / v1 / hybrid / label / hybrid_v1.
9. **Draft 2 S1a/S1b were not computed** (the draft 2 YAML was overwritten in place), so those cells are n/a.
