# Corpus findings: H4–H7

Sources: `out/role_stats.md` (+ `binding_stats.csv`, `constant_stats.csv`), `out/recoverability.md`,
`out/adjacency.md`. Corpus: 10 languages, 2 repos each (`data/corpus_manifest.json`). **ALL = unweighted
mean over 9 languages; elisp is excluded** because its upstream query is sparse (41% of its ink is
`default`). Shares are of non-whitespace characters ("ink") unless marked as tokens.

## H4: binding sites are cheap beacons (< 5% of ink)

| binding kind | ink | tokens | per 40-line screen |
|---|---:|---:|---:|
| function.def | 2.6% | 0.9% | 1.7 |
| type.def | 0.3% | 0.1% | 0.3 |
| constant.def | 0.8% | 0.3% | 0.5 |
| macro.def | 0.02% | 0.01% | 0.0 |
| variable.def.top (module scope) | 0.2% | 0.1% | 0.2 |
| **beacon bindings (the five above)** | **4.0%** | 1.5% | 2.7 |
| variable.def.local | 2.2% | 1.8% | 3.4 |
| parameter.def | 1.2% | 1.3% | 2.4 |
| field.def | 0.4% | 0.3% | 0.5 |
| **all bindings** | **7.9%** | 4.8% | 9.0 |

- **Holds for the landmark definition family.** The family covers function, type, macro and
  constant definitions plus top-level variables. It is 4.0% of ink, about 2.7 tokens per screen.
  By language it ranges from 1.8% (TS) and 1.9% (Lua) up to 5.8% (Python), with bash at 8.1%.
  Bash is inflated because nvim paints every ALL_CAPS bash variable `@constant`, so `FOO=...`
  counts as constant.def (5.6%). Without bash the mean is 3.4%.
- **Fails if every binding is bold.** Adding local variables, parameters and fields gives 7.9% of
  ink and 9 tokens per screen. Local variable definitions alone are 2.2%, and they are about 88% of
  variable.def. So "bold all binding sites" costs twice the budget of "bold top-level definitions".
- Top-level variable bindings are rare: 0.2% of ink, and 0.7% even in JS.

## H5: constants are values; readonly locals are not distinguished

Each class counts its binding sites plus the use sites resolved to them by name (within the file).

| | JS | TS | Rust | Go | C | Java |
|---|---:|---:|---:|---:|---:|---:|
| readonly locals (ink) | 3.7% | 8.0% | 3.9% | – | 0.06% | 2.4% |
| readonly as share of local-variable tokens | 37% | 94% | 64% | 0% | 1% | 40% |
| named constants (declared const + enum member) | – | – | 1.1% | 0.7% | 1.2% | 0.7% |
| JS/TS module-level `const` | 1.1% | 1.3% | – | – | – | – |
| ALL_CAPS identifiers (any) | 0.7% | 0.3% | 0.5% | 0.2% | 5.2% | 1.2% |
| declared constants that are ALL_CAPS (tokens) | 21% | 12% | 31%* | 5% | 90% | 98% |
| ALL_CAPS identifiers declared in the same file | 41% | 52% | 80% | 6% | 20% | 49% |

\*Rust declared = `const`/`static` (ALL_CAPS) plus enum variants (CamelCase). The variants are 0.7%
of Rust ink and pull the share down.

- **Readonly locals are too common to colour, as predicted.** Where the language has them, they are
  2.4–8% of ink. That is 3–7× the named constants (0.7–1.2%). In TS, 94% of local-variable tokens
  are `const`, so a "readonly" colour there would just mean "local variable". Pooled over all 9
  languages (zeros included): readonly locals 2.0% vs named constants 0.4%.
- **CAPS is not a reliable sign of a constant.** In Java (98%) and C (90%), declared constants are
  CAPS by convention. Go (5%), TS (12%), JS (21%) and Rust enum variants are not. The other
  direction fails too: 80% of C's ALL_CAPS identifiers are not declared in the file. They are mostly
  header macros, which nvim paints `@constant` by regex anyway. The `@constant` capture is therefore
  mostly "ALL_CAPS by convention". It misses Go/TS constants and catches bash variables.
- The recoverability of constant.use (0.92) is high **by construction**: the label comes from a CAPS
  regex in 6 of the queries. It does not show that readers can recognise declared constants from
  their glyphs; the CAPS share above is the better test.

## H6: identifier use sites stay default

- Identifier use sites are 33.5% of all ink and **65% of code ink**, where code ink excludes
  comments, doc comments, strings and punctuation. These sites are variable, field, parameter,
  constant, module and builtin uses, plus calls and type uses. By language the code-ink share is
  58% (Python) to 73% (Rust). By tokens it is 25% of all and 52% of code tokens. This matches the
  ~70% figure in P well enough.
- variable.use alone is 10.5% of ink, 17 tokens per screen, on 33% of lines. function.call adds 9.6%
  and 11 per screen.
