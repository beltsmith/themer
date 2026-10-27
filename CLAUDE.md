# CLAUDE.md

themer is an Emacs package for developing colour themes (live preview, SVG
rendering), plus the **reader** standard for colouring source code and the
tooling to generate and edit themes on it. `research/` holds the research
behind the standard; the package implements it.

## Layout

| Path | What |
|---|---|
| `themer.el` | Entry point; requires the rest |
| `themer-preview.el` | `themer-preview-mode`: live reload + swatch painting (autothemer, and macros registered in `themer-preview-forms`) |
| `themer-render.el` | `themer-render`, `themer-render-compare`, headless `themer-batch-render FILE OUT.svg [SETTLE] [LINES]` |
| `themer-colour.el` | Colour maths: OKLab/OKLCH, CIELAB, APCA, Szafir text-size ΔE, gamut fit, CVD simulation |
| `themer-reader.el` | The standard: `themer-reader-deftheme`, palettes, tier derivation, conformance, face mapping, UI accent, `themer-reader-treesit-mode` rules, export, theme load path |
| `themer-picker.el` | `themer-picker-adjust`: adjust the hex at point/region in OKLCH, in place |
| `themer-reader-form.el` | Widget form (`themer-reader-new-theme` / `-edit-theme`), sample buffer |
| `samples/` | `sample.EXT` code samples the theme form fontifies; discovered by name, modes from `auto-mode-alist` |
| `examples/` | Reader themes: blush (the main example, `full+cvd`) and four ports (gruvbox, monokai, kanagawa, zenburn) + renders |
| `tests/themer-test.el` | ERT suite, including byte-compile-clean and checkdoc-clean tests |
| `research/PATTERNS.md` | The normative standard (MUST/SHOULD). Source of truth for behaviour |
| `research/patterns/*.yaml` | Machine-readable roles (`roles.yaml`) and pattern sets (`reader.yaml` is current) |
| `research/00-framework.md` | Vocabulary, hypotheses, and the record of each design revision |
| `research/harness/` | Python reference implementation and measurements (see its README) |
| `server/` | Web server: the research pages plus the timed task (`/task`); reports go to S3 (see its README) |

## Source of truth and parity

- Behaviour follows `research/PATTERNS.md` and `research/patterns/reader.yaml`.
  Change the spec first, then the code, and keep them in sync.
- The Elisp colour maths and tier derivation must match the Python reference
  (`research/harness/colour.py`, `mapper.py` mode C) **exactly**. Tests assert
  this for the example palettes, so a change on one side needs the same
  change on the other.
- Design priority from user review: **reading at a glance beats finding**.
  The earlier "landmark" design optimised search metrics and was rejected
  as unreadable; don't regress toward colouring only landmarks.
- Hue assignment is the theme creator's choice. Only red = error
  (diagnostic layer) and green/red = diff (backgrounds) are fixed, and red
  may also be used for syntax.

## Commands

```sh
# Full test suite (≈6 s). Must stay green, including byte-compile/checkdoc.
emacs --batch -L . -l tests/themer-test.el -f ert-run-tests-batch-and-exit

# Render a file region with a theme to PNG
emacs --batch -L . -l themer -l setup.el -f themer-batch-render FILE out.svg 3 301-332
rsvg-convert out.svg -o out.png
```

Research harness (from `research/`; deps via `uv run --with ...`, exact
commands in `research/harness/README.md`):

- `bash harness/fetch_sources.sh` once: clones the palette corpus, code
  corpus and queries into `data/` (git-ignored, ~350 MB; only derived outputs
  are committed).
- After a `roles.yaml` change: `role_tokens.py` → `role_stats.py` →
  `adjacency.py` → `recoverability.py`, then `score_palettes.py`,
  `parse_load.py`, `render.py`.
- `render.py` regenerates `out/renders/tasks.html`, which `server/` serves. A
  changed trial set changes the reports' `trials_version`.
- Under zsh, an unquoted `$VAR` holding several `--with` flags isn't
  word-split; use an array (`W=(--with a --with b); uv run $W ...`).

## Elisp conventions

- `lexical-binding: t`, `themer-` prefix (`themer-reader-` / `themer-colour-`
  per file, `--` for internals), defcustoms in group `themer`, Emacs 29.1+.
  Terse docstrings and comments, matching the existing files.
- **Special variables from other libraries must be declared** (`(defvar
  treesit-font-lock-level)`) before `let`-binding them. Otherwise the
  binding is lexical and silently does nothing.
- The standard colours level-4 tree-sitter features (calls etc.). Code that
  fontifies samples binds `treesit-font-lock-level` to 4 around the mode
  setup **and** `themer-reader--install`, which recomputes features.
- Every tree-sitter query must compile against the installed grammars; the
  tests check this.
- Reader themes are found by `load-theme` only because loading
  `themer-reader` puts `themer-reader-theme-directory` and `examples/` on
  `custom-theme-load-path`. Keep that working (it's tested).
- The straight recipe needs `:files (:defaults "examples" "samples")`; documented in
  the README. Update the README Installation section if packaging changes.

## Working in the user's Emacs

- Prefer `emacsclient` for evaluation (the user's `emacs-skills:emacsclient`
  skill); `emacs --batch` is fine for tests and headless rendering.
- The live session is the user's real editor. Leave no themes enabled,
  frames, buffers or hooks behind; restore `custom-enabled-themes`. Never
  change `custom-safe-themes`. Reload changed `.el` files when done.
- Don't leave `.elc` files in the repo.

## Git

- Work is tracked in GitHub issues (`gh`); reference them in commits
  (`Closes #N`).
- Commit only when asked. Commit messages: a short summary line, then a body
  explaining what and why.
