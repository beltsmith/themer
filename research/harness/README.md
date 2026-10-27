# Research harness

All commands run from `research/`. Python deps come from `uv run --with ...`; no venv needed.
Clones live under `data/` and are git-ignored (`data/.gitignore`); only derived outputs
(`data/palettes.jsonl`, `data/corpus_manifest.json`, `out/*`) are meant to be committed.

## 0. Fetch sources (once)

```sh
bash harness/fetch_sources.sh
```

Shallow clones: tinted-theming/schemes, iTerm2-Color-Schemes (sparse: `windowsterminal/`),
nvim-treesitter (queries + parser lockfile), Wilfred/tree-sitter-elisp, and the code corpus
repos into `data/corpus/<owner>_<repo>` (neovim is sparse: `runtime/lua`).

## Job A: palette corpus

```sh
uv run --with pyyaml python harness/load_palettes.py
```

Writes `data/palettes.jsonl`, one palette per line:
`{id, source, family, name, variant, variant_declared, variant_computed, bg, fg, bg_L, colours, author, licence_note}`.

- base16/base24: `data/schemes/{base16,base24}/*.y*ml`. bg = base00, fg = base05; `colours` = the
  base00..base0F (..base17) slots. `variant` comes from the file when declared (all of them are).
- ansi16: `data/iterm2/windowsterminal/*.json`. `colours` = the 16 ANSI slots
  (black..brightWhite) plus cursorColor/selectionBackground when present. Variant is computed.
- `variant_computed`: dark if OKLab L(bg) < 0.6, otherwise light. It agrees with every declared
  variant in tinted-theming.
- Not loaded: tinted-theming's `tinted8/` directory (different format, out of scope).

## Job B: token ink share

```sh
uv run python harness/build_parsers.py      # needs git + a C compiler
uv run python harness/select_corpus.py      # -> data/corpus_manifest.json
uv run --with tree-sitter --with tree-sitter-language-pack python harness/ink_share.py
```

- `build_parsers.py` builds each grammar at the exact revision nvim-treesitter pins in
  `lua/nvim-treesitter/parsers.lua` and writes `data/parsers/<lang>.so`. elisp is built from
  tree-sitter-elisp HEAD. This step matters. The newer grammars in tree-sitter-language-pack have
  drifted from the queries. For example, Python's `expression_statement` became a hidden node, so
  the docstring pattern matched every string. If a `.so` is missing, `highlight.py` falls back to
  the language-pack grammar and drops each pattern that doesn't compile, one at a time.
- `select_corpus.py` takes a seeded random sample per language. It interleaves the two repos and
  caps each language at 150 files or 30k lines. It skips files over 6000 lines, minified files
  (any line over 500 chars), vendored/build/fixture directories, and neovim's generated
  `_meta`/`.gen.` API stubs. The manifest records every file and each repo's commit.
- `highlight.py` loads the queries and paints each byte with its winning capture.
- `ink_share.py` computes the statistics and writes `out/ink_share.csv` (long format),
  `out/ink_share.md` and `out/query_coverage.json`.

### Highlight semantics and approximations

- Queries: `nvim-treesitter/runtime/queries/<lang>/highlights.scm`. `; inherits:` is resolved
  recursively with parents first (javascript = ecma + jsx + javascript; typescript = ecma +
  typescript). nvim-treesitter has no elisp queries, so elisp uses tree-sitter-elisp's own
  `queries/highlights.scm`. That query is sparse: it doesn't capture function calls or plain
  symbols, so about 40% of elisp ink is `default`.
