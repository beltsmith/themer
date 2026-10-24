# Reader: a standard for colouring source code (draft 3.2)

This standard defines how editor and terminal themes colour source code. It fixes the
*meaning* of each visual channel and which kinds of token receive which treatment. Colour
choice is left to the theme creator. The key words MUST, SHOULD and MAY are used as in
RFC 2119.

- Machine-readable form: `patterns/reader.yaml` with `patterns/roles.yaml`.
- Rationale: `00-framework.md`, §8 for this draft.
- Superseded drafts: `patterns/landmark.yaml` (draft 2.2) and `patterns/landmark_v1.yaml`.

## 0. Principle: label quietly, landmark loudly

Code is both **read**, by parsing a line's structure at a glance, and **searched**, by
jumping to definitions, exits and literals. The two need different things from colour.

- **Reading layer.** Every token gets a *low-salience* category cue, so syntax, types,
  calls and variables separate before they are read. Keywords take a hue at *lower*
  contrast than default, so the syntax skeleton recedes and the logic (variables, in
  default ink) stands out.
- **Finding layer.** The same hues, *loud* and bold, mark the few landmarks: definitions,
  exits and literals.

So **hue = kind**, **lightness + chroma = importance**, **bold = landmark**.

## 1. Channels (normative)

| Channel | MUST mean | MUST NOT be used for |
|---|---|---|
| hue | the *kind family* (§3) | ranking importance |
| lightness + chroma | *salience tier* (§2) | category |
| bold | *landmark*: binding sites, exits, TODO markers | anything else |
| italic | prose (comments) only; optional | identifiers or keywords |
| strikethrough | deprecated | – |
| underline / gutter | diagnostics and links | syntax |
| background | editor state: selection, search, diff, current line | syntax |

**Fixed conventions.** Everything else about hue is the creator's choice.

- Errors MUST be red on the diagnostic layer. Warnings SHOULD be yellow or orange.
- Diff additions MUST be green and deletions red, as backgrounds.
- Red MAY be a syntax hue: errors are identified by underline, not by owning red.

**Chrome accent.** A theme MAY define one UI *accent* for the chrome layer: the cursor,
minibuffer and shell prompts, mode-line highlights (buffer name, LSP status), the current
line number, key bindings, completion matches, and section headings in UI buffers. It MUST
NOT colour syntax tokens, so it doesn't count against the family cap. It MAY share a hue
with a family. It SHOULD reach Lc ≥ 60 where it colours text. If unset, it defaults to the
popout colour.

## 2. Salience tiers (normative)

Lc is APCA contrast against the background (absolute value); C is OKLCH chroma. "Reliably
distinct" = text-size colour difference at p = .8 (`notes/03`).

| Tier | MUST | SHOULD | Used for |
|---|---|---|---|
| faded | Lc ≥ 15 | Lc ≈ 30, achromatic | punctuation, unused code |
| dim | Lc ≥ 20; ≥ 10 below default; C ≤ 0.04 | Lc ≈ 45 | comments |
| **recessive** | 6–18 Lc below default; C 0.04–0.12; reliably distinct from default, dim, faded and its own loud form | – | keywords |
| default | Lc ≥ 45 | Lc ≥ 60 | variables, parameters, fields, operators |
| **quiet** | within 12 Lc of default; C 0.04–0.10; reliably distinct from default, dim, recessive and every other quiet colour | – | calls, type uses, strings, macro calls |
| loud | Lc ≥ 35; C ≥ 0.08 | Lc ≥ 45 | literals, constants, decorators |
| strong | loud + bold | – | binding sites, exits |
| popout | bold + an accent | an accent not used by any family | TODO / FIXME / XXX |

## 3. Kind families (normative)

A conforming theme provides one accent per family. The quiet and recessive forms are
derived from it. Loud accents MUST be pairwise categorically distinct under normal vision
(reliably distinct, with different basic colour names). They SHOULD stay reliably distinct
under deuteranopia and protanopia simulation.

| Family | Reading layer (quiet / recessive) | Finding layer (loud / strong) |
|---|---|---|
| **syntax** | keywords, `self`/`this`, labels (recessive) | exits: return, raise/throw, break, continue, yield, goto, Rust `?` (strong) |
| **callable** | function and method calls, builtins (quiet) | function and method definitions (strong) |
| **type** | type uses, builtin types, modules/namespaces (quiet) | type definitions (strong) |
| **value** | strings, regexps (quiet) | numbers, booleans, nil, named constants, enum members, escapes (loud); constant definitions (strong) |
| **meta** | macro calls (quiet) | decorators, attributes, preprocessor (loud); macro definitions (strong) |

