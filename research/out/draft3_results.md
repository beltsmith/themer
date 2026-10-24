# Draft 3 (reader) results

Sources: `out/parse_load.{csv,md}` (harness/parse_load.py), `out/palette_scores.{csv,md}` (score_palettes.py, now including
`reader`), `out/renders/grid_*.html` + `tasks.html` (render.py). Mapper: `mapper.map_reader` (docstring has the algorithm).

## 1. Reading: parse load

H = H(class | look-alike cluster), bits/token. amb = tokens per 40-line screen whose look-alike cluster is majority
another class. Plain = H(class) = 2.590 bits, 104.8 amb/screen (no punctuation: 2.856, 74.2).

Creator palettes (mode C), mean of gruvbox-dark-medium / monokai / kanagawa / zenburn:

| set | H | amb | H deutan | amb deutan | H protan | amb protan | H no punct | amb no punct |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| plain | 2.590 | 104.8 | 2.590 | 104.8 | 2.590 | 104.8 | 2.856 | 74.2 |
| landmark C | 1.058 | 53.2 | 1.948 | 83.4 | 1.961 | 83.7 | 1.649 | 48.8 |
| label C | 0.701 | 36.5 | 1.849 | 77.8 | 1.792 | 76.2 | 0.862 | 30.1 |
| reader C | **0.568** | **29.2** | 1.802 | 78.2 | 1.841 | 78.4 | **0.775** | **24.9** |

All 1425 palettes, mode B (medians):

| set | H | amb | H deutan | amb deutan | H protan | amb protan | H no punct | amb no punct |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| landmark B | 1.019 | 50.5 | 1.396 | 65.0 | 1.372 | 65.0 | 1.579 | 46.2 |
| label B | **0.420** | **24.3** | **1.012** | **52.6** | **0.924** | **49.5** | 0.673 | 23.6 |
| reader B | 0.553 | 28.7 | 1.532 | 70.8 | 1.412 | 67.6 | **0.559** | **21.1** |

Paired over the 1425 palettes (mode B), reader has lower H than landmark on 96% of them. The median gain is −0.62 bits/token
and −26 ambiguous tokens per screen. Without punctuation, reader beats label (0.559 vs 0.673). With punctuation counted, label is lower (0.420 vs 0.553). This has not been broken down by class yet. Label gives more classes a hue (field, keywords loud), and those clusters stay apart from the faded-punctuation cluster under the D1-reliable rule more often. Per-palette numbers are in out/parse_load.md.

Under CVD, reader is the worst of the three in mode B. The CVD clusters chain (union-find): fg, the quiet tints, the
recessive keywords and the loud accents fall within D1 of each other one step at a time, so whole palettes collapse
into one or two clusters. For example, gruvbox reader under deutan gives H 2.54, which is almost plain. The quiet and
recessive cues are designed to be just D1-reliable under normal vision, so CVD removes them first. Treat the CVD columns
as a lower bound.

## 2. Finding: reader vs landmark (palette_scores.md, mode B medians unless noted)

| metric | landmark B | reader B | label B |
|---|---:|---:|---:|
| coloured ink (C2 v1) | 0.246 | 0.457 | 0.698 |
| salience budget (sal.-weighted ink) | 0.079 | 0.119 | 0.163 |
| C1 ρ (salience vs ink share) | −0.47 | −0.41 | −0.20 |
| confusion, discounted normal | 0.00204 | 0.00238 | 0.00211 |
| C6 total discounted (mean) | 0.00207 | 0.00247 | 0.00226 |
| beacon coverage | 0.86 | 0.94 | 0.94 |
| S1b (quiet C + .03 ≤ loud C) | 84% | 36% | n/a |

Creator palettes, mean: salience budget 0.087 (landmark) vs 0.111 (reader); C1 ρ −0.35 vs −0.29; C6 disc 0.00205 vs 0.00208.
Reader spends about 50% more salience budget than landmark (median paired Δ +0.033) and stays below label. C1 weakens
slightly. The confusion cost is higher because quiet and recessive tints are D1-floor distinctions that `_confused`
counts as confusions under deutan, and because beacon loss is measured against reader's own, richer design.

## 3. Conformance