- Predicates: py-tree-sitter handles `#eq?`, `#not-eq?`, `#match?` and `#any-of?` natively.
  `#lua-match?` and `#not-lua-match?` are rewritten to `#match?` and `#not-match?`, with a Lua
  pattern to regex translation: `%a %d %l %u %s %w %x %p %c` and their negations, `%` escapes,
  `-` becomes lazy `*?`, and `(?s)` is added because Lua's `.` matches newlines.
  `#has-ancestor?`, `#not-has-ancestor?`, `#has-parent?`, `#not-has-parent?` and `#contains?` run
  in a Python callback. Any other predicate counts as true. `#set! priority N` is honoured;
  other `#set!` directives and `#offset!`/`#gsub!` are ignored.
- Two jsx patterns are dropped (`@_jsx_element`/`@_jsx_attribute` use 3-arg `#set!`). Both are
  private captures with no effect on colour.
- Paint order: sort occurrences by (priority, start asc, end desc, pattern index) and paint later
  ones over earlier ones. Higher priority wins first, then the innermost node, then the later
  pattern in the file, which is how nvim behaves. `@spell`, `@nospell`, `@conceal` and `@_*` are
  ignored. `@none` paints "default".
- Injections are not run, so doc-comment markup, regex internals and embedded languages keep
  their host's colour.

### Metric definitions

- Characters: non-whitespace code points (UTF-8 continuation bytes skipped).
- Token: one painted capture occurrence, counted once even if it spans lines or is split by
  inner captures. Uncaptured text is split into whitespace-separated runs, each labelled
  `default`.
- `per_screen_median` / `per_screen_mean`: distinct tokens per non-overlapping 40-line window
  (trailing windows under 10 lines dropped), with zeros included. Pooled median is taken over
  all windows from all languages.
- `line_frac`: fraction of non-blank lines that contain at least one character of the capture.
- Levels: `full` is the capture name. `top` is the first dotted component. `role` groups by
  definition or use and also harmonises naming: function.def, function.use, variable.plain,
  variable.parameter, variable.member (which includes `property`), type.def and type.use.
- Pooled shares are the unweighted mean over the 10 languages; JS and TS count separately.

## Job C: role statistics, recoverability, adjacency

```sh
uv run --with tree-sitter --with tree-sitter-language-pack --with pandas --with pyyaml \
    python harness/role_tokens.py        # -> data/cache/role_tokens.pkl (git-ignored), ~10 s
uv run --with pandas --with numpy python harness/role_stats.py
uv run --with pandas --with numpy --with scikit-learn --with pyyaml python harness/recoverability.py   # ~5 min
uv run --with pandas --with numpy --with pyyaml python harness/adjacency.py
```

- `role_tokens.py` re-paints the corpus with `highlight.load` (same paint order as `highlight.paint`)
  and maps each winning capture to a `patterns/roles.yaml` role id (most specific selector; fallback
  drops trailing components; uncaptured -> `default`). It splits `@variable`/`@constant`/`@type`
  into binding vs use sites with each language's nvim-treesitter `locals.scm`
  (`@local.definition*`, inherits resolved; imports excluded) plus a name-field heuristic, tags
  bindings top-level vs local (inside any function/method/lambda/closure), classifies declarations
  (declared const, enum member, JS/TS module `const`, readonly local, mutable), splits
  `@function.macro` into macro.def/macro.call, and narrows keyword.exit to exit words (see the
  module docstring). elisp has no locals.scm. Rows are visible token segments.
- `role_stats.py` -> `out/role_stats.{csv,md}`, `out/binding_stats.csv`, `out/constant_stats.csv`.
  lang=ALL is the unweighted mean over languages excluding elisp.
- `recoverability.py` -> `out/recoverability.{csv,md}`, `out/recoverability_confusion.csv`,
  `out/recoverability_pairs.csv`: logistic regression on lexical features, GroupKFold(5) by file.
- `adjacency.py` -> `out/adjacency.{csv,md}`: line co-occurrence and same-line neighbour pairs
  (raw and skipping punctuation).
- `out/corpus_findings.md` is written by hand from these outputs (H4-H7).

## Job D: pattern checks, mapper, palette scoring, ladder