**Not coloured:** variables, parameters and fields stay in default ink, so the logic stands
out. Module-level variable definitions are bold default ink. Operators are default and
punctuation is faded. Comments are dim.

**Optional cues.** These add no salient meaning, so they don't count against the cap.

- **Parameter tint (binding family, quiet only).** A theme MAY give parameters a quiet tint.
  It MUST be reliably distinct from default and from every other quiet colour, and it SHOULD
  use a hue the other quiet cues don't. It works best with LSP semantic tokens, which mark
  every use; tree-sitter mostly marks declarations.
- **Faded commented-out code.** A theme MAY show comments that look like code in the faded
  tier instead of dim, which separates disabled code from prose. Detection is heuristic, and
  the option SHOULD be off by default.

**Why five.** Five is the reader-side limit on salient colour meanings (`notes/01`, Haroz
& Whitney 2012). The quiet and recessive forms reuse their family's hue, so they add
texture without adding meanings. A theme MUST NOT add a sixth hue family.

## 4. Reduced conformance

Where a palette or display can't meet §2 and §3, families are shed in this order, and the
theme MUST declare the level it reaches:

| Level | Shed | Fallback |
|---|---|---|
| R1 | meta | meta's roles use the syntax family |
| R2 | type | types use the callable family; position separates them |
| R3 | failing quiet cues | those roles go to default; loud forms and bold stay |
| R4 | recessive keywords | keywords go to default; the last cue for syntax vs names is lost |

**Full** conformance requires every MUST under normal vision. **Full+CVD** additionally
meets the CVD SHOULDs.

## 5. Checking a theme

`harness/mapper.py` mode C takes a palette and the creator's family → colour assignment.
It derives the recessive, quiet, dim and faded forms, reports every MUST and SHOULD, and
reports the conformance level. `harness/parse_load.py` measures reading and
`harness/score_palettes.py` measures finding. The 1,425-palette corpus measures how far
existing themes are from conforming. It is not a design target.

## 6. Evidence

Corpus: ~280k lines in 10 languages (nvim-treesitter queries). Results are in
`out/draft3_results.md`, `out/parse_load.md`, `out/role_stats.md` and `out/recoverability.md`.

| Claim | Number |
|---|---|
| Reading: category is far less ambiguous from colour alone | 0.55 bits/token median across all palettes (plain 2.59, landmark 1.02, label 0.42); 29 ambiguous tokens per screen (plain 105, landmark 51) |
| Reader beats landmark on reading | 96% of palettes; −0.64 bits, −26 ambiguous tokens per screen |
| Reading costs little finding | salience budget 0.12 (landmark 0.08, label 0.16); rarer-is-louder ρ −0.40 (landmark −0.47); landmark coverage 0.94 (0.86) |
| Bold the landmarks | named binding sites are 4% of ink; exits 1%. Function definitions are hard to recognise from text alone in Lua (0.28), TS (0.47) and JS (0.56) |
| Readonly isn't a colour | 94% of TS locals are `const` |
| Variables stay default | identifier uses are 65% of code ink: the "logic" |
| Optional parameter tint | Separates parameters at a glance: ambiguous tokens per screen 29.6 → 26.0 (−12%) on the creator palettes. A passing tint exists for 89% of palettes. Doesn't help under CVD. (`out/draft32_results.md`) |
| Optional fading of commented-out code | Heuristic precision ≈ 88% on 83 corpus samples; recall is low. Commented-out code is 0.2–5% of comments, so the effect is local, not global. |
| Rust `?` as exit | Rust exits per screen rise from 0.37 to 1.02, so `?` is the main exit in idiomatic Rust. |
| Timed search, 1 subject, 36 trials | reader most accurate (F1 0.84 vs landmark 0.66, label 0.71, plain 0.62); ties landmark on speed × accuracy; beats plain in 7/9 blocks; n.s. (`out/task_analysis.md`) |
| Human review | landmark-only colouring was "very hard to parse at a glance"; keyword colour "lets the logic stand out" (2026-10-23) |

## 7. Known limits and open questions

- **CVD.** Under red–green CVD simulation, quiet tints merge, and reader's parse load (1.51
  bits) is worse than landmark's (1.40). Keywords vs names mostly survives, because the
  recessive keywords are also darker. That is why the CVD rules are SHOULD, not MUST.
- **Low-chroma palettes** (e.g. Zenburn) struggle to produce distinct quiet tints:
  1.08 bits vs about 0.45 for Gruvbox, Monokai and Kanagawa.
- **Fields vs locals** have no channel. Parameters have an optional tint.
- **Commented-out code detection** is a heuristic and can misfire on prose that quotes code.
- **Performance data is one subject.** The parse-load metric is a proxy, and more subjects
  would turn the timed test into evidence.
