# 02 — Taxonomies crosswalk: token roles and design vocabulary

Researched 2026-10-23. Sources were fetched or read from local installs: Emacs 31.1 `font-lock.el`/`treesit.el`, Neovim 0.12.5 `:h treesitter-highlight-groups`, `:h group-name`, `:h lsp-semantic-highlight`, and Pygments `token.STANDARD_TYPES`. The full source list is at the end.
This note is descriptive. It does not judge which theme colours anything which way.

---

## 0. The systems in one paragraph each

| System | Unit name | Shape | Fallback model |
|---|---|---|---|
| **TextMate** scopes (1.x/2 manual, "Naming Conventions") | *scope* (dotted, e.g. `entity.name.function`) | 11 roots → dotted subdivisions; the last segment is often the language (`.c`). Nested `meta.*` scopes describe the surrounding structure. | Theme selectors match by **scope prefix**, plus descendant selectors (`meta.function-call entity.name.function`). The most specific selector wins. |
| **Tree-sitter / Neovim** captures (`:h treesitter-highlight-groups`; this list used to live in nvim-treesitter `CONTRIBUTING.md` and is now in Neovim core docs) | *capture* (`@function.method.call`) | About 90 standard names. `@x.y.z` is followed by an optional `.lang` suffix. | Dotted fallback: `@function.method.call` → `@function.method` → `@function`. The roots link to Vim groups by default. |
| **Helix** theme scopes | *scope* (`function.method`) | A tree-sitter-style tree that leans on TextMate words (`keyword.storage.type`, `constant.numeric`). | "Longest matching theme key wins." |
| **Zed** | *capture* | A flat-ish set of about 45 names (`@comment.doc`, `@variable.special`, `@preproc`, `@variant`, `@enum`). | Prefix fallback. |
| **LSP semantic tokens** (3.17; `label` added in 3.18) | *token type* + set of *token modifiers* | **One type, plus zero or more modifiers** (sent as a bit set). The type is *what the symbol is*; the modifiers are *facts about this occurrence or symbol*. | Clients map `type` and `type.mod` to styles. VS Code falls back to TextMate scopes, and Neovim exposes `@lsp.type.X`, `@lsp.mod.M` and `@lsp.typemod.X.M`. |
| **Emacs** font-lock faces | *face* (`font-lock-function-call-face`) | A flat list of 28 faces that use `:inherit` chains. Tree-sitter modes group rules into *features* and *levels* 1–4. | Face inheritance (`function-call` inherits `function-name`, and so on). |
| **Vim** standard groups (`:h group-name`) | *highlight group* | A two-level hierarchy of **12 preferred groups** and their **minor groups** (e.g. `Statement` ⊃ `Conditional`, `Repeat`, `Label`, `Operator`, `Keyword`, `Exception`). | Minor groups link to their preferred group by default. |
| **Pygments** | *token type* (`Name.Function.Magic`) | A tree under `Token` with about 85 standard types. | Style lookup walks parents (`Name.Function.Magic` → `Name.Function` → `Name`). |
| **JetBrains** `DefaultLanguageHighlighterColors` | *TextAttributesKey* (`DEFAULT_FUNCTION_CALL`) | About 45 language-neutral keys. Language plugins add keys that fall back to these. | Explicit fallback key (`FUNCTION_CALL` → `IDENTIFIER`, `INSTANCE_METHOD` → `FUNCTION_DECLARATION`, `REASSIGNED_LOCAL_VARIABLE` → `LOCAL_VARIABLE`). |
| **base16 / base24** | *slot* (`base0D`) | 16 (or 24) **palette** slots. 00–07 are a monotone ramp and 08–0F are accents, each with a suggested syntax use. | None. It is a palette with usage guidelines. |

---

## a) Crosswalk table

Legend: `—` means the system has no distinct name for the concept, so it falls into the parent shown in brackets, if any. LSP cells show `type` or `type+modifier`. The base16 column gives the slot that `styling.md` suggests, or the slot most builders use where the guide is silent (marked `~`). Nvim captures are written without the `@`.

### Identifiers: functions and calls

| Concept | TextMate | Tree-sitter (nvim) | Helix | LSP type (+mod) | Emacs face | Vim group | Pygments | JetBrains | base16 |
|---|---|---|---|---|---|---|---|---|---|
| Function **definition** name | `entity.name.function` | `function` | `function` | `function`+`declaration`/`definition` | `font-lock-function-name-face` | `Function` | `Name.Function` | `FUNCTION_DECLARATION` | base0D |
| Function **call** | `entity.name.function` within `meta.function-call` (convention; there is no root name for it) | `function.call` | — (`function`) | `function` (no modifier; calls are simply occurrences without `declaration`) | `font-lock-function-call-face` (29.1) | — (`Function`) | — (`Name.Function`, often just `Name`) | `FUNCTION_CALL` | base0D |
| Method definition | `entity.name.function` (+`.member` per VS Code map) | `function.method` | `function.method` | `method`+`declaration` | — (`function-name`) | — (`Function`; "also: methods") | — (`Name.Function`) | `INSTANCE_METHOD` / `STATIC_METHOD` | base0D |
| Method call | (as for function call) | `function.method.call` | — | `method` | — (`function-call`) | — | — | (as above) | base0D |
| Builtin / default-library function | `support.function` | `function.builtin` | `function.builtin` | `function`+`defaultLibrary` | `font-lock-builtin-face` | — | `Name.Builtin` | `PREDEFINED_SYMBOL` | base0C ("Support") |
| Magic / dunder method | — | — | — | — | — | — | `Name.Function.Magic` | — | — |
| Constructor | `entity.name.function.constructor` (common) | `constructor` | `constructor` | — (`class`/`method`) | — | — | — | — | ~base0A/0D |
| Macro (function-like, invocation or definition) | `entity.name.function.preprocessor` (VS Code map), `support.function.macro` | `function.macro` | `function.macro` | `macro` | `font-lock-preprocessor-face` | `Macro` / `Define` | — (`Comment.Preproc` for the directive) | — | ~base08/0E |

### Identifiers: variables and properties