Needs `out/role_stats.csv`, `out/adjacency.csv`, `out/recoverability_pairs.csv` and
`out/recoverability_confusion.csv` from Job C. Without them the loaders fall back: ink shares
from `out/ink_share.csv` through the roles.yaml selectors, adjacency = product of ink shares, and
separability 0. Each report names the source it used.

```sh
D="--with coloraide --with pyyaml --with numpy --with scipy"
uv run --with coloraide python harness/colour.py                 # self-tests against notes/03 values (prints ALL OK)
uv run --with pyyaml python harness/static_checks.py             # -> out/static_checks.md (C4, C9, budget, coverage, H11 ablation)
uv run $D python harness/mapper.py                               # -> out/mapped/*.json (example themes, all sets x modes)
uv run $D python harness/mapper.py 'base16/nord' --set landmark --mode A   # one palette
uv run $D python harness/score_palettes.py                       # -> out/palette_scores.{csv,md}, ~1-2 min on 16 cores
uv run --with pyyaml python harness/ladder.py                    # -> out/ladder.md (H8), < 1 s
uv run $D python harness/generate.py spec.txt --name my-theme    # -> my-theme-theme.el, ~20 s
uv run $D python harness/test_generate.py [--fast]                # generator tests (~30 s; --fast < 1 s)
```

- `generate.py` writes the most readable reader theme for a background, a foreground and a hue name
  (or a hex) per family. A trailing `?` marks type/meta optional. The spec is `Key value` lines or
  `key=value` arguments. Every candidate is scored by `map_reader` mode C, so the
  `reader-theme-deftheme` it writes derives the same way in Elisp. The docstring gives the search and
  the score.

- `colour.py` is the metric library: OKLCH, ΔE_OK and ΔE00, the Szafir line model `de_text`, D1–D4,
  L-tiers, APCA (from `apca.py`), CVD simulation (Machado for deutan/protan, Brettel for tritan,
  full severity, gamut-fitted), hue names (OKLCH bins documented in the module), and salience.
- `mapper_common.py` loads the pattern sets (it resolves `inherits`), roles, weights, ink share,
  adjacency (`adjacent_skip_punct`, lang ALL) and lexical separability. It also holds the static
  channel model, the beacon-loss term and λ. `SETS = [landmark, hybrid, label, landmark_v1, hybrid_v1, reader]`.
  Draft 2 sets (landmark, hybrid) are recognised by their `loud` tier and rank families by `keep`
  (higher = kept longer); draft 1 sets use `ladder` (lower = dropped first). Both mean "ascending =
  dropped first". Quiet roles of a dropped family go to `quiet_fallback`, else default.
- `mapper.py` implements framework §4. Its docstring gives the exact algorithm, objective and the
  mode B habit table. `reserve_diag` defaults to OFF (red may be used for syntax); with it on, the error colour (base08 / ANSI red)
  and every accent not D2 from it are kept out of syntax. `score_palettes.py` headline = off, with the on setting as a sensitivity section.
- Confusion cost is reported twice: raw (Σ adjacency × w) and discounted (× (1 − separability)).
  H8 and H12 are judged on the discounted version.

### Draft 2 (patterns/landmark.yaml, hybrid.yaml)

```sh
uv run --with pandas --with numpy --with scikit-learn --with pyyaml python harness/recoverability.py   # rerun after any roles.yaml change
uv run --with pyyaml python harness/static_checks.py
uv run $D python harness/score_palettes.py     # ~70 s on 16 cores; 5 sets x {A,B} reserve off (headline) + 5 sets x B reserve on (sensitivity)
uv run --with pyyaml python harness/ladder.py
uv run --with tree-sitter --with tree-sitter-language-pack --with pandas --with pyyaml $D python harness/render.py
```

