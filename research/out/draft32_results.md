# Draft 3.2 results (optional binding tint, Rust `?` exit, faded commented-out code)

Generated with `harness/role_tokens.py`, `role_stats.py`, `adjacency.py`, `mapper.py` (`options`), `parse_load.py`, `score_palettes.py`, `render.py`.

## 1. Corpus roles

**Rust `?` -> keyword.exit.** An `@operator` token with text `?` whose parent is `try_expression`.

| Rust keyword.exit | before | after |
|---|---:|---:|
| char share | 0.236% | 0.304% |
| token share | 0.181% | 0.495% |
| tokens per 40-line screen | 0.37 | 1.02 |

Pooled (lang ALL) keyword.exit char share moves 0.827% -> 0.834%, per screen 1.33 -> 1.40. Rust operator ink drops 1.07% -> 1.00%. Rust exits nearly triple per screen, so Rust no longer under-represents the exit landmark.

**comment.code.** `@comment` segments (not `@comment.documentation`) passing `role_tokens.is_commented_code`. It is a partition of the old `comment` role in `out/role_stats.csv`; `mapper_common.ink_shares()` and `adjacency()` fold it back into `comment` for pattern sets with no comment.code style, so the other sets' inputs are unchanged. The heuristic is the roles.yaml one with the tightenings listed in its docstring (a first literal version had roughly 50% precision, mostly prose that mentions code: `foo() detects X`, `If A=b ...`, `e.g.`, shellcheck directives, elisp autoload cookies and rulers). 13 code and 18 prose examples are unit-tested in `harness/test_comment_code.py`.

| lang | char share | token share | share of non-doc comments |
|---|---:|---:|---:|
| python | 0.039% | 0.006% | 0.5% |
| javascript | 0.118% | 0.009% | 0.9% |
| typescript | 0.197% | 0.022% | 4.5% |
| rust | 0.026% | 0.004% | 0.7% |
| go | 0.427% | 0.023% | 1.4% |
| c | 0.074% | 0.003% | 0.3% |
| lua | 0.151% | 0.030% | 3.5% |
| bash | 0.247% | 0.042% | 1.4% |
| elisp | 0.014% | 0.004% | 0.2% |
| java | 0.234% | 0.026% | 5.1% |
| ALL (no elisp) | 0.168% | 0.018% | |

Samples: `out/comment_code_samples.md` (10 per language, fewer where fewer were detected; 83 in all). Eyeballed precision about 88% (about 7 clear false positives and 2 ambiguous). False positives: prose with a code fragment (`// (case-insensitive) listed in `redactKeys` ...`), a ruler-led C block, a Go `params[2]=response body ...` doc line, a Lua doc line with an inline table, one bash prose line starting `NVM_X=1 makes ...`, `;t=pty nil=pipe` in elisp. Most hits are real: commented-out test code in TS/Java/Go/Lua, block-commented examples in JS, `#VAR=value` config defaults in bash. Recall is low by design (continuation lines such as a lone `0, new short[]{...}` are missed). The cue touches 0.17% of ink, so it matters little for reading metrics.

Cache rebuilt; `role_stats` and `adjacency` rerun. Later numbers moved slightly because of these changes (see 4).

## 2. Mapper options

`map_palette(p, 'reader', mode, options={'binding': slot | 'auto' | None, 'fade_commented_code': bool})`, both off by default (default output is identical to before; the reader quiet/recessive/loud derivation is not touched). `mapper.apply_options` works on a finished theme, so variants cost almost nothing. `mapper_common.hue_families` skips `optional` families, so `binding` is outside the hue cap, capacity, shedding and conformance.

- binding: `parameter` gets a quiet tint from the slot's hue via the same `quiet_joint` search (C in tiers.quiet.chroma, |Lc - Lc_fg| <= 12) with recessive, dim and every other quiet colour as the avoid set. Theme JSON: `binding` {slot, hex, ok, margins vs fg / dim / recessive / each quiet, d1_reliable_all, d1_cvd, hue_gap}. `auto` (mode B) tries every chromatic ink slot and prefers hue gap >= 40 deg from the other quiet cues, then the largest margin.
- fade: `comment.code` uses the theme's faded colour.
- `assignments.yaml` reader section has `binding:` per creator palette, with justification comments.

Creator binding tints (D1 reliable at p=.8, de_text margin minus 1, must be >= 0):

