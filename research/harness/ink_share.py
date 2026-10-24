"""Token "ink share" statistics over the sampled corpus.

For every selected file (data/corpus_manifest.json), each non-whitespace
character is assigned its winning highlight capture (harness/highlight.py).
Per language and pooled, per capture (full name and rolled-up top level):

  char_share        share of non-whitespace characters
  token_share       share of tokens (a token = one painted capture occurrence;
                    uncaptured text = whitespace-separated runs, "default")
  per_screen_median median count of tokens per 40-line screen (non-overlapping
                    windows; trailing windows < 10 lines dropped)
  per_screen_mean   mean of the same
  line_frac         fraction of non-blank lines containing >= 1 such char

Pooled = macro-average over languages (each language weighs equally), except
per_screen_median, which is the median over all screens of all languages.

Writes out/ink_share.csv, out/ink_share.md, out/query_coverage.json.
Run:  uv run --with tree-sitter --with tree-sitter-language-pack python harness/ink_share.py
"""
import csv
import json
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import highlight  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
CORPUS = ROOT / "data" / "corpus"
OUT = ROOT / "out"
SCREEN = 40
MIN_SCREEN = 10
WS = set(b" \t\r\n\f\v")


def top(name):
    return name.split(".")[0]


ROLE = {
    "function": "function.def", "function.method": "function.def",
    "function.call": "function.use", "function.method.call": "function.use",
    "function.builtin": "function.use", "function.macro": "function.use",
    "variable": "variable.plain", "variable.parameter": "variable.parameter",
    "variable.member": "variable.member", "property": "variable.member",
    "variable.builtin": "variable.builtin",
    "type.definition": "type.def", "type": "type.use", "type.builtin": "type.use",
}


def role(name):
    """Definition/use grouping that also harmonises naming differences between
    languages' queries (e.g. C/Go use @property where others use @variable.member)."""
    return ROLE.get(name, top(name))


LEVELS = {"full": lambda n: n, "top": top, "role": role}


class Acc:
    def __init__(self):
        self.chars = {lv: Counter() for lv in LEVELS}
        self.tokens = {lv: Counter() for lv in LEVELS}
        self.lines = {lv: Counter() for lv in LEVELS}
        self.screens = {lv: [] for lv in LEVELS}  # list of Counter per screen
        self.n_chars = self.n_tokens = self.n_lines = 0
        self.n_files = 0


def analyse_file(lang, src, acc):
    _, names, owner = highlight.paint(lang, src)
    names = ["default" if n == "none" else n for n in names]
    n = len(src)
    # token id per byte (None for whitespace / utf-8 continuation bytes)
    tid = [None] * n
    tname = {}
    nxt = -1
    prev_default = False
    for i in range(n):
        b = src[i]
        if b in WS:
            prev_default = False
            continue
        k = owner[i]
        if k >= 0:
            prev_default = False
            if 0x80 <= b < 0xC0:
                continue
            tid[i] = k
            tname[k] = names[k]
        else:
            if not prev_default:
                nxt -= 1
                tname[nxt] = "default"
                prev_default = True
            if 0x80 <= b < 0xC0:
                continue
            tid[i] = nxt
    # chars and tokens
    char_c = Counter(tname[t] for t in tid if t is not None)
    tok_c = Counter(tname[t] for t in set(tid) if t is not None)
    # lines and screens
    line_sets = []
    start = 0
    for ln in src.split(b"\n"):
        end = start + len(ln)
        line_sets.append({t for t in tid[start:end] if t is not None})
        start = end + 1
    if line_sets and not src.split(b"\n")[-1].strip():
        line_sets.pop()  # trailing newline
    for lv, f in LEVELS.items():
        cc = Counter()
        for nm, c in char_c.items():
            cc[f(nm)] += c
        acc.chars[lv].update(cc)
        tc = Counter()
        for nm, c in tok_c.items():
            tc[f(nm)] += c
        acc.tokens[lv].update(tc)
        for ls in line_sets:
            if ls:
                acc.lines[lv].update({f(tname[t]) for t in ls})
        for w in range(0, len(line_sets), SCREEN):
            win = line_sets[w:w + SCREEN]
            if len(win) < MIN_SCREEN:
                continue
            ids = set().union(*win)
            acc.screens[lv].append(Counter(f(tname[t]) for t in ids))
    acc.n_chars += sum(char_c.values())
    acc.n_tokens += sum(tok_c.values())
    acc.n_lines += sum(1 for ls in line_sets if ls)
    acc.n_files += 1