| Concept | TextMate | Tree-sitter (nvim) | Helix | LSP type (+mod) | Emacs face | Vim group | Pygments | JetBrains | base16 |
|---|---|---|---|---|---|---|---|---|---|
| Variable **declaration** (binding site) | `variable.other` / `entity.name.variable` | `variable` | `variable` | `variable`+`declaration` | `font-lock-variable-name-face` | `Identifier` | `Name.Variable` | `LOCAL_VARIABLE` / `GLOBAL_VARIABLE` | base08 |
| Variable **use** (reference) | `variable.other.readwrite` | `variable` (no split) | `variable` | `variable` | `font-lock-variable-use-face` (29.1) | `Identifier` | `Name` | `LOCAL_VARIABLE` / `IDENTIFIER` | base08 or base05 |
| Variable that is **assigned to** or reassigned | — | — | — | `variable`+`modification` | — | — | — | `REASSIGNED_LOCAL_VARIABLE`, `REASSIGNED_PARAMETER` | — |
| Local vs global scope | — | — | — | — (some servers use off-spec `globalScope`/`local`) | — | — | `Name.Variable.Global`, `.Instance`, `.Class` | `LOCAL_VARIABLE` vs `GLOBAL_VARIABLE` | — |
| Parameter | `variable.parameter` | `variable.parameter` | `variable.parameter` | `parameter` | — (`variable-name`) | — (`Identifier`) | — (`Name.Variable`) | `PARAMETER` | base08 |
| Special parameter (`_`, `it`) | — | `variable.parameter.builtin` | — | — | — | — | — | — | — |
| Builtin variable (`self`, `this`, `super`) | `variable.language` | `variable.builtin` | `variable.builtin` | `variable`+`defaultLibrary` (inconsistent; many servers send `keyword` or `selfKeyword`) | `font-lock-builtin-face` / `font-lock-keyword-face` (mode-dependent) | — | `Name.Builtin.Pseudo` | `PREDEFINED_SYMBOL` | ~base08/0E |
| Field / property **declaration** | `variable.other.property`, `entity.name.variable.field`... | `variable.member` | `variable.other.member` | `property`+`declaration` | `font-lock-property-name-face` (29.1) | — | `Name.Property` (rare), `Name.Attribute` | `INSTANCE_FIELD` / `STATIC_FIELD` | ~base08 |
| Field / property **use** | `variable.other.property` / `variable.other.object.property` | `variable.member` | `variable.other.member` | `property` | `font-lock-property-use-face` (29.1) | — | — | (same) | ~base08 |
| Key in key/value literal (JSON, dict) | `support.type.property-name` (JSON grammar) | `property` | — (`variable.other.member`) | `property` | `font-lock-property-name-face` | — | `Name.Tag` (JSON lexer) / `Name.Attribute` | — | ~base0D/08 |
| Private member (`#x`) | — | — | `variable.other.member.private`, `function.method.private` | — | — | — | — | — | — |
| Static member | `storage.modifier.static` (keyword only) | — | — | `+static` | — | — | `Name.Variable.Class` | `STATIC_FIELD`, `STATIC_METHOD` | — |
| Event | — | — | — | `event` | — | — | — | — | — |
| Unused variable or binding | — | — | `comment.unused` | — (LSP *diagnostic* tag `Unnecessary`, not a token modifier) | — | — | — | (inspection "unused symbol") | base03 |

### Constants and literals

| Concept | TextMate | Tree-sitter (nvim) | Helix | LSP type (+mod) | Emacs face | Vim group | Pygments | JetBrains | base16 |
|---|---|---|---|---|---|---|---|---|---|
| Named constant / readonly binding | `variable.other.constant` | `constant` | `constant` | `variable`+`readonly` (property+`readonly` for const fields) | `font-lock-constant-face` | `Constant` | `Name.Constant` | `CONSTANT` | base09 |
| Builtin constant (`true`, `nil`, `None`) | `constant.language` | `constant.builtin`, `boolean` | `constant.builtin` (`.boolean`) | `variable`+`readonly`+`defaultLibrary`, or `keyword` | `font-lock-constant-face` | `Boolean` (⊂ `Constant`) | `Keyword.Constant` | `KEYWORD` / `PREDEFINED_SYMBOL` | base09 |
| Preprocessor constant (`#define X 1`) | `constant.other.preprocessor`, `entity.name.constant.preprocessor` | `constant.macro` | — | `macro` | `font-lock-preprocessor-face` | `Define` / `Macro` | — | — | — |
| Enum member / variant | `variable.other.enummember`, `constant.other.enum` | `constant` | `type.enum.variant` | `enumMember` | `font-lock-constant-face` (mode) | `Constant` | `Name.Constant` | (lang-specific) | base09 |
| Number | `constant.numeric` (`.integer`, `.float`, `.hex`) | `number`, `number.float` | `constant.numeric` (`.integer`, `.float`) | `number` | `font-lock-number-face` (29.1) | `Number`, `Float` (⊂ `Constant`) | `Number` (`.Integer`, `.Float`, `.Hex`, `.Bin`, `.Oct`) | `NUMBER` | base09 |
| Character literal | `constant.character` | `character` | `constant.character` | — (`string`) | — (`string`) | `Character` | `String.Char` | — (`STRING`) | base0B/09 |
| String | `string.quoted.{single,double,triple}`, `string.unquoted` | `string` | `string` | `string` | `font-lock-string-face` | `String` (⊂ `Constant`) | `String` (`.Single`, `.Double`, `.Heredoc`, `.Backtick`) | `STRING` | base0B |
| String escape (`\n`) | `constant.character.escape` | `string.escape` | `constant.character.escape` | — | `font-lock-escape-face` (29.1) | `SpecialChar` (⊂ `Special`) | `String.Escape` | `VALID_STRING_ESCAPE` / `INVALID_STRING_ESCAPE` | base0C |
| String interpolation delimiters (`${ }`) | `punctuation.section.embedded`, `meta.embedded` / `string.interpolated` | `punctuation.special` | `punctuation.special` | — | — | `Special` | `String.Interpol` | — | base0F ("embedded") / base0C |
| String affix / prefix (`f`, `r`, `b`) | `storage.type.string` | — | — | — | — | — | `String.Affix` | — | — |
| Regex literal | `string.regexp` | `string.regexp` | `string.regexp` | `regexp` | `font-lock-regexp-face` (29.1); `regexp-grouping-*` | — | `String.Regex` | — | base0C |
| Symbol / atom / keyword-literal | `constant.other.symbol` | `string.special.symbol` | `string.special.symbol` | — | `font-lock-constant-face` / `builtin` | — | `String.Symbol` | — | ~base09/0C |
| Path / URL literal | `string.other.link`, `markup.underline.link` | `string.special.path`, `string.special.url` | `string.special.path`, `.url` | — | `link` (not font-lock) | `Underlined` | — | — | base09 ("link URLs") |
| Date or other special literal | `constant.other` | `string.special` | `string.special` | — | — | — | `Literal.Date` | — | — |