- Comments, doc comments and strings together are about 39% of ink. Punctuation is 44% of tokens.

## H7: keywords need no hue; exits might

| role | recall (recoverability) | ink | tokens/screen | lines |
|---|---:|---:|---:|---:|
| keyword.exit | 0.97 | 1.0% | 1.6 | 4.9% |
| keyword.decl | 0.97 | 2.2% | 4.3 | 10.5% |
| keyword.other | 0.96 | 1.6% | 3.7 | 10.0% |
| keyword.flow | 0.92 | 1.1% | 3.9 | 9.2% |

- **All keyword roles can be recovered from their glyphs** (recall 0.92–0.97, precision ≥ 0.95).
  Exit vs flow separates almost perfectly (balanced accuracy 0.999). The few errors come from the
  top-300 vocabulary proxy: Rust `break`/`continue` are too rare to make the top 300 (Rust exit
  recall 0.91).
- So colour on exits buys **beacon value only**, not disambiguation. That is cheap: 1.0% of ink and
  about 1.6 tokens per screen, the rarest keyword role. This is consistent with H2 and the landmark
  `exit` family.
- **Selector problem in roles.yaml.** `keyword.exit` selects `@keyword.exception` and
  `@keyword.coroutine`. nvim also paints try/catch/except/finally, `async`, Java `throws` and Rust
  `assert!`/`assert_eq!`/`panic!` with those captures. role_tokens.py narrows keyword.exit by text to
  return/raise/throw/yield/await/break/continue/goto. The raw selectors would give 3.3% of TS ink
  (vs 2.3% narrowed) and 1.7% of Rust ink (vs 0.2%).
- **Is `await` an exit?** In TS, `await` is 1.3% of ink, more than `return`. Counting it as an exit
  doubles TS exit ink. The framework's "await?" needs a decision.

## Other findings (H2/H8 inputs)

- **Definitions are not always visible in the glyphs.** function.def recall is 1.00 in Python and
  Rust, where `def`/`fn` comes first. It drops to 0.56 in JS, 0.47 in TS and 0.28 in Lua, where
  `const f = () =>` and `M.f = function` hide it. type.def recall is 0.70 and constant.def 0.53. By
  H2, the definition hue adds the most disambiguation value in JS, TS and Lua.
- **Weighted pairs that are hard to separate from lexical features alone** (balanced accuracy):
  parameter/variable.use 0.90 (Lua 0.60, JS 0.83) and function.def/function.call 0.96 (Lua 0.84,
  Go 0.91). The remaining weighted pairs are ≥ 0.975.
- **comment.doc vs comment** is the largest confusion of a frequent role: 26% of doc comments are
  predicted as comment. A separate doc-comment treatment therefore carries information.
- **Adjacency (skipping punctuation)** of the weighted pairs: field/variable.use 3.5% of neighbour
  pairs (`obj.field`), type.use/function.call 1.3% (7.2% in Java), string/string.escape 1.2%,
  constant.use/variable.use 0.16%, parameter/variable.use 0.16%. string/comment, the w=3 pair, is
  only 0.05% (0.15% of lines). With the current weights, field/variable.use (w=1) dominates the
  confusion cost: adjacency 3.5% × 1 = 0.035, against about 0.0015 for string/comment.

## Caveats

- Every label is nvim-treesitter's paint, as approximated in harness/README.md: pinned parsers,
  no injections, partial predicate support. comment.todo never fires because there are no
  injections.
- Binding sites come from locals.scm. Its coverage is uneven:
  - Rust `static` items and Java enum constants come only from a name-field heuristic (a few dozen tokens).
  - Lua global assignments are not definitions.
  - Python re-assignments are definitions.
  - Imports are excluded on purpose.
  - elisp has no locals.scm: its query paints `@variable` only at defvar/defconst/let, so all elisp
    variable tokens are bindings, and no use sites exist.
- Use-site resolution for H5 is by name within the file. It ignores shadowing. A closure's use of
  an outer function's local stays unresolved, so readonly-local shares are a lower bound. Constants
  declared in other files (C headers, Java imports) do not resolve.
- "Top-level" means not inside a function, method, lambda or closure. Class bodies count as
  top-level.
- Python docstrings are `string` under roles.yaml (Python string share 34%). Comment and string
  shares swing ±10 percentage points between codebases. Two repos per language is a small sample.
- Recoverability uses a linear model on one segment per example. It is a lower bound on what a
  reader extracts, and it is inflated wherever a query labels by lexical rule (CAPS→constant,
  `self`→builtin). The string/comment pair scores 1.0, but this cannot measure the motivating case,
  a commented-out string, because a string inside a comment is part of the comment token.
- ALL averages include zeros for languages that lack a concept, such as readonly locals in
  Python/Go/Lua or declared constants in Python. The per-language columns are the honest view.