Levels (map_reader): R0 full; R1 meta → syntax loud; R2 + type → callable; R3 = R2 with failing quiet cues set to
default; R4 = R3 with the recessive cue also set to default; none = loud families still fail at R2. `level` uses the full
loud check: D2 under normal vision, D1-reliable under deutan and protan, L2, and dim. `level_normal` drops the CVD part.

| palette (mode C) | level | level, normal vision | recessive | quiet type / callable / value / meta |
|---|---|---|---|---|
| gruvbox-dark-medium | none (CVD: meta/syntax, type/callable, callable/syntax) | R2 | ok | ok / ok / ok / ok |
| monokai | R3 | R3 | ok (C .05) | – / ok / **fail** / – |
| kanagawa | none (CVD) | R1 | ok, outshines exits | ok / ok / ok / ok |
| zenburn | none (CVD) | R2 | ok, outshines exits | ok / ok / ok / ok |

Mode B, all palettes: `level` R0 2%, R1 4%, R2 14%, R3 3%, R4 2%, none 76%. `level_normal` R0 42%, R1 12%,
R2 10%, R3 14%, R4 5%, none 15%. Hue families kept (capacity): 5 in 47% of palettes, 4 in 14%, 3 in 26%, fewer than 3 in 14%.

## 4. Reading-layer success (mode B)

- Recessive: ok on 87% of palettes. On 32% of those, the keywords end up more salient (colour.salience_v2) than
  `keyword.exit` in the same hue.
- Quiet, among palettes that keep the family and give it quiet roles: type 94% (n 865), callable 82% (n 1237),
  value 97% (n 1372), meta 89% (n 671).

## 5. Render checks (grid_go.html, grid_typescript.html)