### Types, namespaces and annotations

| Concept | TextMate | Tree-sitter (nvim) | Helix | LSP type (+mod) | Emacs face | Vim group | Pygments | JetBrains | base16 |
|---|---|---|---|---|---|---|---|---|---|
| Type **definition** name (class, struct, typedef) | `entity.name.type`, `entity.name.type.class`, `entity.name.class` | `type.definition` (typedef identifier), `type` | `type` | `class`/`struct`/`enum`/`interface`/`type`+`declaration` | `font-lock-type-face` | `Typedef` / `Structure` (⊂ `Type`) | `Name.Class` | `CLASS_NAME`, `INTERFACE_NAME` | base0A |
| Type **reference** / annotation | `entity.name.type`, `storage.type` (for primitive keywords) | `type` | `type` | `class`/`struct`/`type`... (no `declaration`) | `font-lock-type-face` | `Type` | `Name.Class` / `Keyword.Type` | `CLASS_REFERENCE` | base0A |
| Builtin / primitive type (`int`, `str`) | `storage.type` / `support.type` | `type.builtin` | `type.builtin` | `type`+`defaultLibrary` | `font-lock-type-face` (sometimes `builtin`) | `Type` | `Keyword.Type` / `Name.Builtin` | `KEYWORD` | base0A / base0E |
| Generic type parameter (`T`) | `entity.name.type.parameter` (TS grammar) | — (`type`) | `type.parameter` | `typeParameter` | — | — | — | — | base0A |
| Superclass in a declaration | `entity.other.inherited-class` | — | — | — | — | — | — | — | base0B (!) |
| Enum type | `entity.name.type.enum` | — | `type.enum` | `enum` | — | `Structure` | — | — | base0A |
| Interface / trait | `entity.name.type.interface` | — | — | `interface` | — | — | — | `INTERFACE_NAME` | base0A |
| Namespace / module / package | `entity.name.namespace`, `entity.name.type.module`, `support.other.namespace` | `module`, `module.builtin` | `namespace` | `namespace` | — (`type-face` or `constant-face` by convention) | — (`Identifier` or `Include`) | `Name.Namespace` | — | ~base0A/0D |
| Attribute / decorator / annotation | `meta.decorator`, `entity.name.function.decorator`, `storage.type.annotation` | `attribute`, `attribute.builtin` | `attribute` (also used for class attrs!) | `decorator` (3.17) | — (`preprocessor` or `builtin` by mode) | — (`PreProc`) | `Name.Decorator` | `METADATA` | base0D ("Attribute IDs")? ambiguous |
| Label (`goto`, loop label) | `entity.name.label` | `label` | `label` (also CSS `.class`!) | `label` (3.18) | — (`constant-face` by convention) | `Label` (Vim **misuses** this for `case`/`default`) | `Name.Label` | `LABEL` | — |
| Tag (HTML/XML element) | `entity.name.tag` | `tag`, `tag.builtin` | `tag`, `tag.builtin` | — | — | `Tag` (Vim's `Tag` is a jump target, not markup) | `Name.Tag` | `TAG` | base08 |
| Tag attribute name | `entity.other.attribute-name` | `tag.attribute` | `attribute` | — | — | — | `Name.Attribute` | `ATTRIBUTE` | base09 |
| Tag delimiters `<` `>` | `punctuation.definition.tag` | `tag.delimiter` | `punctuation` | — | — | — | `Punctuation` | — | base05 |
| HTML entity (`&amp;`) | `constant.character.entity` | `character.special` | — | — | — | `SpecialChar` | `Name.Entity` | `ENTITY` | base0C |
| Exception class name | — | — | — | — | — | — | `Name.Exception` | — | — |

### Keywords and operators

| Concept | TextMate | Tree-sitter (nvim) | Helix | LSP type (+mod) | Emacs face | Vim group | Pygments | JetBrains | base16 |
|---|---|---|---|---|---|---|---|---|---|
| Keyword (generic) | `keyword.other` | `keyword` | `keyword` | `keyword` | `font-lock-keyword-face` | `Keyword` / `Statement` | `Keyword` | `KEYWORD` | base0E |
| Keyword: conditional | `keyword.control.conditional` (common) | `keyword.conditional` (+`.ternary`) | `keyword.control.conditional` | `keyword` | — (`keyword`) | `Conditional` | — (`Keyword`) | — | base0E |
| Keyword: loop | `keyword.control.loop` (common) | `keyword.repeat` | `keyword.control.repeat` | `keyword` | — | `Repeat` | — | — | base0E |
| Keyword: return / yield | `keyword.control.flow` (common) | `keyword.return` | `keyword.control.return` | `keyword` | — | — (`Statement`) | — | — | base0E |
| Keyword: exception (`try`, `throw`) | `keyword.control.trycatch`/`.exception` (common) | `keyword.exception` | `keyword.control.exception` | `keyword` | — | `Exception` | — | — | base0E |
| Keyword: import / export | `keyword.control.import`, `keyword.other.import` | `keyword.import` | `keyword.control.import` | `keyword` | — | `Include` (⊂ `PreProc`!) | `Keyword.Namespace` | — | base0E |
| Keyword: coroutine (`async`, `await`, `go`) | `storage.modifier.async`, `keyword.control.flow` | `keyword.coroutine` | — | `keyword` (the *async* **modifier** applies to the declared function, not to the keyword) | — | — | — | — | base0E |
| Keyword: debug | — | `keyword.debug` | — | — | — | `Debug` (⊂ `Special`) | — | — | — |
| Keyword: declares a function (`def`, `fn`) | `storage.type.function` | `keyword.function` | `keyword.function` | `keyword` | — | — | `Keyword.Declaration` | — | base0E |
| Keyword: declares a type (`struct`, `class`, `enum`) | `storage.type.class`/`.struct` | `keyword.type` | `keyword.storage.type` | `keyword` | — | `Structure` (⊂ `Type`) | `Keyword.Declaration` | — | base0E |
| Keyword: variable declaration (`let`, `var`, `const`) | `storage.type` | `keyword` / `keyword.modifier` | `keyword.storage.type` | `keyword` | — | `StorageClass` | `Keyword.Declaration` | — | base0E |
| Keyword: modifier (`static`, `pub`, `final`, `mut`) | `storage.modifier` | `keyword.modifier` | `keyword.storage.modifier` | `modifier` (3.17 *type*, distinct from token *modifiers*) | — | `StorageClass` (⊂ `Type`) | `Keyword` / `Keyword.Reserved` | — | base0E |
| Word operator (`and`, `in`, `sizeof`) | `keyword.operator.{logical,word}` | `keyword.operator` | `keyword.operator` | `operator` or `keyword` | — (`keyword`) | `Operator` (⊂ `Statement`) | `Operator.Word` | `OPERATION_SIGN` | base0E |
| Pseudo keyword (contextual) | — | — | — | — | — | — | `Keyword.Pseudo` | — | — |
| Symbolic operator (`+`, `=`, `->`) | `keyword.operator` (`.arithmetic`, `.assignment`...) | `operator` | `operator` | `operator` | `font-lock-operator-face` (29.1) | `Operator` | `Operator` | `OPERATION_SIGN` | base05 |
| Negation char (`!`) | `keyword.operator.logical` | `operator` | `operator` | `operator` | `font-lock-negation-char-face` | — | `Operator` | — | — |
| Preprocessor directive (`#include`, `#if`) | `keyword.control.directive`, `meta.preprocessor` | `keyword.directive`, `keyword.directive.define` | `keyword.directive` | `macro`/`keyword` | `font-lock-preprocessor-face` | `PreProc`, `Include`, `PreCondit`, `Define` | `Comment.Preproc`, `Comment.PreprocFile` | — | base0E? (unspecified) |
| Shebang | `comment.line.number-sign.shebang` (common) | `keyword.directive` | — | — | `font-lock-comment-face` | `PreProc` | `Comment.Hashbang` | — | base03 |

### Punctuation

| Concept | TextMate | Tree-sitter (nvim) | Helix | LSP type (+mod) | Emacs face | Vim group | Pygments | JetBrains | base16 |
|---|---|---|---|---|---|---|---|---|---|
| Punctuation (generic) | `punctuation` (convention, not among the 11 roots) | `punctuation.*` | `punctuation` | — | `font-lock-punctuation-face` (29.1) | `Delimiter` (⊂ `Special`, "character that needs attention") | `Punctuation` | — | base05 |
| Brackets `()[]{}` | `punctuation.section.*`, `punctuation.definition.*.begin/end` | `punctuation.bracket` | `punctuation.bracket` | — | `font-lock-bracket-face` (29.1) | `Delimiter` | `Punctuation` | `BRACES`, `BRACKETS`, `PARENTHS` | base05 |
| Delimiters `, ; . :` | `punctuation.separator`, `punctuation.terminator`, `punctuation.accessor` | `punctuation.delimiter` | `punctuation.delimiter` | — | `font-lock-delimiter-face` (29.1) | `Delimiter` | `Punctuation` | `COMMA`, `SEMICOLON`, `DOT` | base05 ("Delimiters") |
| Special punctuation (interpolation braces, `?` in ternary) | `punctuation.section.embedded` | `punctuation.special` | `punctuation.special` | — | `font-lock-misc-punctuation-face` (29.1) | `Special` | `Punctuation.Marker` | — | base0F/0C |

### Comments and documentation

| Concept | TextMate | Tree-sitter (nvim) | Helix | LSP type (+mod) | Emacs face | Vim group | Pygments | JetBrains | base16 |
|---|---|---|---|---|---|---|---|---|---|
| Comment | `comment.line.*`, `comment.block` | `comment` | `comment`, `.line`, `.block` | `comment` | `font-lock-comment-face` | `Comment` | `Comment` (`.Single`, `.Multiline`) | `LINE_COMMENT`, `BLOCK_COMMENT` | base03 |
| Comment delimiter (`//`, `/*`) | `punctuation.definition.comment` | — (`comment`) | — | — | `font-lock-comment-delimiter-face` | — | — | — | base03 |
| Doc comment | `comment.block.documentation` | `comment.documentation` | `comment.line.documentation`, `comment.block.documentation` | `comment`+`documentation` (the modifier is meant for *symbols inside* docs) | `font-lock-doc-face` (inherits **string**) | `SpecialComment` | `Comment.Special` (and `String.Doc`) | `DOC_COMMENT` | base03 (sometimes base04) |
| Docstring (string used as documentation) | `string.quoted.docstring`, `comment.block.documentation` | `string.documentation` | — | `string`+`documentation` (rare) | `font-lock-doc-face` | — | `String.Doc` | — | base03/0B |
| Doc markup / tags (`@param`, `{@link}`) | `storage.type.class.jsdoc`, `entity.name.type.instance.jsdoc` | — | — | `+documentation` on embedded symbols | `font-lock-doc-markup-face` (inherits **constant**) | `SpecialComment` | `Comment.Special` | `DOC_COMMENT_TAG`, `DOC_COMMENT_TAG_VALUE`, `DOC_MARKUP` | — |
| TODO / FIXME / NOTE in comment | — (grammar-specific) | `comment.todo`, `comment.note`, `comment.warning`, `comment.error` | — | — | — (hl-todo etc.; `font-lock-warning-face` in some modes) | `Todo` | — | (TODO pattern feature) | — |

### Errors, deprecation and generic text

| Concept | TextMate | Tree-sitter (nvim) | Helix | LSP type (+mod) | Emacs face | Vim group | Pygments | JetBrains | base16 |
|---|---|---|---|---|---|---|---|---|---|
| Error / invalid syntax | `invalid.illegal` | — (parser `ERROR` nodes are not captured; diagnostics instead) | `error` (UI/diagnostic) | — (diagnostics, not tokens) | `font-lock-warning-face` (inherits `error`) | `Error` | `Error`, `Generic.Error` | `INVALID_STRING_ESCAPE` (and the global `ERRORS_ATTRIBUTES`) | base08 (by ANSI convention) |
| Deprecated | `invalid.deprecated` | — | `diagnostic.deprecated` | `+deprecated` (modifier, any type) | — (`shadow`? none standard) | — | — | `DEPRECATED_ATTRIBUTES` (global) | base0F |
| Abstract | `storage.modifier.abstract` (keyword only) | — | — | `+abstract` | — | — | — | — | — |
| Async-declared | (keyword only) | — | — | `+async` | — | — | — | — | — |
| Plain / default text | (no scope) | `variable`/none | — | — | `default` | `Normal` | `Text`, `Name.Other`, `Token.Other` | `IDENTIFIER`, `TEXT` | base05 |
| Embedded language region | `meta.embedded`, `source.<lang>.embedded` | (injection) | — | — | — | — | `Token.Other` | `TEMPLATE_LANGUAGE_COLOR` | base0F |
| Diff added / removed / changed | `markup.inserted`, `markup.deleted`, `markup.changed` | `diff.plus`, `diff.minus`, `diff.delta` | `diff.plus/minus/delta` | — | `diff-*` faces (not font-lock) | `Added`, `Removed`, `Changed` (new in Vim 9.1 / Nvim 0.10) | `Generic.Inserted`, `Generic.Deleted` | — | base0B / base08 / base0E |
| Markup heading / bold / italic / code / quote / link | `markup.heading`, `.bold`, `.italic`, `.raw`, `.quote`, `.underline.link` | `markup.heading(.1-6)`, `.strong`, `.italic`, `.raw(.block)`, `.quote`, `.link(.label,.url)` | same as nvim, plus `markup.heading.marker` | — | (mode-specific, e.g. `markdown-*`) | `Title`*, `Underlined` | `Generic.Heading`, `.Strong`, `.Emph`, `.Subheading` | — | base0D / base0A / base0E / base0B / base0C / base08–09 |

### Notes on the cells
- **TextMate "(common)" cells** are de-facto conventions from widely used grammars (VS Code built-ins, Sublime's later scope naming guide). They are not part of the original 11-root list. TextMate's own list covers only `keyword.control`, `keyword.operator`, `keyword.other`, `storage.type` and `storage.modifier` for keywords.
- **The Vim `Label` group** describes `case`/`default`, not goto labels. That differs from every other system.
- **Vim `Statement`/`Keyword`.** `Statement` is the preferred group, and `Keyword` is a minor group for "any other keyword".
- **Vim `Include`** sits under `PreProc`, so `import` in modern languages gets preprocessor colouring by default. Neovim itself links `@keyword.import` → `Include`.
- **Emacs `doc-face` inherits `string-face`.** This reflects Lisp docstrings: docs are treated as a kind of string, while most other systems treat them as a kind of comment.
- **Emacs function-call and variable-use faces.** `font-lock-function-call-face` inherits `function-name-face`, and `variable-use` inherits `variable-name`. A theme that does nothing therefore keeps the pre-29 look. The use/call split is opt-in.

---

## b) Observations

### 1. The consensus core
Every system above, including base16's palette guide, names these concepts. These are the safe primitives:

| # | Concept | Evidence |
|---|---|---|
| 1 | **comment** | All 9 |
| 2 | **string** | All 9 |
| 3 | **number** (sometimes inside "constant") | All except base16, which merges it into constants |
| 4 | **keyword** | All 9 |
| 5 | **function name** | All 9 |
| 6 | **type / class name** | All 9 |
| 7 | **constant** (named or builtin) | All 9 |
| 8 | **variable / identifier** | All 9; Vim `Identifier`, Emacs `variable-name`, base16 base08 |
| 9 | **operator** | All but Emacs before 29 |
| 10 | **builtin / library-provided** (`support.*`, `*.builtin`, `defaultLibrary`, `font-lock-builtin-face`, `Name.Builtin`) | All but Vim |
| 11 | **preprocessor / macro** | All but base16 |
| 12 | **error / invalid** | All |

The **8 Vim preferred groups for code** (`Comment Constant Identifier Statement PreProc Type Special Error`, plus `Todo` and `Underlined`) are still a good minimal base vocabulary. Everything later refines them.

### 2. Near-consensus second ring (present in about 6 of 8 systems)
- **string escape** (TM `constant.character.escape`, ts `string.escape`, Emacs 29 `escape-face`, Vim `SpecialChar`, Pygments `String.Escape`, JetBrains `VALID_STRING_ESCAPE`, base0C).
- **regexp**, **parameter**, **property/field**, **namespace/module**, **attribute/decorator**, **doc comment**, **punctuation/delimiter**, and **label**.
- **Character literal** and **boolean** are consensus only in Vim, tree-sitter and Pygments. Elsewhere they fold into string or constant.

### 3. Recent additions: the *occurrence-role* axis
Older systems name **what a thing is** (kind). Newer systems also name **how this occurrence uses it** (role).

| Distinction | Where it appears | When |
|---|---|---|
| definition vs **call** of function | tree-sitter `function.call` / `function.method.call`; Emacs `font-lock-function-call-face`; JetBrains `FUNCTION_DECLARATION` vs `FUNCTION_CALL` | Emacs 29.1 (2023); the nvim-treesitter capture overhaul (2023–24, `@method` → `@function.method`, `@field` → `@variable.member`, `@parameter` → `@variable.parameter`, `@text.*` → `@markup.*`) |
| declaration vs **use** of variable | Emacs `variable-name-face` vs `variable-use-face` (29.1); LSP `declaration` modifier | 29.1 / LSP 3.16 |
| property name vs **property use** | Emacs `property-name-face` vs `property-use-face` (29.1) | 29.1 |
| **reassigned / mutated** | LSP `modification`; JetBrains `REASSIGNED_LOCAL_VARIABLE`/`PARAMETER`; rust-analyzer `mutable` (off-spec) | LSP 3.16 |
| **punctuation split** into bracket / delimiter / misc | tree-sitter `punctuation.{bracket,delimiter,special}`; Emacs 29 `bracket`/`delimiter`/`misc-punctuation`; JetBrains `BRACES/BRACKETS/PARENTHS/COMMA/DOT/SEMICOLON` | Emacs 29.1 |
| number, operator, escape, regexp as their own faces | Emacs 29.1 (before that they were usually unstyled or `constant`) | 29.1 |
| comment **severity** (todo/note/warning/error) | tree-sitter `comment.{todo,note,warning,error}` | 2023–24 |
| `decorator`, `modifier` (keyword) token types | LSP 3.17 | 2022 |
| `label` token type | LSP 3.18 | — |
| `Added`/`Changed`/`Removed` groups | Vim 9.1 / Nvim 0.10 `:h group-name` | 2024 |

**Takeaway.** Definition-vs-use and call-vs-definition are the main recent splits. Emacs, JetBrains and nvim all express them as **refinements that fall back to the kind**: `function.call` → `function`, and `variable-use` inherits `variable-name`. A role-agnostic theme keeps working unchanged.

### 4. The type/modifier split (LSP), and why it matters
- **The model.** LSP semantic tokens are explicitly **one type plus a set of modifiers**: "Tokens are represented using one token type combined with n token modifiers." Modifiers are bit flags, so they **combine freely**: a `variable` can be `readonly`+`static`+`defaultLibrary`+`declaration` at once.
- **Types (the *kind* axis, mutually exclusive).**
  - Symbol kinds: namespace, type, class, enum, interface, struct, typeParameter, parameter, variable, property, enumMember, event, function, method, macro, decorator, label.
  - Lexical kinds: keyword, modifier, comment, string, number, regexp, operator.
- **Modifiers (orthogonal axes).**
  - Occurrence role: `declaration`, `definition`, `modification`.
  - Mutability: `readonly`.
  - Binding or ownership: `static`, `abstract`, `async`.
  - Provenance: `defaultLibrary`.
  - Lifecycle: `deprecated`.
  - Context: `documentation`.
- **The hierarchical systems flatten this axis into the name**, so they cannot combine them:
  - "builtin" is a *child* (`function.builtin`, `variable.builtin`, `type.builtin`, `constant.builtin`, `module.builtin`, `attribute.builtin`, `tag.builtin`). In LSP it is one modifier, `defaultLibrary`, that applies to any type.
  - "call" is a child (`function.call`). In LSP it is the *absence* of `declaration`.
  - "constant" is a **kind** in TextMate, tree-sitter, Vim, Emacs and Pygments. In LSP it is a **modifier** (`variable`+`readonly`). This is the largest structural mismatch: is constness *what a thing is* or *a property it has*?
  - "deprecated" is a TextMate kind (`invalid.deprecated`) but an LSP modifier. Nvim and Helix treat it as a diagnostic.
  - TextMate splits `support.*` (provenance) as a **root**, so `support.function` and `entity.name.function` are siblings in different subtrees. Provenance outranks kind.
- **Practical consequence for patterns.** A palette-agnostic pattern language is easiest to state as **hue ← kind** and **attribute (weight/slant/underline/strike) ← modifier**. Examples: "deprecated → strikethrough on any kind", "declaration → bold", "readonly → its own hue or bold". Neovim exposes exactly this shape (`@lsp.type.*`, `@lsp.mod.*`, `@lsp.typemod.*` with increasing priority), and VS Code selectors (`*.declaration`, `variable.readonly`) do the same.

### 5. Other orthogonal axes worth naming (beyond LSP)
- **Language** suffix: TextMate `.c`, nvim `@comment.lua`, VS Code `:java`.
- **Scope/lifetime**: local vs global vs instance vs class. Pygments `Name.Variable.{Global,Instance,Class}`, JetBrains LOCAL/GLOBAL/INSTANCE_FIELD/STATIC_FIELD.
- **Visibility**: Helix `.private`, rust-analyzer `public` (off-spec).
- **Severity**: comment todo/note/warning/error, and diagnostics.
- **Salience / decoration level**: Emacs `treesit-font-lock-level` 1–4.
  - "Level 1 usually contains only comments and definitions. Level 2 adds keywords, strings, data types. Level 3 … assignments, constants, numbers and literals. Level 4 adds … delimiters, operators, brackets, punctuation, all functions, properties, variables."
  - This is the only standard that ranks categories by **importance**. It is direct prior art for a salience ordering: **definitions and comments first, punctuation and plain references last.**

### 6. Gaps and inconsistencies
1. **Function call has no TextMate name.** Calls are only distinguishable by the enclosing `meta.function-call`. TextMate themes need descendant selectors.
2. **"Builtin" means three things.**
   - Provenance: from the stdlib (`support`, `defaultLibrary`).
   - Language-intrinsic: `self`, `true`, `int` (`variable.language`, `constant.language`).
   - Emacs `font-lock-builtin-face`: historically "builtin functions", but modes also use it for preprocessor, `self` and `:keywords`.
3. **Attribute is overloaded.** It covers HTML tag attributes (TM `entity.other.attribute-name`, nvim `tag.attribute`), decorators/annotations (nvim `@attribute`), and class attributes/fields (Helix `attribute`).
4. **Label is overloaded.** Vim uses it for `case`/`default`, Helix for CSS selectors, and everyone else for goto/loop labels.
5. **Doc comment parentage is split.** It is a comment in TM, ts, Vim, Pygments `Comment.Special` and JetBrains; Emacs and Pygments `String.Doc` make it a string.
6. **Storage vs keyword.** TextMate puts declaration keywords (`class`, `int`, `static`) under `storage`, separate from `keyword`.
   - Pygments uses `Keyword.Declaration`/`Keyword.Type`, and Vim uses `StorageClass`/`Structure`/`Typedef` *under `Type`*.
   - nvim uses `keyword.type`/`keyword.modifier`, and Helix uses `keyword.storage.*`.
   - The same token, `struct`, is therefore a keyword in nvim, a type in Vim, and storage in TextMate.
7. **Primitive types** (`int`) are a *type* in nvim (`type.builtin`), a *keyword* in Pygments (`Keyword.Type`) and *storage* in TextMate (`storage.type`).
8. **Constructor** is its own kind only in tree-sitter and Helix.
9. **Unused** is a diagnostic tag in LSP (`DiagnosticTag.Unnecessary`), not a token modifier. Helix puts it under `comment.unused`, which implies "dim like a comment".
10. **Keys in data literals** (JSON keys) are `property` in nvim, a `support.type.property-name` hack in TM, and `Name.Tag` in Pygments' JSON lexer.
11. **Error tokens** are lexical (`invalid.illegal`, `Error`) in older systems. Newer systems drop them in favour of diagnostics, which are a separate overlay layer (underline/undercurl) rather than token colour.
12. **base16's assignments carry history** rather than semantics.
    - `entity.other.inherited-class` → base0B (green, same as strings).
    - Variables and tags → base08 (red, same as diff-deleted).
    - Attribute IDs → base0D (blue, same as functions).
    - Delimiters and operators → base05 (default fg).
    - It does not cover parameters, properties, namespaces, punctuation subtypes, doc comments or definition-vs-use.

### 7. Palette-level role systems (the other half of the problem)

These describe **colours by their job in the UI**, not tokens by syntax. They supply the vocabulary for the palette side of a pattern.

- **base16** (`styling.md`).
  - base00–07: a monotone ramp. 00 = default background, 01 = lighter background (status bars, line numbers), 02 = selection background, 03 = comments/invisibles/line highlight, 04 = dark fg (status bars), 05 = default fg/caret/delimiters/operators, 06 = light fg, 07 = light bg.
  - base08–0F: accents. 08 = variables/XML tags/link text/lists/diff deleted; 09 = integers/booleans/constants/XML attributes/link URLs; 0A = classes/markup bold/search bg; 0B = strings/inherited classes/markup code/diff inserted; 0C = support/regex/escapes/quotes; 0D = functions/methods/attribute IDs/headings; 0E = keywords/storage/selectors/italic/diff changed; 0F = deprecated/embedded language tags.
  - "base00 to base07 should span from dark to light" for dark themes, reversed for light.
- **base24** extends base16.
  - base10/11 are darker backgrounds.
  - base12–17 are bright red, yellow, green, cyan, blue and magenta.
  - It gives an explicit ANSI mapping: 08 → ANSI 1 red, 0B → 2 green, 0A → 3 yellow, 0D → 4 blue, 0E → 5 magenta, 0C → 6 cyan, 03 → 8 (bright black), 05 → 7, 07 → 15.
  - This makes explicit that base16's accent slots are **hue names** in practice (base08 = red, base09 = orange, 0A = yellow, 0B = green, 0C = cyan, 0D = blue, 0E = magenta, 0F = brown/dark red). That is a hidden *palette* assumption.
- **ANSI 16** conventional semantics. These are customs from git, ls/dircolors, compilers and test runners, not a spec.
  - 0 black, 1 **red** = error/deleted/failure, 2 **green** = success/added/passed, 3 **yellow** = warning/modified, 4 **blue** = info/directories/links, 5 **magenta** = misc (gcc uses it for warnings), 6 **cyan** = notes/hints/symlinks, 7 white = default fg.
  - 8–15 are "bright" variants, which historically doubled as **bold**. That is a salience coupling: bold and bright were the same signal.
  - Background, foreground and cursor are separate, non-indexed roles.
- **Material Design 3 colour roles.**
  - Accent families: `primary`, `secondary`, `tertiary`. Each has `on-X` (content colour drawn **on** X), `X-container` (lower-emphasis fill), `on-X-container`, and `X-fixed`/`X-fixed-dim`/`on-X-fixed(-variant)` (the same in light and dark).
  - Status: `error`, `on-error`, `error-container`, `on-error-container`.
  - Neutrals: `surface`, `on-surface`, `on-surface-variant`, `surface-dim`, `surface-bright`, and `surface-container-{lowest,low,,high,highest}` (tonal elevation steps).
  - Lines and the rest: `outline` (borders) and `outline-variant` (decorative dividers); `inverse-surface`, `inverse-on-surface`, `inverse-primary`; `scrim`, `shadow`, `background`/`on-background` (legacy).
  - Roles map to **tones** (0–100 lightness, HCT) of key-colour tonal palettes. Roles are named by **function and pairing**, not hue.
- **W3C DTCG Design Tokens Format Module** (2025.10 report; current draft dated 2026-09-08).
  - A token is "information associated with a human readable name, at minimum a name/value pair". It has `$value`, `$type`, and an optional `$description`.
  - **Groups** hold tokens. **Aliases/references** (`{group.token}`) let a semantic token point to a primitive one.
  - Composite tokens exist (typography, border, shadow...).
  - Types: color, dimension, fontFamily, fontWeight, duration, cubicBezier, number, strokeStyle, border, transition, shadow, gradient, typography.
  - The *primitive → semantic → component* tiering is industry practice built on aliases. It is not normative in the spec.

---

## c) Terms

Each term gives its source and the definition as used there. Where usage varies, the proposed sense for this project follows the arrow (→).

| Term | Source(s) | Definition |
|---|---|---|
| **Token** | Lexing/compilers; Pygments; LSP; DTCG | (1) Lexical: a classified span of source text. Pygments yields `(tokentype, value)`. (2) LSP: a classified span with one type and n modifiers. (3) DTCG: a *design token*, a named value such as a colour or dimension. → Use "syntax token" and "design token" to avoid the clash. |
| **Token type** | Pygments, LSP | The class of a token. In LSP it is mutually exclusive per token; in Pygments it is hierarchical. |
| **Modifier** (token modifier) | LSP 3.16+ | An orthogonal boolean fact attached to a token, encoded as a bit flag, combinable (declaration, definition, readonly, static, deprecated, abstract, async, modification, documentation, defaultLibrary). Not the same as the LSP *type* `modifier` (a keyword like `static`), nor TextMate `storage.modifier`. |
| **Scope** | TextMate, Sublime, VS Code, Helix | A dotted hierarchical name assigned by a grammar to a span. Scopes nest, so a span has a *scope stack*. Themes match with *scope selectors* (prefix and descendant). |
| **Scope selector** | TextMate | A pattern over scope stacks (`source.js meta.function-call entity.name.function`, with `-` exclusion). The more specific match wins. |
| **Capture** (capture name) | tree-sitter queries; Neovim; Zed | A name (`@function.call`) bound to a syntax-tree node by a query pattern. In Neovim it is also directly a highlight group, with dotted fallback. |
| **Highlight group** | Vim/Neovim | A named style target (fg, bg, sp, bold, italic, underline...). *Syntax groups* link to highlight groups. There are *preferred groups* (e.g. `Statement`) and *minor groups* (e.g. `Conditional`) that link to them. |
| **Face** | Emacs | A named bundle of display attributes (family, height, weight, slant, fg, bg, underline, box, `:inherit`...). It is the Emacs analogue of a highlight group. |
| **Font-lock** | Emacs | Emacs's syntax-highlighting engine, which uses regexp or tree-sitter rules. The faces are named `font-lock-*-face`. |
| **Feature / decoration level** | Emacs `treesit-font-lock-feature-list`, `treesit-font-lock-level` | A named set of highlighting rules (e.g. `comment`, `definition`, `bracket`) assigned to levels 1–4 by importance. This is prior art for salience tiers. |
| **TextAttributesKey** | JetBrains | A named style key with an optional fallback key. `DEFAULT_*` keys are language-neutral bases. |
| **Semantic highlighting** | LSP / VS Code | Highlighting from a language server's symbol analysis, layered **over** syntactic (grammar/tree-sitter) highlighting. |
| **Syntactic highlighting** | General | Highlighting from parse or lex structure only, without name resolution. |
| **Definition / declaration** | LSP modifiers; JetBrains | LSP: `declaration` marks declarations of symbols, and `definition` marks definitions, "for example, in header files". → The binding occurrence of a name. |
| **Reference / use / call** | Emacs 29 (`*-use-face`, `function-call-face`), tree-sitter (`.call`) | A non-binding occurrence of a name. |
| **Builtin / default library / support** | ts `.builtin`; LSP `defaultLibrary`; TM `support`; Emacs `builtin-face`; Pygments `Name.Builtin` | Provided by the language or stdlib rather than the user's code. → Split *language-intrinsic* (`self`, `true`) from *library-provided* (`print`, `Vec`). |
| **Readonly / constant** | LSP modifier `readonly`; kind `constant` elsewhere | A binding that cannot be reassigned. Systems disagree on whether this is a kind or a modifier (see b§4). |
| **Meta scope** | TextMate `meta.*` | A structural scope that marks a larger region (function body, call, class) and is not usually coloured itself. It enables context selectors. |
| **Injection** | tree-sitter; TextMate | One language embedded in another (regex in a string, SQL in a string, code in markdown). |
| **Palette** | General; base16 | The finite set of colour values a theme draws from, usually named by slot or hue and with no syntax meaning. |
| **Slot** | base16/base24 | A numbered palette position (`base00`–`base0F`, `base10`–`base17`) with *guidelines*, not rules, for what it colours. |
| **Ramp / scale** | base16 (00–07), M3 tonal palettes, Radix 1–12 | An ordered lightness sequence of one hue, or of neutrals. |
| **Tone / tonal palette** | Material 3 (HCT) | A lightness step (0–100) of a key colour. Roles are assigned to tones. |
| **Colour role** | Material 3 | A named *function* a colour serves in the UI (`primary`, `on-surface`, `outline`), independent of its value. It is resolved to a tone per light or dark scheme. |
| **On-colour** (`on-X`) | Material 3 | The content (text/icon) colour designed to sit **on** role X with guaranteed contrast. → For syntax, every token colour is effectively "on-surface". |
| **Surface** | Material 3; general UI | A background plane that content sits on. M3 has graded `surface-container-lowest…highest` for elevation. → Editor bg, gutter, popups, status line. |
| **Container** | Material 3 | A lower-emphasis fill version of an accent role, used behind content (`primary-container`). |
| **Accent** | General UI; base16 (08–0F informally); M3 ("accent colors" = primary/secondary/tertiary) | A chromatic colour used for emphasis, as opposed to the neutral ramp. |
| **Neutral** | M3, base16 00–07 | Low-chroma colours for surfaces, default text and de-emphasised text (comments). |
| **Semantic colour / semantic token** | Design-systems practice (DTCG aliases; Primer, Radix, etc.) | A design token named by purpose (`fg.muted`, `danger`) that aliases a primitive (`gray.500`). Distinct from LSP "semantic tokens". |
| **Primitive (base/global) token** | Design-systems practice | A raw value named by appearance (`blue.600`), with no purpose implied. |
| **Alias / reference** | DTCG | A token whose `$value` points to another token (`{color.blue.600}`), which creates the primitive → semantic → component layers. |
| **Status / feedback colours** | M3 (`error`), ANSI conventions, diagnostics (error/warning/info/hint) | Colours reserved for state signals: error = red, warning = yellow (or magenta in gcc), info = blue, success/added = green, hint = cyan. |
| **Diagnostic** | LSP | A server-reported problem with severity (Error, Warning, Information, Hint) and tags (`Unnecessary`, `Deprecated`). It is usually rendered as an underline or overlay, not as token colour. |
| **Salience** | Perceptual psychology / visualization (Itti & Koch saliency; "visual salience" in information design) | How strongly an element draws attention relative to its surroundings. It is driven by contrast in luminance, chroma, hue, weight and size. No editor taxonomy names it; Emacs decoration levels and ANSI bright=bold are implicit uses. → The project's axis for "how loud" a role is, independent of "which hue". |
| **Emphasis / weight** | Typography; Pygments `Generic.Emph`/`Strong`; M3 "high/medium/low emphasis" text | Typographic signalling (bold, italic) or contrast tiers. M3 uses emphasis levels for text on surfaces. |
| **Invisibles / whitespace** | TextMate, base16 base03 | Rendered whitespace and control-character markers. They are conventionally given comment-level salience. |

---

## Sources
- TextMate manual, Language Grammars → Naming Conventions: https://macromates.com/manual/en/language_grammars
- Neovim `:h treesitter-highlight-groups` (runtime/doc/treesitter.txt, v0.12.5 local), `:h group-name` (syntax.txt), `:h lsp-semantic-highlight` (lsp.txt)
- nvim-treesitter CONTRIBUTING.md (historical home of the capture list): https://github.com/nvim-treesitter/nvim-treesitter/blob/master/CONTRIBUTING.md
- Helix themes: https://docs.helix-editor.com/themes.html
- Zed language extensions (captures): https://zed.dev/docs/extensions/languages
- LSP 3.17 / 3.18 semantic tokens: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_semanticTokens and https://github.com/microsoft/language-server-protocol (`_specifications/lsp/3.18/language/semanticTokens.md`)
- VS Code Semantic Highlight Guide (standard types, modifiers, TextMate fallback map): https://code.visualstudio.com/api/language-extensions/semantic-highlight-guide
- Emacs 31.1 `lisp/font-lock.el` (defface list, `:version "29.1"` additions, `:inherit` chains) and `lisp/treesit.el` (`treesit-font-lock-level` docstring)
- Vim 9.2 / Neovim `:h group-name`
- Pygments `pygments.token.STANDARD_TYPES` (local install); docs: https://pygments.org/docs/tokens/
- JetBrains `DefaultLanguageHighlighterColors.java`: https://github.com/JetBrains/intellij-community/blob/master/platform/core-api/src/com/intellij/openapi/editor/DefaultLanguageHighlighterColors.java
- base16 styling: https://github.com/chriskempson/base16/blob/main/styling.md ; base24: https://github.com/tinted-theming/base24/blob/main/styling.md
- Material 3 colour roles: https://m3.material.io/styles/color/roles ; MDC-Android Color.md (role list): https://github.com/material-components/material-components-android/blob/master/docs/theming/Color.md
- W3C DTCG Design Tokens Format Module: https://www.designtokens.org/tr/drafts/format/