- Tiers (`mapper.dim_faded`, `quiet_colour`, `spare_accent`): **loud** = accent with OKLCH C ≥ 0.08
  after derivation (only loud/strong use counts against capacity); **strong** = loud + bold;
  **quiet** = the family accent, chroma reduced (OKLab mix toward fg, or OKLCH at fg's L) into
  [0.03, 0.08], |Lc| within 15 of fg, D1 floor from fg, dim and the other quiet colour; the most
  fg-like passing colour is used, else `quiet_fallback`/default (recorded in the theme JSON `quiet`);
  **dim** = mix(fg, bg) to |Lc| min(45, fg − 10), C ≤ 0.04; **faded** = |Lc| 30 (down to 15) and D1
  floor from dim; **popout** = bold + the most chromatic reserved-safe accent whose hue name is unused,
  else fg bold. Theme JSON gains `version`, `tiers`, `quiet`, `popout`; `roles` keep the same keys.
- D2 between hue families needs a different hue **name** (`colour.d2(strict_name=True)`), so
  reserve_diag reserves the whole error hue name. Draft 1 sets keep the old D2.
- Salience (`colour.salience_v2`, all sets): a·max(0,|Lc|−|Lc_fg|)/100 + b·C/0.15 + c·bold −
  d·max(0,|Lc_fg|−|Lc|)/100, a = d = 1, b = 0.5, c = 0.15; derivation of b in colour.py. S1 = every
  adjacent pair of declared tiers in use holds with margin 0.075.
- C6 = pair confusion + λ·Σ beacon·ink·loss; λ (`mapper_common.beacon_lambda`) equalises the two
  terms for "drop every family" on draft-2 landmark (λ_disc ≈ 0.0018, λ_raw ≈ 0.40).
- Draft 1 reproducibility: landmark_v1/hybrid_v1/label map exactly as before. The exception is mode-B
  ties (≤ 2% of mode-B rows): these used to be broken by set-iteration order, which depends on
  PYTHONHASHSEED, and are now broken by YAML drop order. Discounted costs moved slightly because
  recoverability was rerun after the docstring → comment.doc move.
- `render.py`: columns plain / landmark A / landmark B / hybrid A / label B / landmark_v1 A; tasks
  use plain / landmark A / label B. Local `variable.def` renders as `variable.use`. Results: `out/draft2_results.md`.

### Draft 2.1 (landmark.yaml / hybrid.yaml "2.1" changes)

Same commands as Draft 2 (note: in zsh write the `uv run --with ...` flags out in full; `$D` is not word-split). Results: `out/draft21_results.md`.

- Quiet: C in [0.05, 0.09] (read from `tiers.quiet.chroma`), D1 reliable vs fg, dim and other quiet colours; failures recorded in `theme.quiet`.
  `quiet_fallback {tier: quiet, family: any_kept, else: default}` -> `effective_styles` marks roles `quiet_borrow`; the mapper picks the kept accent with the best D1 margin (`theme.quiet_borrow`, `theme.strings_quiet` = own/borrowed/none).
- Dim: `below_default` 10 beats the lc target; `theme.tiers.fg_limited` = |Lc fg| < 50.
- CVD capacity (draft-2 sets): D1 reliable between loud accents and vs fg; name rule only under normal vision. H9: normal all 4, deutan/protan >= 3.
- Headline mode is B (`score_palettes.HEAD`); reports show A too. S1 = S1a (|Lc| faded < dim < default) and S1b (OKLCH C quiet < loud, margin 0.03; `mapper.s1_ab`); the old salience S1 is kept as `S1_sal`.
- Separable cost: `mapper_common.unseparated_pairs()` (pairs no set separates) are excluded in the `*_sep` columns.
- Render: cell meta shows the string outcome (own / borrowed).

### Creator assignment (mode C)

- `map_palette(p, setname, mode='C', assign={family: slot})`: hue assignment belongs to the theme creator. Each family takes its assigned
  slot's colour, lightness-derived toward the tier target (fidelity cap 0.05); no ladder drops, no capacity check. Quiet / dim / faded / popout
  derivation is unchanged. If `assign` is omitted it is read from `harness/assignments.yaml` (set -> palette id -> {family: slot}).
  Label only: optional `string_override: slot` colours the `string` role from that slot (theme.string_override).
- The theme JSON gains `assign` and `conformance`: per loud family pair `d2_normal`, `d1_reliable_deutan`, `d1_reliable_protan`, `ok`; `L2` per family
  (strict/default/floor/fail; `L2_ok` = not fail); `quiet_value_ok` (string tint exists); `dim_ok`; `failures` (list) and `conforms`.
- `assignments.yaml` mirrors each theme's own choices for gruvbox-dark-medium, monokai, kanagawa, zenburn (landmark and label).
- `render.py` now renders those four palettes with columns plain / landmark C / label C (conformance line under each landmark cell); tasks use
  the same three conditions. `render.py --sample` restores the old stratified random sample with the A/B columns.

### Draft 3 (patterns/reader.yaml: "label quietly, landmark loudly")

```sh
D="--with coloraide --with pyyaml --with numpy --with scipy"   # write out in full under zsh
uv run --with coloraide --with pyyaml --with numpy --with scipy python harness/mapper.py base16/zenburn --set reader --mode C
uv run --with coloraide --with pyyaml --with numpy --with scipy python harness/parse_load.py      # -> out/parse_load.{csv,md}, ~30 s
uv run --with coloraide --with pyyaml --with numpy --with scipy python harness/score_palettes.py  # reader now in SETS, ~2 min
uv run --with tree-sitter --with tree-sitter-language-pack --with pandas --with pyyaml \
    --with coloraide --with numpy --with scipy python harness/render.py
```

Results: `out/draft3_results.md`.

- `mapper_common`: `is_v3(s)` = the set has a `recessive` tier. Fallbacks come only from the YAML (`families.<f>.fallback`; reader: type → callable, meta → syntax loud). A fallback `{family: g, tier: T}` re-tiers only the quiet and recessive roles
  (meta macro.call quiet → syntax loud); strong roles stay strong. A dropped family with no fallback sends its
  quiet/recessive roles to default. `bold_if: top-level` = bold + `scope: top-level` (locals render as variable.use).
- `mapper.map_reader` (via `map_palette` when `is_v3`):
  **recessive** = accent hue in OKLCH, |Lc| 6–18 below fg, C in [0.04, 0.12] after gamut fit, D1-reliable from fg, dim,
  faded and the family's loud accent; picks the point with the largest de_text(p=.8) from fg (`theme.recessive`,
  `outshines_loud` = salience above the loud accent).
  **quiet** = `quiet_joint`: one candidate grid per family (accent hue, C in [0.05, 0.10], |Lc − Lc_fg| ≤ 12,
  D1-reliable from fg, recessive and dim), then a coordinate search for all families at once. The objective is
  lexicographic: pairwise violations, then min margin capped at 0.2, then closeness to fg. If a pairwise violation
  remains, the family involved in the most violations fails (ties: lowest keep) and the search reruns.
  Failed cues fall to default ink (`theme.quiet[f].reason`).
  **Shedding / conformance**: R0 → R1 (meta → syntax loud) → R2 (type → callable), then R3 (failing quiet → default),
  R4 (recessive → default), else `none`. Mode C tries R0..R2. In modes A/B, capacity sets the first level tried (5/4/3
  hues; fewer → ladder, `none`). `theme.level` uses the full loud check (D2 normal + D1-reliable deutan/protan, L2, dim);
  `theme.level_normal` ignores CVD. For `none`, the theme returned is the first level tried; `levels_tried` lists each
  level's failures.
  Mode B habits: `syntax` = keyword habits.