- Go `func (r *multipartRequest) TrySet(...)`, gruvbox reader C: `func` is recessive red (#f29281). `multipartRequest`,
  `Value`, `StructField`, `string`, `setOptions`, `bool` and `error` are the quiet type tint (#d2ad65); `reflect` (module)
  takes the same tint. `TrySet` is bold callable green (#b8bb26). Parameters are default. As specified.
- TS `test("tuple inference", ...)`: calls (`tuple`, `function`, `assertEqual`, `test`) are the quiet callable tint,
  types (`TypeOf`, `func1` in `<func1, …>`, `string`, `number`) the quiet type tint, `type func1` is bold type, and the
  variables (`args1`, `z`, `func1`) are default. All three can be told apart in gruvbox, kanagawa and zenburn. In
  gruvbox, type (#d2ad65) and default (#d5c4a1) differ mainly in chroma and are the weakest pair.
- Monokai (R3): strings are default ink because the value quiet tint failed (fg #f8f8f2 is near white, and no tint is
  D1-reliable from fg, the recessive and dim). Keywords are only faintly pink (C .05). Types and calls share the
  callable tint (R2 shed).
- Not mapper bugs: Go `errors` in `errors.New`, and `multipartRequest` inside `(*multipartRequest)(nil)`, are captured
  as variables by the nvim-treesitter queries.

## 6. Problems and proposed pattern changes (patterns/ not edited)

1. **CVD makes R0–R2 nearly unreachable.** 76% of palettes, and 3 of 4 creator palettes, fail the loud deutan/protan
   check even after shedding to 3 hues. Options: make `level` normal-vision only and report CVD separately (as
   `level_normal` does now), or add a CVD shed step (e.g. callable → bold only).
2. **Recessive outshines loud.** The recessive tier says "maximise distinctness from fg". When the family accent is
   muted (kanagawa exit salience < fg, zenburn exit C .066), keywords end up more salient than the exits that share
   their hue (32% of successes). Loud-relative rules were tried and rejected because they kill the cue on exactly those
   palettes: C ≤ C_loud (− .03), and salience(recessive) ≤ salience(loud). Proposal: give exits `strong` (bold) under
   reader, or pick the *least* distinct passing recessive point (fg + just-reliable).
3. **S1b fails on 64% of reader B palettes.** The quiet chroma ceiling (0.10) sits too close to the loud floor (0.08).
   Proposal: quiet chroma [0.05, 0.08], or measure S1b per family.
4. **YAML gaps the harness had to fill.** (a) `type` has no `fallback`, yet the comment says type → callable: implemented
   in `mapper_common.SET_FALLBACKS`, and the fix is to add `fallback: {family: callable}`. (b) `fallback: {family: syntax,
   tier: loud}` is applied to reading-layer roles only (macro.call quiet → loud); macro.def stays strong (bold). (c) The
   quiet joint search also requires D1 from dim (strings vs comments; draft-2.1 rule): add `dim` to `distinct_from`.
   (d) Recessive also requires D1 from its own loud accent (keyword vs keyword.exit): add `loud` to `distinct_from`.
   (e) Shedding R3 drops only the failing quiet cues, not all of them.
5. **Operators** are default ink in both reader and label. They share a cluster with the bindings, so about 12 operator tokens per screen are ambiguous in every set. If the operator/binding split matters for reading, consider the faded or recessive tier for operators.
6. **Separable cost baseline moved.** `unseparated_pairs()` now includes reader in `SETS`, so the `*_sep` columns
   shifted for every set.

---

# Draft 3.1 (patterns/reader.yaml "draft 3.1")

Changes in the YAML: `keyword.exit` is `strong` (loud + bold); the `type` family has `fallback: {family: callable}`;
quiet chroma [0.04, 0.08]; quiet `distinct_from` lists `dim`; recessive `distinct_from` lists `own_loud`.
Harness: the mapper now reads these from the YAML. `SET_FALLBACKS` is removed from `mapper_common`. The recessive avoid set
(dim, faded, own_loud) and the quiet avoid set (dim, recessive) come from the `distinct_from` lists. The quiet chroma was
already read from `tiers.quiet.chroma`, so `QUIET3_C` is only a default (now equal to the 3.1 value).
Other sets unchanged: every landmark, label, hybrid, landmark_v1 and hybrid_v1 row of `out/palette_scores.csv` (21375 rows)
and every landmark/label row of `out/parse_load.csv` is identical to the draft-3 run (numeric and text columns).

Measure change: `outshines_loud` now gives the loud accent its bold term when the family's keyword role is `strong`
(exit is bold in 3.1). The draft-3 definition (no bold) is kept as `outshines_loud_nobold` in the theme JSON. On that old
definition the rate is unchanged at 32%, so the whole drop below comes from counting bold.

## 1. Reading: parse load (draft 3.1)

Plain: H 2.590, 104.8 amb/screen (no punct 2.856, 74.2). Cells are H / amb per screen.

Creator palettes (mode C, mean of 4):

| set | H / amb | deutan | protan | no punct |
|---|---:|---:|---:|---:|
| plain | 2.590 / 104.8 | 2.590 / 104.8 | 2.590 / 104.8 | 2.856 / 74.2 |
| landmark C | 1.058 / 53.2 | 1.948 / 83.4 | 1.961 / 83.7 | 1.649 / 48.8 |
| label C | 0.701 / 36.5 | 1.849 / 77.8 | 1.792 / 76.2 | 0.862 / 30.1 |
| reader C | **0.632 / 32.7** | 1.746 / 75.2 | 1.816 / 78.1 | 0.888 / 28.4 |

All 1425 palettes, mode B (medians):

| set | H / amb | deutan | protan | no punct |
|---|---:|---:|---:|---:|
| landmark B | 1.019 / 50.5 | 1.396 / 65.0 | 1.372 / 65.0 | 1.579 / 46.2 |
| label B | 0.420 / 24.3 | 1.012 / 52.6 | 0.924 / 49.5 | 0.673 / 23.6 |
| reader B | 0.553 / 29.2 | 1.523 / 70.6 | 1.457 / 67.4 | 0.552 / 19.8 |

## 2. Finding metrics

| metric (mode B medians) | landmark | reader 3.1 | label |
|---|---:|---:|---:|
| salience budget | 0.079 | 0.112 | 0.163 |
| C1 ρ | −0.47 | −0.41 | −0.20 |
| beacon coverage | 0.86 | 0.94 | 0.94 |
| S1b pass rate | 84% | 49% | n/a |

Creator palettes, mean: salience budget 0.087 / 0.100 / 0.102 (landmark / reader / label); C1 ρ −0.35 / −0.32 / −0.34;
beacon coverage 0.86 / 0.89 / 0.97.

## 3. Conformance and reading-layer success

Mode B, all palettes: `level` R0 1%, R1 4%, R2 13%, R3 4%, R4 2%, none 76%. `level_normal` R0 38%, R1 10%, R2 12%, R3 19%,
R4 5%, none 15%.

| palette (mode C) | level | level, normal vision | recessive | quiet type / callable / value / meta |
|---|---|---|---|---|
| gruvbox-dark-medium | none | R3 | ok | **fail** / **fail** / ok / ok |
| monokai | R3 | R3 | ok | – / ok / fail / – |
| kanagawa | none | R2 | ok, outshines exits (bold-aware) | **fail** / ok / ok / ok |
| zenburn | none | R2 | ok | **fail** / ok / ok / **fail** |

Mode B: recessive ok 87%. Keywords outshine exits on 12% of successes (bold-aware; 32% on the draft-3 definition).
Quiet success: type 87% (n 852), callable 78% (n 1237), value 96% (n 1372), meta 85% (n 666).

## 4. Before / after (draft 3 vs 3.1)

| metric | draft 3 | draft 3.1 |
|---|---:|---:|
| reader C, H / amb | 0.568 / 29.2 | 0.632 / 32.7 |
| reader C, H / amb no punct | 0.775 / 24.9 | 0.888 / 28.4 |
| reader C, H deutan / protan | 1.802 / 1.841 | 1.746 / 1.816 |
| reader B, H / amb | 0.553 / 28.7 | 0.553 / 29.2 |
| reader B, H / amb no punct | 0.559 / 21.1 | 0.552 / 19.8 |
| reader B, H deutan / protan | 1.532 / 1.412 | 1.523 / 1.457 |
| salience budget, B median | 0.119 | 0.112 |
| salience budget, C mean | 0.111 | 0.100 |
| C1 ρ, B median / C mean | −0.41 / −0.29 | −0.41 / −0.32 |
| beacon coverage, B median / C mean | 0.94 / 0.93 | 0.94 / 0.89 |
| S1b pass rate (B) | 36% | 49% |
| outshines_loud (of recessive successes) | 32% (no bold) | 12% bold-aware (32% no bold) |
| recessive ok | 87% | 87% |
| quiet type / callable / value / meta | 94 / 82 / 97 / 89% | 87 / 78 / 96 / 85% |
| `level` R0 / R1 / R2 / R3 / R4 / none | 2 / 4 / 14 / 3 / 2 / 76% | 1 / 4 / 13 / 4 / 2 / 76% |
| `level_normal` R0 / R1 / R2 / R3 / R4 / none | 42 / 12 / 10 / 14 / 5 / 15% | 38 / 10 / 12 / 19 / 5 / 15% |
| creator levels (gruvbox / monokai / kanagawa / zenburn) | none / R3 / none / none | none / R3 / none / none |
| creator `level_normal` | R2 / R3 / R1 / R2 | R3 / R3 / R2 / R2 |

Reading of the result:
- Exit as `strong` fixes the exit-vs-keyword salience problem once bold is counted (32% to 12%). Kanagawa still has recessive
  keywords brighter than its bold exit.
- The 0.08 quiet ceiling helps S1b (36% to 49%) but is still far from the landmark's 84%. The ceiling equals the loud floor, and S1b needs a 0.03 margin.
  A ceiling of about 0.05 would be needed to pass it everywhere, which leaves very little room for a D1-reliable tint.
- It costs quiet cues. Three creator palettes (gruvbox, kanagawa, zenburn; monokai has no type quiet) lose the type tint (ok in draft 3), and
  gruvbox loses callable and zenburn loses meta too. Mode B quiet success drops 4 to 7 points on type, callable and meta. On creator palettes this pushes the
  normal-vision level down (kanagawa R1 to R2, gruvbox R2 to R3), and reader C parse load rises from 0.568 to 0.632 bits. Mode B median parse load is unchanged.
- Adding `dim` to the quiet `distinct_from` was already enforced by the harness, so it changes nothing. Likewise `own_loud` for recessive.
  The `type` fallback is now read from the YAML and behaves as before.
- CVD still dominates `level`: none on 76% of palettes, unchanged (problem 1 of draft 3 stands).