def summarise(acc, lv):
    rows = {}
    names = set(acc.chars[lv]) | set(acc.tokens[lv])
    for nm in names:
        vals = [s.get(nm, 0) for s in acc.screens[lv]]
        rows[nm] = {
            "char_share": acc.chars[lv][nm] / acc.n_chars,
            "token_share": acc.tokens[lv][nm] / acc.n_tokens,
            "per_screen_median": statistics.median(vals) if vals else 0,
            "per_screen_mean": statistics.fmean(vals) if vals else 0,
            "line_frac": acc.lines[lv][nm] / acc.n_lines,
            "char_count": acc.chars[lv][nm],
            "token_count": acc.tokens[lv][nm],
        }
    return rows


def main():
    manifest = json.loads((ROOT / "data" / "corpus_manifest.json").read_text())
    OUT.mkdir(exist_ok=True)
    per_lang = {}
    coverage = {}
    accs = {}
    for lang, info in manifest["langs"].items():
        _, query, n_pat, dropped = highlight.load(lang)
        coverage[lang] = {"patterns_total": n_pat, "patterns_dropped": len(dropped),
                          "dropped": dropped,
                          "parser": highlight.get_language(lang)[1],
                          "query_source": "Wilfred/tree-sitter-elisp" if lang == "elisp"
                          else "nvim-treesitter"}
        acc = Acc()
        errors = 0
        for f in info["files"]:
            src = (CORPUS / f["repo"] / f["path"]).read_bytes()
            analyse_file(lang, src, acc)
        # parse-error rate (rough grammar-fit check)
        for f in info["files"][:50]:
            src = (CORPUS / f["repo"] / f["path"]).read_bytes()
            from tree_sitter import Parser
            t = Parser(highlight.load(lang)[0]).parse(src)
            errors += t.root_node.has_error
        coverage[lang]["files_with_parse_errors_first50"] = errors
        coverage[lang].update(files=acc.n_files, nonblank_lines=acc.n_lines,
                              nonws_chars=acc.n_chars, tokens=acc.n_tokens,
                              screens=len(acc.screens["top"]))
        accs[lang] = acc
        per_lang[lang] = {lv: summarise(acc, lv) for lv in LEVELS}
        print(f"{lang:11s} files={acc.n_files} lines={acc.n_lines} chars={acc.n_chars} "
              f"tokens={acc.n_tokens} default={per_lang[lang]['top'].get('default', {}).get('char_share', 0):.3f} "
              f"parse_err={errors}/50", flush=True)

    langs = list(per_lang)
    pooled = {}
    for lv in LEVELS:
        names = set().union(*(per_lang[l][lv] for l in langs))
        pooled[lv] = {}
        for nm in names:
            def mean(key):
                return statistics.fmean(per_lang[l][lv].get(nm, {}).get(key, 0) for l in langs)
            all_screens = [s.get(nm, 0) for l in langs for s in accs[l].screens[lv]]
            pooled[lv][nm] = {
                "char_share": mean("char_share"), "token_share": mean("token_share"),
                "per_screen_median": statistics.median(all_screens),
                "per_screen_mean": statistics.fmean(all_screens),
                "line_frac": mean("line_frac"),
                "char_count": sum(per_lang[l][lv].get(nm, {}).get("char_count", 0) for l in langs),
                "token_count": sum(per_lang[l][lv].get(nm, {}).get("token_count", 0) for l in langs),
                "n_langs": sum(1 for l in langs if nm in per_lang[l][lv]),
            }

    cols = ["lang", "capture", "level", "char_share", "token_share", "per_screen_median",
            "line_frac", "per_screen_mean", "char_count", "token_count"]
    with (OUT / "ink_share.csv").open("w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(cols)
        for lang, data in [("pooled", pooled)] + list(per_lang.items()):
            for lv in LEVELS:
                for nm, r in sorted(data[lv].items(), key=lambda kv: -kv[1]["char_share"]):
                    w.writerow([lang, nm, lv, f"{r['char_share']:.6f}", f"{r['token_share']:.6f}",
                                r["per_screen_median"], f"{r['line_frac']:.6f}",
                                f"{r['per_screen_mean']:.3f}", r["char_count"], r["token_count"]])
    (OUT / "query_coverage.json").write_text(json.dumps(coverage, indent=1))
    write_md(manifest, per_lang, pooled, coverage, langs)
    print("wrote out/ink_share.csv, out/ink_share.md, out/query_coverage.json")


def pct(x):
    return f"{100 * x:.1f}%" if x >= 0.001 else (f"{100 * x:.2f}%" if x > 0 else "-")


def write_md(manifest, per_lang, pooled, coverage, langs):
    L = []
    L.append("# Token ink share\n")
    L.append("Generated by `harness/ink_share.py`. Shares are of non-whitespace characters / tokens; "
             "pooled = unweighted mean over the languages below (each language counts equally). "
             "`scr med`/`scr mean` = tokens per 40-line screen; `lines` = fraction of non-blank lines "
             "containing the capture. Highlighting = nvim-treesitter `highlights.scm` (elisp: "
             "Wilfred/tree-sitter-elisp upstream query), innermost/last capture wins, no injections.\n")
    L.append("## Corpus\n")
    L.append("| lang | files | non-blank lines | non-ws chars | tokens | repos |")
    L.append("|---|---:|---:|---:|---:|---|")
    for l in langs:
        c = coverage[l]
        repos = sorted({f["repo"] for f in manifest["langs"][l]["files"]})
        L.append(f"| {l} | {c['files']} | {c['nonblank_lines']} | {c['nonws_chars']} | {c['tokens']} | {', '.join(repos)} |")
    L.append("")

    def table(rows, n=None, min_share=0.0):
        out = ["| capture | char share | token share | scr med | scr mean | lines | langs |",
               "|---|---:|---:|---:|---:|---:|---:|"]
        items = sorted(rows.items(), key=lambda kv: -kv[1]["char_share"])
        items = [kv for kv in items if kv[1]["char_share"] >= min_share][:n]
        for nm, r in items:
            out.append(f"| {nm} | {pct(r['char_share'])} | {pct(r['token_share'])} | "
                       f"{r['per_screen_median']:g} | {r['per_screen_mean']:.1f} | {pct(r['line_frac'])} | "
                       f"{r.get('n_langs', '')} |")
        return out

    L.append("## Pooled, top-level categories\n")
    L += table(pooled["top"])
    L.append("\n## Pooled, full capture names (char share >= 0.1%)\n")
    L += table(pooled["full"], min_share=0.001)

    L.append("\n## Pooled, definition/use roles\n")
    L.append("`role` level: function.def = function + function.method (names at definition); "
             "function.use = *.call + function.builtin + function.macro; variable.member = "
             "variable.member + property; type.use = type + type.builtin; type.def = type.definition; "
             "everything else rolled up to top level.\n")
    L += table(pooled["role"])
    L.append("\n## Top-level char share by language\n")
    tops = sorted(pooled["top"], key=lambda k: -pooled["top"][k]["char_share"])
    L.append("| capture | pooled | " + " | ".join(langs) + " |")
    L.append("|---|---:|" + "---:|" * len(langs))
    for nm in tops:
        if pooled["top"][nm]["char_share"] < 0.0005:
            continue
        L.append(f"| {nm} | {pct(pooled['top'][nm]['char_share'])} | " +
                 " | ".join(pct(per_lang[l]["top"].get(nm, {}).get("char_share", 0)) for l in langs) + " |")

    L.append("\n## Definition vs use\n")
    L.append("Char share (token share in parentheses). nvim-treesitter marks definitions/uses "
             "through sub-captures: `function`/`function.method` = name at definition site, "
             "`*.call` = call sites; `variable.parameter` = parameters (definition and, in some "
             "grammars, use); `variable.member` = fields/properties; `type.definition` = typedef/alias "
             "names. Plain `variable` covers both bindings and references (not separable via queries).\n")
    groups = ["function", "function.call", "function.method", "function.method.call", "function.builtin",
              "function.macro", "constructor", "variable", "variable.parameter", "variable.member",
              "variable.builtin", "property", "type", "type.definition", "type.builtin", "module"]
    L.append("| capture | pooled | " + " | ".join(langs) + " |")
    L.append("|---|---:|" + "---:|" * len(langs))
    for g in groups:
        def cell(r):
            return "-" if not r else f"{pct(r['char_share'])} ({pct(r['token_share'])})"
        L.append(f"| {g} | {cell(pooled['full'].get(g))} | " +
                 " | ".join(cell(per_lang[l]['full'].get(g)) for l in langs) + " |")
    defs = [k for k in ("function", "function.method") ]
    uses = [k for k in ("function.call", "function.method.call")]
    L.append("\nFunction-name definition:call ratio (tokens) per language: " + ", ".join(
        f"{l} {sum(per_lang[l]['full'].get(k, {}).get('token_count', 0) for k in defs)}:"
        f"{sum(per_lang[l]['full'].get(k, {}).get('token_count', 0) for k in uses)}" for l in langs) + ".\n")

    L.append("## Per-language notable deviations\n")
    L.append("Top-level and full captures whose char share in a language is >= 2x or <= 0.5x the pooled "
             "value and differs by >= 2 percentage points (pooled value after 'vs'; '-' = capture never "
             "produced by that language's query). '(top)' = rolled-up category.\n")
    for l in langs:
        notes = []
        for lv in ("top", "full"):
            for nm, r in pooled[lv].items():
                v = per_lang[l][lv].get(nm, {}).get("char_share", 0)
                p = r["char_share"]
                if abs(v - p) >= 0.02 and (v >= 2 * p or v <= 0.5 * p):
                    tag = "" if lv == "full" else " (top)"
                    if lv == "top" and nm in pooled["full"]:
                        fv = per_lang[l]["full"].get(nm, {}).get("char_share", 0)
                        if abs(fv - v) < 0.005:
                            continue  # same story as the full-name entry
                    notes.append((abs(v - p), f"`{nm}`{tag} {pct(v)} vs {pct(p)}"))
        notes.sort(reverse=True)
        seen, uniq = set(), []
        for _, s in notes:
            if s not in seen:
                seen.add(s)
                uniq.append(s)
        top3 = sorted(per_lang[l]["full"].items(), key=lambda kv: -kv[1]["char_share"])[:5]
        L.append(f"- **{l}**: top full captures " +
                 ", ".join(f"`{k}` {pct(v['char_share'])}" for k, v in top3) +
                 (". Deviations: " + "; ".join(uniq[:8]) if uniq else ". No large deviations") + ".")
    L.append("\n## Caveats\n")
    L += [
        "- Shares reflect what nvim-treesitter's queries *paint*, not language semantics: e.g. bash "
        "`constant` is nvim's ALL_CAPS-variable heuristic; C/Go/Lua use `property` where others use "
        "`variable.member`; Rust/C have no `function.method.call`; Java has no plain `function.call`. "
        "Use the `role` level for cross-language comparisons.",
        "- elisp uses the sparse upstream Wilfred/tree-sitter-elisp query (no call/symbol captures), so ~40% "
        "of its ink is `default`; pooled `default` is almost entirely elisp.",
        "- Injections are not run: doc-comment markup (JSDoc/LuaCATS/rustdoc), regex internals, printf "
        "formats, and embedded languages stay painted as their host comment/string.",
        "- Comment/docstring share is very corpus-dependent (requests/flask docstrings, neovim LuaCATS, "
        "rustdoc, javadoc). Treat comment/string char shares as +/- 10pp across codebases; token shares "
        "and per-screen counts for code tokens are more stable.",
        "- Pooled = unweighted mean of 10 languages (JS and TS counted separately).",
    ]
    L.append("\n## Query coverage\n")
    for l in langs:
        c = coverage[l]
        L.append(f"- {l}: {c['query_source']}, {c['patterns_total']} top-level patterns, "
                 f"{c['patterns_dropped']} dropped (don't compile); parser={c['parser']}; "
                 f"{c['files_with_parse_errors_first50']}/50 sampled files have >=1 parse ERROR node.")
    (OUT / "ink_share.md").write_text("\n".join(L) + "\n")


if __name__ == "__main__":
    main()