- `parse_load.py`: reading classes, look-alike clusters (same bold/italic and not D1-reliable, union-find, optionally
  CVD-simulated), H(class | cluster) and ambiguous tokens per screen from out/role_stats.csv lang=ALL; with and
  without punctuation. Themes: plain plus landmark/label/reader C on the 4 creator palettes, and landmark/label/reader
  B on all palettes; finding metrics from `evaluate` alongside.
- `render.py`: columns plain / landmark C / reader C / label C (the reader cell shows level, recessive and quiet
  outcomes). tasks.html uses the same 4 conditions with 4 snippets per language (Latin square), 36 trials.
- `evaluate`: S1a also orders recessive below fg; `ink_split` gains `recessive`.

### Draft 3.1 (patterns/reader.yaml "draft 3.1")

Same commands as Draft 3 (score_palettes.py, parse_load.py, render.py; under zsh write the `--with` flags out in full). Results: the
"Draft 3.1" section of `out/draft3_results.md`.

- The mapper reads reader tier parameters from the YAML: `tiers.quiet.chroma`, `tiers.recessive.chroma|below_default`, and the
  `distinct_from` lists (recessive: `dim`, `faded`, `own_loud`; quiet: `dim`, `recessive`). `QUIET3_C`, `REC_C` and `REC_BELOW` are only defaults.
  `SET_FALLBACKS` is gone. `keyword.exit` is `strong` (bold).
