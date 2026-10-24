# themer

Tools for developing an Emacs colour theme while you look at it.

## Installation

With [straight.el](https://github.com/radian-software/straight.el):

```elisp
(straight-use-package
 '(themer :type git :host github :repo "beltsmith/themer"
          :files (:defaults "examples")))
(require 'themer)
```

Or with `use-package`:

```elisp
(use-package themer
  :straight (themer :type git :host github :repo "beltsmith/themer"
                    :files (:defaults "examples"))
  :demand t)
```

`:files` has to include `examples` for the example themes (reader-gruvbox,
-monokai, -kanagawa, -zenburn) to be available. Load the package eagerly
(`require` or `:demand t`): loading it is what puts your theme directory
and the examples on `custom-theme-load-path`, so until then reader themes
don't show up in `load-theme` or `consult-theme`.

## `themer-preview-mode`

Turn it on in a `<name>-theme.el` buffer. After each edit, saved or not, it
re-evaluates the buffer and re-enables the theme (after
`themer-preview-delay`, 0.4s idle by default), so changes to a palette hex
or a role binding show up in every window straight away.

For [autothemer](https://github.com/jasonm23/autothemer) themes, it also
paints each palette and role name with the colour it resolves to, both
where it's defined and wherever a face spec uses it, so you can read the
role → colour mapping straight off the buffer.
In a `themer-reader-deftheme` form it paints each hex string of the spec,
each palette entry's name, and each slot that names a palette entry.

- Unbalanced parens mid-edit are skipped.
- If evaluation fails, the previous face settings are restored.
- Turning the mode off removes the swatches. It also disables the theme
  if the theme wasn't already enabled when you turned the mode on.

## `themer-render`, `themer-render-compare`

Render the faces Emacs actually resolved in a buffer (font-lock,
tree-sitter, eglot semantic tokens, all of it) to an SVG. The colours come
from the live face pipeline, not a hand-tagged sample, so the image shows
exactly what the theme does to real code, including the places where one
layer overrides another.

- `themer-render` renders the region, or the visible window if no region
  is active.
- `themer-render-compare` renders font-lock alone next to font-lock plus
  eglot semantic tokens, and underlines every character whose look the
  tokens changed. Use it to spot a semantic-token face clobbering a more
  specific tree-sitter face.

The image opens in `*themer-render*`; press `w` there to write the SVG.

### Headless

```sh
emacs --batch -L path/to/themer -l themer -l setup.el \
      -f themer-batch-render FILE OUT.svg [SETTLE-SECONDS] [LINES]
```

`setup.el` loads the theme and sets whatever the render depends on:
`treesit-font-lock-level`, the major mode for `FILE`, and
`eglot-server-programs`. If a server is configured for `FILE`'s mode, batch
mode starts eglot itself, waits `SETTLE-SECONDS` (default 3) for the server
to index, and renders the comparison. Otherwise it renders font-lock alone.
Slow-indexing servers such as rust-analyzer need around 20–25 seconds.
`LINES` (for example `301-332`) renders only that range. The whole file is
still parsed, so tree-sitter sees the full context.

To get a PNG: `rsvg-convert OUT.svg -o OUT.png`.

## Reader themes

`themer-reader.el` generates themes on the **reader** standard for colouring
source code ([research/PATTERNS.md](research/PATTERNS.md), draft 3.2):
"label quietly, landmark loudly". Hue means the *kind* of token, lightness
and chroma mean importance, and bold marks landmarks. Keywords take a
recessive tint below default ink, calls, types and strings take quiet tints
near default ink, and definitions, exits and literals are loud. Variables
stay in default ink, so the logic stands out.

You choose one accent per kind family. Every tier is derived from it, the
way the reference mapper does it (`research/harness/mapper.py`, mode C).

### Quick start

`M-x themer-reader-new-theme` opens a form for a new theme, empty (seeded
with your current background and foreground) or seeded from a reader theme
you pick by name. `M-x themer-reader-edit-theme` opens the same form on an
existing theme: the current buffer's theme file, or one picked by name from
the reader themes on `custom-theme-load-path` and in
`themer-reader-theme-directory`.

The form has a field for the name and the description, the **palette**
(see [Palettes](#palettes)), and a field for each slot: `:bg`, `:fg`, the
five family accents, the optional parameter tint, popout and UI accent, and
the four conventions. Each slot has:

- an editable field holding a palette name or a raw hex, and a **Pick**
  button (the palette menu, below);
- a swatch: the colour as a block, and as text on the theme's background;
- a short status from the conformance result, for example `fails Lc 35
  (Lc 28.4)`, `quiet tint: not distinct from another quiet tint`,
  `CVD-confusable with callable` or `shed at R2: drawn as callable`.

Below the fields are the derived tiers (recessive, quiet, loud and strong
per family, plus default, dim, faded, the parameter tint and popout, each
with its hex and Lc), and the conformance level with each MUST and SHOULD.

### Samples

The code samples have their own buffer, `*themer-reader-sample: NAME*`
(read-only; `g` refreshes, `q` quits the window). The form opens in the
selected window, and the samples split off it: to the right when the window
is wide enough for both (about 180 columns), else below. A rule in
`display-buffer-alist` overrides that. It
redraws on every re-derive, keeping its window's point and scroll, and is
killed with the form. If you close its window, the form's **Show samples**
button brings it back.

There are samples for TypeScript, Python, Rust, C, Go and Emacs Lisp, each
exercising the standard's roles: keywords, exits, calls, types, function
definitions, module-level bindings and constants, parameters, literals,
strings with escapes, comments, a doc comment, a TODO, commented-out code,
and macros, decorators and attributes. Each is fontified by its real major
mode: the tree-sitter mode if its grammar is installed, else the classic
mode (`rust-mode`, `go-mode`, ...); a language with neither shows a one-line
note. `themer-reader-treesit-mode`'s rules apply as well. The form's
**Samples** section has a checkbox per language; ticking one updates the
sample buffer at once, without re-deriving. The choice lasts for the
session and starts from `themer-reader-form-sample-languages`. Add a
language to `themer-reader-form-samples`, an alist of
`(LANGUAGE (MODE...) . CODE)`:

```elisp
(add-to-list 'themer-reader-form-samples
             '(ruby (ruby-ts-mode ruby-mode) . "def hi = puts(\"hi\")"))
```

### Editing

Edits re-derive after `themer-preview-delay` idle seconds, and only when a
colour changed. Deriving takes about a second; typing during it cancels
and reschedules it. **Apply** enables the theme globally for a live
preview. Turning it off, or killing the form, restores the themes that
were enabled before.

The buttons are **Save**, **Export standalone**, **Import base16** (it
asks which slot each field takes, with defaults from the base16 conventions
and the slots' hue names), **Revert** and **Check** (the full report). TAB
and S-TAB move between fields, `C-c C-c` saves and `C-c C-k` cancels.

Save writes `:palette` and the slots' references as they are, so a theme
file read and saved unchanged is byte-identical. It writes
`NAME-theme.el` next to the file you edited, or to
`themer-reader-theme-directory` for a new theme. When you edit a file, its
header comment and key order are kept; a renamed theme gets the new name in
its header and footer lines. The file looks like this:

```elisp
(require 'themer-reader)

(themer-reader-deftheme reader-gruvbox
  "Gruvbox dark, medium (base16), on the reader standard."
  :palette ((bg "#282828")
            (fg "#d5c4a1")
            (red "#fb4934")
            (yellow "#fabd2f")
            (green "#b8bb26")
            ...)
  :bg bg
  :fg fg
  :syntax red
  :callable green
  ...)
```

Themes appear in `load-theme` and `consult-theme`: loading `themer-reader`
puts `themer-reader-theme-directory` (without creating it) and, with
`themer-reader-include-examples`, the package's `examples/` on
`custom-theme-load-path`, and Save adds the directory of a theme saved
anywhere. `(load-theme 'reader-gruvbox)` asks you to confirm the theme as
usual; `custom-safe-themes` is not touched.

`examples/` has four themes like this, built from the creator assignments
in `research/harness/assignments.yaml`: gruvbox, monokai, kanagawa and
zenburn. Each palette holds the theme's full base16 set under the theme's
own colour names (kanagawa's `sumiInk1`, `fujiWhite`, `oniViolet`…;
zenburn's `red+1`, `yellow-1`…), used or not. `examples/renders/` shows
each one on Go, TypeScript and Rust snippets from the research corpus.

### Palettes

A palette defines each colour once, by name. `:palette` is an ordered
list of `(NAME "#rrggbb")` entries, with any symbol as a name (except `t`,
`nil` and keywords). Every slot then takes either a palette name or a hex
string, so themes without a palette still work:

```elisp
(themer-reader-deftheme my-theme "Doc."
  :palette ((ink "#1d1f21") (paper "#c5c8c6") (red "#cc6666"))
  :bg ink :fg paper :syntax red :callable "#81a2be" :value "#b5bd68")
```

Names are resolved before anything is derived (`themer-reader-resolve`),
and an unknown name is an error that names the slot. Derivations are
cached on the resolved colours, so a palette theme and its hex-only twin
share one entry. Editing an entry's hex and re-evaluating (or
`themer-preview-mode`) re-derives every slot that names it. Unused
entries are allowed.

In the form, the **Palette** section comes before the slots. Each entry
has an editable name and hex, a swatch on the theme's background, its hue
name and Lc, and the slots that use it, or "(unused)". Its buttons:

- **Pick**: a new colour with `read-color`;
- **Rename**: renames the entry and every slot that names it. Typing a
  new name into the name field does the same, once the name is usable and
  no other entry has it;
- **Delete**: deletes the entry. If slots use it, it asks first, and those
  slots then take its hex.

**Add**, under the entries, reads a colour and a name (default: its hue
name). Editing an entry's hex live-updates every slot that names it, the
tiers, the samples and the conformance checks.

A slot's **Pick** opens a menu of the palette entries, each annotated with
a swatch, its hex and its hue, plus **Custom hex…** (`read-color`; the slot
gets a raw hex) and **Add to palette…** (a hex and a name; the slot then
names the new entry). You can also type a name or a hex in the field.

**Import base16** fills the palette with the scheme's slots, `base00` to
`base0F` (or `base17` for base24), and asks which slot each field names:
`:bg` `base00`, `:fg` `base05`, and the families from the base16
conventions. Earlier entries that other fields still use are kept. A new
theme with no seed starts with a palette of the current `bg` and `fg`.

### Spec keys

Every colour key takes a palette name or a `"#rrggbb"` string.

| Key | | Used for |
|---|---|---|
| `:palette` | optional | `((NAME "#rrggbb") ...)`: named colours for the other keys |
| `:bg`, `:fg` | required | background, default ink (variables, parameters, fields, operators) |
| `:syntax` | required | keywords (recessive), exits: `return`, `raise`/`throw`, `break`, `continue`, `yield`, `goto`, Rust `?` (bold) |
| `:callable` | required | calls and builtins (quiet), function definitions (bold) |
| `:value` | required | strings (quiet), numbers, constants and escapes (loud) |
| `:type` | optional | type uses and modules (quiet), type definitions (bold) |
| `:meta` | optional | macro calls (quiet), decorators, attributes and preprocessor (loud) |
| `:binding` | optional | a quiet parameter tint. It never appears loud, so it isn't a sixth family |
| `:popout` | optional | TODO/FIXME/XXX ink. By default, the first fixed colour whose hue no family uses |
| `:accent` | optional | the UI accent (below). By default `:popout`, else the callable family's loud colour |
| `:error`, `:warning`, `:added`, `:removed` | optional | diagnostics and diffs. Defaults are a red, a yellow and a green for the background |

UI faces (region, `hl-line`, mode line, completion, diff and diagnostics)
come from OKLab mixes of `:bg` and `:fg` and the fixed colours.
Diagnostics are wavy underlines in the error and warning colours.

### UI accent

`:accent` is one colour for the chrome, never for syntax, so it doesn't
count as a family. It draws the cursor, minibuffer and shell prompts, the
current line number, key bindings (`help-key-binding`, `which-key`,
`embark`, `marginalia`), the buffer name and LSP status in the mode line,
the mode-line highlight box, `isearch` (the accent as background, bold,
in `:bg`-coloured text), the matching paren, completion matches
(`completions-common-part`, `orderless` group 0, `consult`), diff hunk
headers, and headings in `magit`, `org`, `outline`, `dired` and the
agenda. Two conformance lines check it (SHOULDs): Lc ≥ 60 on the
background, and Lc ≥ 60 for the `isearch` text on the accent. In the form
it is the **Accent** field under **UI**, with Pick, a swatch and a status.
The examples each set one, with the reason in a comment.

### Conformance

`M-x themer-reader-check` shows the report for the theme in the current
buffer, or for the enabled reader theme. It lists the derived tiers and
each MUST and SHOULD of PATTERNS.md §1–§4, and gives the level reached:

| Level | Meaning |
|---|---|
| `full+cvd` | every MUST, plus the loud accents stay reliably distinct under deutan and protan simulation |
| `full` | every MUST under normal vision |
| `R1` | meta is shed: its roles use the syntax family |
| `R2` | type is shed too: types use the callable family |
| `R3` | R2, with the quiet cues that fail set to default ink |
| `R4` | R3, with keywords in default ink as well |
| `none` | the loud families still fail at R2 |

The level is reached under normal vision, because the standard makes the CVD
rules SHOULDs. The faces follow that level. The example themes reach R2
(gruvbox, zenburn), R3 (monokai) and R1 (kanagawa). None meets the CVD
SHOULDs. These match the reference mapper.

`M-x themer-reader-export` writes a standalone `deftheme` with the colours
baked in and no dependency on themer. If the theme has a palette, the
entries the faces use are bound in a `let` and the faces name them
(`` `(default ((t :foreground ,fg :background ,bg))) ``), so the export
stays readable. With a prefix argument it adds a note
about the faces that need the rules mode.

### Tree-sitter rules

Emacs's tree-sitter modes don't separate exits from other keywords, or type
definitions from type uses. `themer-reader-treesit-mode` is a global minor
mode that adds `:override` font-lock rules to the tree-sitter modes for
python, javascript, typescript, tsx, rust, go, c, c++, java, lua and bash,
when the grammar is installed. The rules cover:

- exits (`themer-reader-exit`), including Rust's `?`;
- type definition names (`themer-reader-type-definition`);
- decorators, attributes and annotations (`themer-reader-meta`), and macro
  calls and definitions;
- parameter declarations (`themer-reader-parameter`);
- module-level variable bindings, bold default ink
  (`themer-reader-module-variable`), and constant definitions, strong in
  the value family (`themer-reader-constant-definition`). Locals keep the
  plain variable face;
- TODO, FIXME and XXX in comments (`themer-reader-todo`);
- commented-out code, drawn faded (`themer-reader-commented-code`). This
  one is only on when `themer-reader-fade-commented-code` is set. Detection
  is the harness's heuristic (`role_tokens.py`), about 88% precise on
  corpus samples.

"Top level" means not inside a function, method, lambda or closure, as in
the research corpus (`role_tokens.py`). Class bodies, namespaces and
top-level blocks count as top level. Which declarations count:

| Language | Module variable (top level only) | Constant definition |
|---|---|---|
| Python | assignment targets, including class bodies | ALL_CAPS targets at top level |
| JavaScript, TypeScript, TSX | `let`/`var` declarators, and `const` ones not named ALL_CAPS | top-level `const` named ALL_CAPS |
| Rust | `static mut` items | `const` items and non-`mut` `static` items, at any scope |
| Go | `var` specs | `const` specs, at any scope |
| C, C++ | file- and namespace-scope declarators (not prototypes) | top-level `const`/`constexpr` declarations (not a pointer to const); object-like `#define` with a value |
| Java | none: fields stay fields | `static final` fields, interface constants |
| Lua | `local` and global assignments | `local NAME <const>` (or `<close>`) at top level |
| Bash | assignments, `export`, `declare` | `readonly` or `declare -r` at top level |

ALL_CAPS is the research's test, `_?[A-Z][A-Z0-9_]+`. Most top-level
`const` in JavaScript and TypeScript are ordinary bindings (94% of
TypeScript locals are `const`), so only ALL_CAPS names count as constants.
A JS/TS declarator whose value is a function (`const f = () => ...`) is drawn
as a function definition. A `#define` with no value (include guards, feature
flags) stays a macro definition.

Loading a reader theme turns the mode on, unless
`themer-reader-enable-rules` is nil. A rule group whose query doesn't
compile against the installed grammar is skipped with a message.

### Limitations

- Module-level bindings and constant definitions need
  `themer-reader-treesit-mode` and a tree-sitter mode. Without it,
  `font-lock-variable-name-face` is plain default ink everywhere.
- C++ `static constexpr` class members and Java `final` instance fields
  are fields, so they aren't drawn as constant definitions.
- The tree-sitter rules only mark parameter *declarations*. Parameter uses
  get the binding tint only from eglot semantic tokens
  (`eglot-semantic-parameter`).
- Eglot semantic-token faces that would override tree-sitter's more
  specific faces are left empty. For example, eglot maps every
  `declaration` modifier to the function-name face.
- On muted palettes the quiet tints sit close to default ink, as the
  standard intends, and can be hard to see. Kanagawa's call tint is one
  example. Low-chroma palettes such as zenburn struggle most.
- Deriving a theme takes about a second. Results are cached per spec, so
  re-enabling an unchanged theme, or going back to an earlier colour in
  the form, is instant.

## Options

| Option | Default | |
|---|---|---|
| `themer-preview-delay` | `0.4` | Idle seconds before re-evaluating, or before the form re-derives |
| `themer-render-font-family` | `nil` | `nil` uses the `default` face's family |
| `themer-render-font-size` | `14` | Pixels |
| `themer-render-char-width` | `0.6` | Column width as a fraction of the font size |
| `themer-render-line-height` | `1.45` | Multiple of the font size |
| `themer-render-semtok-timeout` | `10` | Seconds to wait for semantic tokens |
| `themer-render-diff-colour` | `nil` | `nil` uses the `shadow` face |
| `themer-reader-theme-directory` | `themes/` in `user-emacs-directory` | Where new themes are saved, and searched by `themer-reader-edit-theme`. Put on `custom-theme-load-path` |
| `themer-reader-include-examples` | `t` | Put the package's `examples/` on `custom-theme-load-path` |
| `themer-reader-enable-rules` | `t` | Loading a reader theme turns on `themer-reader-treesit-mode` |
| `themer-reader-form-sample-languages` | `(typescript python rust c go elisp)` | Languages whose samples the form shows at first |
| `themer-reader-form-samples` | six built-in samples | Alist `(LANGUAGE (MODE...) . CODE)` of sample code; add your own |
| `themer-reader-fade-commented-code` | `nil` | Draw code-like comments in the faded tier |
| `themer-reader-italic-comments` | `nil` | Italic comments |

## Requirements

Emacs 29.1+. The reader rules need the tree-sitter grammars for the
languages you use. The semantic-token comparison needs the eglot that ships with
Emacs 31: it reads eglot's internal `eglot--semtok-state` to tell when
tokens have arrived.
