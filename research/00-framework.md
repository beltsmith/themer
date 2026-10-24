# Colouring source code: framework (draft 2)

Draft 2 adds §7 (findings from the v1 validation run) and the draft-2 changes listed there.
Sections 1–6 are the draft-1 text except where §7 overrides them. Draft 1 incorporated `notes/01-perception.md` (cited as **P:I#** for its implications),
`notes/02-taxonomies.md` (**T**) and `notes/03-colour-science.md` (**CS:** check IDs).
Claims marked **H#** are hypotheses. **C#** are the criteria the validation agents compute.
Pattern sets are written in machine-readable form in `patterns/*.yaml`.

## 1. Vocabulary

Existing terms are reused where they exist. New terms are marked ✱.

### 1.1 What is styled

| Term | Meaning | Source / equivalents |
|---|---|---|
| **token** | A contiguous span that receives one style. | TextMate scope span; tree-sitter capture; LSP semantic token (T) |
| **token type** | What a token *is*: function, type, variable, keyword, string… Exactly one per token. | LSP `SemanticTokenTypes` (T) |
| **modifier** | An orthogonal property a token *has*. Zero or more per token. | LSP `SemanticTokenModifiers` (T). Tree-sitter, TextMate, Vim and Emacs bake these into names (`function.builtin`), so they can't combine them (T §observations) |
| **site** ✱ | The modifier pair *binding site* (declaration/definition) vs *use site* (reference/call). It applies to every named token type. | LSP `declaration`/`definition`; Emacs 29 `*-call-face`/`*-use-face`; nvim `.call` (T) |
| **provenance** ✱ | The modifier group *intrinsic* (language-defined: `self`, `true`), *library* (`defaultLibrary`), and *user* (the default). T notes that "builtin" mixes the first two. | LSP `defaultLibrary`; `*.builtin` captures |
| **role** | A (token type, modifier set) selector that the pattern styles. | Emacs face, Vim highlight group, Helix scope (T) |
| **family** ✱ | A set of roles that share a hue because they mean one thing to the reader, e.g. *value* = {string, number, boolean, nil, named constant, enum member}. | – |
| **beacon** | A token readers jump to when scanning code non-linearly. | Brooks 1983; Wiedenbeck; Busjahn 2015 (P) |

### 1.2 Visual means

| Term | Meaning | Source |
|---|---|---|
| **channel** | An independent visual variable: hue, lightness, chroma, weight, slant, decoration, background. | Bertin's visual variables |
| **salience** | Bottom-up pull on attention, driven mostly by luminance contrast (CS: Mullen; Legge), then chroma and weight. Ranked by \|Lc\|. | P Terms |
| **attention tier** | A salience level a role is assigned to. Names follow Rougier 2020 (P) where possible. Draft 2 order: **faded** < **dim** < **default** ≈ **quiet** < **loud** < **strong** < **popout** < **critical**, plus **subtle** for background tints. *dim* = achromatic and below default contrast; *quiet* = default contrast with a low-chroma tint; *loud* = an accent with chroma (Rougier's *salient*). | Rougier 2020, *On the design of text editors*; ✱ dim/quiet/loud |
| **region vs landmark** ✱ | A *region* is a token kind that occupies long spans (strings, comments). It needs boundaries visible (segmentation), not pop-out. A *landmark* is a rare, short token the reader jumps to (beacon). Regions get dim/quiet; landmarks get loud. Long marks need smaller colour differences to be seen (CS: Szafir, elongation), so a tint suffices for regions. | – |
| **labelling vs highlighting** | *Labelling* gives every token a category colour, which costs category memory and attention. *Highlighting* marks a few rare targets against a neutral ground and gets pop-out cheaply (P: Fisher & Tan; Haroz & Whitney). | P |
| **ink share** | The fraction of non-whitespace characters a role occupies. | measured: `out/ink_share.*` |
| **salience budget** ✱ | Σ over roles of ink share × salience above default. Exceeding it produces an *angry fruit salad* (existing jargon). | – |
| **monosemy** ✱ | Each channel carries exactly one semantic axis across all token types. | – |
| **lexical recoverability** ✱ | How accurately a token's role can be predicted from its own glyphs plus adjacent characters (quotes, `(`, CAPS, keyword spelling). P:I4 calls this "shape". | measured (§6) |

### 1.3 Palette side

| Term | Meaning | Source |
|---|---|---|
| **palette** | The colours the designer supplies (base16/24, ANSI 16, or a free set). | |
| **surface / ink** | Backgrounds / foregrounds. **default ink** = plain text colour. | Material 3, DTCG (T) |
| **accent** | A chromatic ink with OKLCH C ≥ 0.06, enough for its hue to be nameable (CS:D4). | CS |
| **primitive vs semantic token** | Raw palette colour vs a role-bound alias (`value.ink → green`). The pattern set is the semantic layer, and a palette fills in the primitives. | W3C DTCG (T) |
| **derived colour** ✱ | A colour produced from palette colours by an allowed operation: an OKLCH lightness or chroma shift, an OKLab mix, or a surface blend. **Fidelity** = ΔE_OK from the nearest palette colour. | – |
| **distinguishable (as text)** | `de_text(p=.8, s=.1°) ≥ 1` (reliable) / `p=.5` (floor), with the Szafir 2018 line model. | CS:D1 |
| **categorically distinct** | Distinguishable **and** (different hue name **or** \|ΔL_ok\| ≥ 0.12). | CS:D2 |
| **capacity** ✱ | The largest set of the palette's accents (plus derived colours) that are pairwise categorically distinct and pass CS:L2 on its surface. **CVD capacity** = the same, after deutan/protan simulation. | – |
| **layer** | An independent stratum: **syntax** (foreground), **state** (backgrounds: selection, search, diff), **diagnostic** (underline, gutter), **chrome** (UI). | – |
| **reserved** ✱ | A channel value claimed by one layer. The syntax layer never uses a reserved value. | – |
| **capacity ladder** ✱ | An ordered list of family merges or drops applied as capacity falls. | – |

## 2. What colour can buy

The evidence (P §1) is that conventional highlighting barely affects *comprehension*. Benefits show up in *search* tasks, and only for categories that match the task (P:I3, I14). Colour therefore gets spent only on:

1. **Beacons** – known-target search: "where is X defined", "where does this return", "where are the literals". Colour helps most when the reader knows which colour to look for (P: Green & Anderson).
2. **Segmentation** – where strings, comments and embedded languages start and end.
3. **Disambiguation** – information the glyphs don't carry (P:I4).
4. **Oddballs** – errors, TODOs, deprecated use. These work only if the pop-out treatment stays rare (P:I9).

Costs: category memory (~4–5 hues, P:I2), loss of oddball pop-out as variety grows (Haroz & Whitney), reading speed lost to italic (Tinker), and lost legibility when contrast falls (Legge).

## 3. Hypotheses and criteria

| ID | Hypothesis | Criterion (computed by agents) |
|---|---|---|
| **H1** inverse salience | Salience should fall as ink share rises. | **C1**: Spearman ρ(role salience rank, ink share) ≤ −0.5. **C2**: ink in a non-default hue is ≤ 35% of non-whitespace (band to be calibrated). |
| **H2** colour what glyphs can't say | A role's hue value = beacon value + disambiguation value × (1 − recoverability). | **C3**: per-role recoverability from a lexical classifier. Report the mean recoverability of hue-bearing vs default roles for each pattern set. |
| **H3** monosemy | Channel → axis: hue → family; lightness → tier; weight → site; slant → prose only; decoration → diagnostic/deprecated; background → state layer. | **C4**: static check on the YAML. |
| **H4** binding sites are cheap beacons | Binding sites are < 5% of ink, so bold (plus hue) on them is affordable. | **C5**: ink share of binding sites. A human timed "find definition" task (§5). |
| **H5** constants are values | Named constants and enum members go in the *value* family. Readonly locals are not distinguished. | **C5b**: ink share of readonly locals vs named constants. Recoverability of CAPS constants. |
| **H6** identifiers stay default | Identifier use sites (~70% of characters, P) stay in default ink. | follows from C1/C2 |
| **H7** keywords need no hue | Keywords are a closed, highly recoverable set (P:I4). The exception may be control-flow exits, which are beacons. | **C3** on `keyword.*` vs `keyword.return/exception` |
| **H8** capacity ladder | A merge order exists that minimises confusion cost at every capacity. | **C6**: confusion cost = Σ adjacency(i,j)·w(i,j) over merged must-differ pairs. Search all orders for small family counts. |
| **H9** palettes can carry it | ≥ 80% of chromatic corpus palettes reach the capacity the *landmark* set needs (with derivation, fidelity ≤ 0.05), and ≥ 60% under deutan. | **C7** |
| **H10** salience-driven hue assignment | Giving the highest-salience accent to the rarest high-value family beats conventional hue habits on C1/C6. It costs cross-theme consistency (P:I12), which a human weighs. | **C8**: compare both assignment modes. |
| **H11** graceful degradation | Every must-differ distinction survives the loss of any one of {italic, bold, hue}, or else it is low value. | **C9**: static plus ablated re-run of C6. |
| **H12** landmark beats label | The *landmark* set spends less salience budget, needs less capacity and has lower confusion cost than the *label* set, without losing beacon coverage. | **C10**: compare all metrics across sets. Human task test. |

## 4. Pattern sets

Three candidate sets are written as YAML in `patterns/`:

- **label** – the control: hue by token type everywhere (callable, type, value, keyword, comment). Bold = binding site. This is roughly what most themes do.
- **landmark** – hue only on beacons. Proposed baseline.
- **hybrid** – landmark plus a low-salience hue for callables and types at use sites.

### Landmark set v1 (superseded: see §7 and `patterns/landmark.yaml`)

| Family | Roles | Tier | Channels | Why |
|---|---|---|---|---|
| **definition** | binding site of any named type: function, method, type, class, macro, constant, module, top-level variable | strong | definition hue + **bold** | The main beacon (P:I3, I5). One hue for all binding sites, because the kind of definition can be read from the keyword before it (`def`/`class`/`let`). Bold is redundant with hue (H11). |
| **value** | string, number, boolean, nil, char, regex, named constant (use), enum member | salient | value hue; escapes and placeholders = lightness variant | Literals are a beacon and a segmentation aid. Constants are values (H5). |
| **prose** | comments, doc comments | salient | prose hue *or* achromatic + optional italic (the only place italic is allowed, P:I6) | Readable, not faded (P:I8). Stance can be set by the human. |
| **exit** | return, throw/raise, break, continue, yield, await?, goto | salient | exit hue | Control-flow beacon (P: Rodeghero). Rare. To be tested (H7). |
| **meta** | decorators/attributes, preprocessor, macro invocation | salient | meta hue | Code that changes code. Rare. |
| *(default)* | identifiers at use sites, params, fields, calls, keywords, operators, types at use sites | default | default ink | Neutral ground (P:I1, H6). |
| *(faded)* | punctuation and brackets, unnecessary/unused (LSP tag), inactive `#if` regions, inlay hints, commented-out code where detectable | faded | default ink mixed toward the surface | De-emphasise with lightness (P:I7). |
| *(oddball)* | TODO/FIXME/XXX in comments | popout | emphatic: bold + highest-chroma accent not used by syntax | Rare, high validity. |
| *(reserved)* | errors and warnings | critical | diagnostic layer: underline, gutter, red-ish | Never on syntax (P:I9). |
| *(modifier)* | deprecated | – | strikethrough | Decoration = diagnostic/deprecation axis. |

Capacity needed: 3 hues (definition, value, prose) at minimum and 5 for the full set. The ladder is to be optimised by C6. The prior guess is drop meta → default, then exit → default, then prose → achromatic (lightness-only), then definition → bold-only with default hue.

### Palette → pattern mapping algorithm (to be implemented and tested)

1. Classify the palette: surface = bg; default ink = fg. Accent candidates are palette inks with C ≥ 0.06 and |Lc| ≥ 35. Grey candidates are inks with C < 0.04.
2. Derive: for each accent, allow an OKLCH L shift (gamut-fitted) to reach a tier's Lc target. Record fidelity.
3. Choose the hue-bearing families from the top of the ladder that the palette's capacity allows.
4. Assign accents to families by maximising Σ adjacency-weighted D2 margins plus the salience-order fit (CS:S1), subject to L1–L3. **Mode A (salience-driven)**: rank families by needed salience = value / ink share, and give the highest-salience accents to the highest-need families. **Mode B (conventional)**: hue-name preferences taken from the crosswalk's habits (T: base16 assignments).
5. Fill the faded tier with `mix(fg, bg, t)`, choosing t so that Lc is at its target (CS:L3, L4).
6. Verify all checks, normal and under CVD. Where a pair fails, add redundancy (bold or italic only where the pattern permits) or apply the next ladder merge.

## 5. Human-in-the-loop (non-quantifiable)

1. **Value weights** w(i,j) for distinctions. The seed comes from the literature, and the human edits it once.
2. **Aesthetic acceptability** of renders for ~6 representative palettes × 3 languages × 3 sets.
3. **Consistency vs optimality** (H10): is "functions are always blue" worth the cost?
4. **Prose stance**: comments coloured, achromatic, or italic.
5. **Optional timed tasks** (quantified, but the human is the subject): find-the-definition, find-the-exit, spot-the-literal, on renders with each set. Preference must not be the metric (P:I13).

## 6. Validation pipeline

| Step | Output | Feeds |
|---|---|---|
| Ink share per capture | `out/ink_share.*` | C1, C2, C5 |
| Lexical recoverability per role | `out/recoverability.*` | C3, H7 |
| Within-line role adjacency matrix | `out/adjacency.*` | C6 |
| Static pattern checks (monosemy, degradation) | `out/static_checks.md` | C4, C9 |
| Mapper + palette scoring, normal and CVD | `out/palette_scores.*` | C7, C8, C10 |
| Ladder search | `out/ladder.md` | H8 |
| Renders for human review | `out/renders/` | §5 |

## 7. Findings from the v1 run, and the draft-2 changes

Sources: `out/role_stats.md`, `out/corpus_findings.md`, `out/recoverability.md`,
`out/palette_scores.md`, `out/ladder.md`, `out/static_checks.md`. n = 1349 non-monochrome
palettes (76 near-monochrome excluded), 9 languages (+ elisp, reported separately).

### What the data say

| Hypothesis | Result (v1) | Verdict |
|---|---|---|
| H4 binding sites are cheap | Named binding sites: 4.0% of ink, ~2.7 per screen. All bindings including locals and params: 7.9%, ~9 per screen. | **Holds for named (non-local) bindings.** Locals stay default. |
| H2 / definitions need help | function.def lexical recall is 0.28–0.56 in Lua, TS and JS (no `def` keyword), 0.96 pooled. | **Strong support** for marking definitions, especially in expression-defined languages. |
| H5 constants are values | Readonly locals: TS 8.0%, Rust 3.9%, JS 3.7% of ink (94% of TS locals are `const`). Named constants: ~1%. ALL_CAPS is an unreliable signal (Go 5%, TS 12% of declared constants). | **Holds.** Use semantic tokens where possible. |
| H6 identifiers stay default | Identifier use sites are 65% of code ink. | **Holds.** |
| H7 keywords need no hue | Lexical recall 0.92–0.97 for every keyword role; exit vs flow separable at 0.999. | **Holds.** Exits keep a hue only as a beacon (1.0% of ink, 1.6 per screen). |
| H1/C1 inverse salience | Median ρ = −0.35; only 8% of palettes reach ≤ −0.5. | **Fails in v1**, because strings (15%) and comments (24%) were loud. |
| C2 coloured ink ≤ 35% | Landmark median 48% (prose 24, value 19); label 62%. | **Fails in v1.** Same cause. |
| H9 palettes carry the set | Capacity median 5 (normal), 3 (deutan/protan/tritan, full dichromat). Full v1 landmark (6 hues): 33% normal, 1% deutan. | **Fails as stated.** Budget the set to ≤ 4 loud hues. |
| H8 ladder | One merge order is optimal at every capacity level, but not the YAML order (+11% cost for landmark). C6 lacked a term for lost beacon value. | **Partly holds.** Metric fixed in draft 2. |
| H10 salience vs habit assignment | Mode A ρ −0.35 vs mode B −0.22, with confusion tied. Habit fit 0.24 vs 0.69. Partly circular. | **Open: human decision** (consistency vs optimality). |
| H12 landmark vs label | Landmark has lower raw confusion in 95% of palettes and lower discounted confusion in 69%. Salience budget 0.52 vs 0.67. Keeps every family in 31% of palettes vs 5%. | **Supported, modest margin.** |
| P:I9 reserved diagnostic hue | Without reservation, 65–70% of mapped themes put red on syntax; with it, 13–16% (same-name reds remained). | Reservation now also covers the error colour's hue name. |

### Draft-2 changes (patterns/landmark.yaml header lists them)

1. **Regions vs landmarks.** Strings are *quiet* (the value hue with low chroma), comments are *dim* (achromatic, below default contrast), and escapes, scalars and constants are *loud* in the value hue. A string's active parts are the loud bits inside a quiet region.
2. **Salience is lightness plus chroma** on one declared axis, so the tier order can be checked (S1).
3. **Lightness or weight first, hue second.** The highest-weight distinctions are comment vs code (lightness) and definition vs use (bold). Both survive CVD and monochrome displays, and hue adds category on top (H11).
4. **≤ 4 loud hue families:** definition > value > exit > meta. The oddball (TODO) uses a spare accent, else bold.
5. **Bold's axis is renamed to *landmark*** (binding sites and oddballs: both are jump targets) to keep monosemy.
6. **Distinct hue families need different hue names.** The D2 lightness-only escape no longer applies between families.

### Open spec problems

- *parameter vs variable.use* (separability 0.90; Lua 0.60) and *field vs variable.use* have no channel. Candidates: LSP-only quiet tint for parameters, or nothing (they are frequent: 1.9% and 2.9% of ink).
- Commented-out code can't be distinguished from prose comments with highlights.scm alone (P:I8 wants it faded). This needs a heuristic or LSP.
- Mode A vs B (H10) is a human call.

## 8. Correction from human review: reading vs finding (draft 3)

**Feedback (2026-10-23).** On the Gruvbox, Monokai, Kanagawa and Zenburn renders, the
landmark set was "very hard to parse at a glance". Python was close to usable. Go, Rust and C
were worse, and TypeScript was the worst: types, variables and calls couldn't be told apart.
The reviewer observed that colouring keywords differently "allows them to fade into the
background and lets the logic stand out".

**Diagnosis.** Three of the framework's assumptions were wrong.

1. *Lexical recoverability ≠ free.* A classifier that sees each token's text recovers
   keywords 92–97% of the time, but a human must **read** a token to recover it that way.
   Colour gives the category *before* reading, through pre-attentive segmentation. H2 and
   H7 discounted exactly the distinctions that make code parseable at a glance.
2. *Finding was the only task modelled.* The confusion cost, beacon coverage and C1 all
   reward landmarks. Nothing measured the load of parsing a line. P:I14 ("design for
   finding") over-generalised evidence that came from novices doing comprehension tasks on
   small programs.
3. *The category limit was applied to every hue.* The 4–5 category limit (Haroz & Whitney)
   concerns search and odd-one-out detection among **salient** categories. Low-salience
   texture cues are a different use of colour, and the limit may not bind them in the same
   way. **H13** below tests this.

**New hypotheses.**

- **H13 (label quietly, landmark loudly).** Low-salience category cues on every token
  (recessive keywords; quiet types, calls and strings) cut parse load sharply without hurting
  landmark search, as long as the landmark forms stay louder than every cue.
  *C11:* parse load, H(reading class | visual style) in bits per token, and ambiguous tokens
  per screen (`out/parse_load.*`). It should fall well below landmark's while C1 stays ≤ −0.4.
- **H14 (keywords recede by hue).** A keyword hue at *lower* contrast than default makes the
  syntax skeleton recede and the names stand out. Default ink belongs to bindings, "the logic".
  This is a human judgement, checked in renders.

**Draft-3 set:** `patterns/reader.yaml`.

- Hue = kind family: syntax, callable, type, value, meta (5, at the cap).
- Salience = importance:
  - recessive keywords, loud exits;
  - quiet calls and types, strong definitions;
  - quiet strings, loud literals.
- Exits no longer need their own hue: they are the loud form of the syntax hue.