- `outshines_loud` counts the exit's bold term; `outshines_loud_nobold` keeps the draft-3 definition.
- Other sets are unchanged: landmark/label/hybrid/v1 rows of `out/palette_scores.csv` and landmark/label rows of `out/parse_load.csv` are byte-identical to the draft-3 run.

### Draft 3.2 (patterns/reader.yaml "3.2": optional binding tint, Rust `?` exit, faded commented-out code)

Same commands as Draft 3, plus the Job C reruns (role_tokens -> role_stats -> adjacency). Results: `out/draft32_results.md`.

```sh
uv run --with tree-sitter --with tree-sitter-language-pack --with pandas --with pyyaml python harness/test_comment_code.py   # heuristic unit tests
uv run --with pandas python harness/comment_code_samples.py                                                                   # -> out/comment_code_samples.md
```

- `role_tokens.py`: Rust `?` (an `@operator` in `try_expression`) -> keyword.exit; `@comment` segments passing `is_commented_code()` -> `comment.code`.
  The heuristic is a small function (docstring lists the tightenings over roles.yaml's one-liner); `test_comment_code.py` holds the examples.
  role_stats / adjacency treat comment.code as a partition of `comment`; `mapper_common.ink_shares()` and `adjacency()` fold it back into `comment`
  for sets without a comment.code style, so other sets' inputs are unchanged. `comment_code_samples.py` draws 10 seeded examples per language.
- `mapper_common.hue_families` skips families marked `optional` (binding): outside the hue cap, capacity and shedding.
- `mapper.map_palette(..., options={'binding': slot | 'auto' | None, 'fade_commented_code': bool})`, both off by default (reader only).
  Implemented by `mapper.apply_options(theme, p, options)` on a finished theme: binding = quiet tint for `parameter` via `quiet_joint`,
  avoiding recessive, dim and every other quiet colour (`theme.binding` reports margins, D1-reliable flags, hue gap; `auto` picks the slot);
  fade = `comment.code` in the faded tier. `mapper.load_binding_slot(set, palette)` reads `binding:` from `assignments.yaml` (reader section; the
  key is popped from `assign` so it is never a hue family).
- `parse_load.py`: variants reader+binding / reader+fade / reader+both (mode C creator slot; mode B `auto`). Every row has `H_p` / `ambiguous_p`
  (parameter as its own reading class, variant analysis); `H` / `ambiguous` keep the original classes. Columns `bind_ok`, `bind_slot`, `bind_gap`, `bind_d1_all`.
- `render.py`: columns plain / landmark C / reader C / reader C + options (creator binding slot + faded commented code); comment.code renders as comment in
  sets without that role. Snippet choice favours Rust windows that contain a `?` exit. tasks.html is unchanged (4 conditions).