| palette | slot | tint | hue gap to nearest quiet cue | min margin (vs fg / dim / recessive / quiet) | D1-reliable vs all | deutan / protan |
|---|---|---|---:|---|---|---|
| gruvbox | base0D | #75d1b2 | 32 deg | fg 1.15, dim 1.25, rec 3.18, quiets 0.23-1.84 | yes | no / no |
| monokai | base0C | #acfcf1 | 58 deg | fg 0.55, dim 1.42, rec 1.55, callable 0.20 | yes | no / no |
| kanagawa | base0C | #b7eede | 90 deg | fg 0.20, dim 1.09, rec 2.43, quiets 0.49-1.87 | yes | no / no |
| zenburn | base0B | #b4e3b4 | 54 deg | fg 0.33, dim 0.84, rec 1.09, quiets 0.21-2.07 | yes | no / no |

All four pass D1-reliable against default and every other quiet colour under normal vision. Gruvbox misses the 40 deg hue SHOULD (every warm hue is taken; aqua is the only cool slot). None is D1-reliable under deutan/protan. Quiet cues in general are not, so this is the reader's existing CVD weakness, not something the tint adds.

## 3. Parse load (`out/parse_load.md`, section "Draft 3.2 optional cues")

`H_p` / `amb_p` split `parameter` into its own reading class; `H` / `amb` keep the original classes. Normal vision, with punctuation, means over the 4 creator palettes (mode C):

| variant | H | amb/screen | H_p | amb_p/screen |
|---|---:|---:|---:|---:|
| reader | 0.4791 | 25.96 | 0.5678 | 29.59 |
| reader+binding | 0.4665 | 25.96 | 0.4665 | 25.96 |
| reader+fade | 0.4791 | 25.96 | 0.5678 | 29.59 |
| reader+both | 0.4665 | 25.96 | 0.4665 | 25.96 |

- Binding tint: with parameters as their own class, H_p falls by 0.101 bits/token and ambiguous tokens by 3.6 per screen (-12%), as the tint pulls parameters out of the "default ink" cluster that holds variables, fields and defaults. With the original classes (parameter = binding) H falls 0.012 and amb is unchanged, because parameters and variables share a class there.
- Fade: no measurable effect (comment.code is 0.02% of tokens; |dH| < 0.0005). It moves comment.code from the comment cluster to the punctuation cluster at no cost.
- Under deutan the tint makes H_p worse (1.834 -> 1.901, amb_p 77.0 -> 80.1); protan is unchanged. Without punctuation H_p 0.774 -> 0.593.
- Mode B, all 1425 palettes (binding slot chosen by `auto`): found on 89% of palettes (1266/1425), D1-reliable vs fg and every other quiet colour on 100% of those, hue gap >= 40 deg on 92%. Median H_p 0.641 -> 0.534 (median delta -0.099 bits; lower on 89% of palettes), amb_p 32.2 -> 28.6 (-3.6). The 11% without a tint are palettes with no chromatic slot that is reliably distinct from fg and the other quiet cues.

Reader / landmark / label rows otherwise moved only by the role-stat changes: median |dH| about 0.001, with a few outliers (ansi16/Squirrelsong Dark landmark B under protan moved 0.6-0.9 bits through a mode-B assignment tie).

## 4. Reruns

- `score_palettes.py`: all sets rerun. Medians (mode B) of C6 raw/disc, S1a unchanged to the printed digits for landmark, label and reader; reader C1 rho -0.399 -> -0.324 (comment.code is now its own reader role, and exits include Rust `?`). Many deutan/label confusion columns changed in the 4th decimal place from the new ink and adjacency inputs.
- `parse_load.py`: see 3. `static_checks.py` also reran (out/static_checks.md differs: comment.code is a new role).
- `render.py`: columns plain / landmark C / reader C / reader C + options (binding tint + faded commented code). The Rust grid (`out/renders/grid_rust.html`, ripgrep jsont.rs 185-216, chosen to include `?`) was screenshotted: the bold `?` after `serialize_field(...)` shows in both reader columns, the parameter tints `path`/`s` in `from_path(path: &Path)` show in the options column (aqua on gruvbox), and the `// use base64 ...` commented-out lines are faded there. Tree-sitter marks mostly the declaration, so only declaration-site parameters are tinted, as the spec warns. tasks.html keeps its 4 conditions (plain / landmark C / reader C / label C).
