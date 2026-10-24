"""Per-role ink statistics from the role-painted corpus (data/cache/role_tokens.pkl,
built by harness/role_tokens.py).

Writes
  out/role_stats.csv     lang, role, char_share, token_share, per_screen_mean,
                         per_screen_median, line_frac   (+ variable.def.top/.local rows,
                         a partition of variable.def; lang=ALL = unweighted mean over
                         languages excluding elisp, for every column)
  out/binding_stats.csv  binding-site share by kind (H4)
  out/constant_stats.csv readonly locals vs named constants vs ALL_CAPS (H5)
  out/role_stats.md      readable tables + caveats

Run: uv run --with pandas --with numpy python harness/role_stats.py
"""
import pickle
import re
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "out"
SCREEN, MIN_SCREEN = 40, 10
EXCLUDE_FROM_ALL = {"elisp"}
CAPS = re.compile(r"^_?[A-Z][A-Z0-9_]+$")


def load():
    with (ROOT / "data" / "cache" / "role_tokens.pkl").open("rb") as fh:
        return pickle.load(fh)


def line_table(seg, lines):
    """(file, line, key, occ) rows for every non-blank line a segment touches."""
    single = seg[seg.l0 == seg.l1]
    multi = seg[seg.l0 != seg.l1]
    parts = [pd.DataFrame({"file": single.file.values, "line": single.l0.values,
                           "idx": single.index.values})]
    if len(multi):
        reps = (multi.l1 - multi.l0 + 1).values
        f = np.repeat(multi.file.values, reps)
        idx = np.repeat(multi.index.values, reps)
        ln = np.concatenate([np.arange(a, b + 1) for a, b in zip(multi.l0.values, multi.l1.values)])
        parts.append(pd.DataFrame({"file": f, "line": ln, "idx": idx}))
    lt = pd.concat(parts, ignore_index=True)
    nb = pd.DataFrame([(fi, ln) for fi, lns in lines.items() for ln in lns], columns=["file", "line"])
    lt = lt.merge(nb, on=["file", "line"])
    return lt, nb


def screens(lines):
    """list of (file, window) that count as screens (>= MIN_SCREEN physical lines)."""
    out = []
    for fi, lns in lines.items():
        if not lns:
            continue
        nlines = lns[-1] + 1
        for w in range(0, nlines, SCREEN):
            if min(w + SCREEN, nlines) - w >= MIN_SCREEN:
                out.append((fi, w // SCREEN))
    return pd.DataFrame(out, columns=["file", "win"])


def stats_for(seg, lines, keycol):
    """Stats per value of seg[keycol] (rows with NaN key are skipped for numerators
    but count in the denominators)."""
    n_chars = seg.nch.sum()
    n_tok = seg[["file", "occ"]].drop_duplicates().shape[0]
    lt, nb = line_table(seg, lines)
    n_lines = len(nb)
    scr = screens(lines)
    s = seg[seg[keycol].notna()]
    chars = s.groupby(keycol, observed=True).nch.sum()
    toks = s[["file", "occ", keycol]].drop_duplicates().groupby(keycol, observed=True).size()
    lt[keycol] = seg[keycol].reindex(lt.idx.values).values
    lt["occ"] = seg.occ.reindex(lt.idx.values).values
    lt = lt[lt[keycol].notna()]
    lf = lt[["file", "line", keycol]].drop_duplicates().groupby(keycol, observed=True).size()
    lt["win"] = lt.line // SCREEN
    per = lt[["file", "win", "occ", keycol]].drop_duplicates().groupby(
        ["file", "win", keycol], observed=True).size().rename("n").reset_index()
    rows = {}
    for k in chars.index:
        p = scr.merge(per[per[keycol] == k][["file", "win", "n"]], on=["file", "win"], how="left")
        v = p.n.fillna(0).values
        rows[k] = dict(char_share=chars[k] / n_chars, token_share=toks.get(k, 0) / n_tok,
                       per_screen_mean=float(v.mean()) if len(v) else 0.0,
                       per_screen_median=float(np.median(v)) if len(v) else 0.0,
                       line_frac=lf.get(k, 0) / n_lines,
                       char_count=int(chars[k]), token_count=int(toks.get(k, 0)))
    return rows


def pooled(per_lang, cols):
    langs = [l for l in per_lang if l not in EXCLUDE_FROM_ALL]
    keys = set().union(*(per_lang[l] for l in langs))
    out = {}
    for k in keys:
        out[k] = {c: float(np.mean([per_lang[l].get(k, {}).get(c, 0.0) for l in langs])) for c in cols}
        out[k]["n_langs"] = sum(1 for l in langs if k in per_lang[l])
    return out


# ------------------------------------------------------------- H5 classes


def resolve_classes(seg):
    """Assign each identifier segment a constant/readonly class, def and use sites.
    Uses are resolved by name: same innermost function first, then file-level
    (top) bindings.  Returns a Series aligned to seg (NaN = not an identifier of
    interest / unresolved)."""
    ident = seg.role.isin(["variable.def", "variable.use", "constant.def", "constant.use", "field"])
    defs = seg[seg.role.isin(["variable.def", "constant.def"])]
    cls = pd.Series(np.nan, index=seg.index, dtype=object)
    cls[defs.index] = defs.cls.astype(str)
    scope = pd.Series(np.nan, index=seg.index, dtype=object)
    scope[defs.index] = defs.scope.astype(str)
    first = defs.sort_values("s").drop_duplicates(["file", "func", "text"])
    fn = {(r.file, r.func, r.text): (r.cls, r.scope) for r in first.itertuples()}
    top = first[first.scope == "top"].drop_duplicates(["file", "text"])
    tp = {(r.file, r.text): (r.cls, r.scope) for r in top.itertuples()}
    uses = seg[ident & ~seg.role.isin(["variable.def", "constant.def"])]
    for r in uses.itertuples():
        hit = fn.get((r.file, r.func, r.text)) or tp.get((r.file, r.text))
        if hit:
            cls[r.Index], scope[r.Index] = hit
    return cls, scope, ident


def constant_rows(seg, lines):
    cls, scope, ident = resolve_classes(seg)
    caps = seg.text.str.match(CAPS) & ident
    declared = cls.isin(["declared_const", "enum_member", "module_const"])
    keys = {
        "readonly_local (def+use)": cls.eq("readonly_local"),
        "local variable, any (def+use)": scope.eq("local") & seg.role.isin(
            ["variable.def", "variable.use", "constant.def", "constant.use"]),
        "declared_const (def+use)": cls.eq("declared_const"),
        "enum_member (def+use)": cls.eq("enum_member"),
        "module_const JS/TS top-level const (def+use)": cls.eq("module_const"),
        "named constant = declared_const+enum_member (def+use)": cls.isin(["declared_const", "enum_member"]),
        "ALL_CAPS identifier": caps,
        "ALL_CAPS and declared in file": caps & declared,
        "ALL_CAPS, not declared in file": caps & ~declared,
        "declared (const/enum/module_const), not ALL_CAPS": declared & ~caps & ident,
        "painted constant.def+constant.use": seg.role.isin(["constant.def", "constant.use"]),
    }
    seg = seg.copy()
    out = {}
    for name, mask in keys.items():
        seg["k"] = np.where(mask.fillna(False).values, name, None)
        r = stats_for(seg, lines, "k")
        out[name] = r.get(name, dict(char_share=0, token_share=0, per_screen_mean=0,
                                     per_screen_median=0, line_frac=0, char_count=0, token_count=0))
    return out


def binding_rows(seg, lines):
    seg = seg.copy()
    k = pd.Series(np.nan, index=seg.index, dtype=object)
    for r in ("function.def", "type.def", "macro.def", "constant.def"):
        k[seg.role == r] = r
    vd = seg.role == "variable.def"
    k[vd] = "variable.def." + seg.scope[vd].astype(str)
    k[(seg.role == "parameter") & (seg.dkind == "def")] = "parameter.def (locals)"
    k[(seg.role == "field") & (seg.dkind == "def")] = "field.def (locals)"
    seg["k"] = k
    rows = stats_for(seg, lines, "k")
    core = ["function.def", "type.def", "macro.def", "constant.def", "variable.def.top"]
    seg["k"] = np.where(seg.k.isin(core), "ALL beacon bindings (fn/type/macro/const/top var)", None)
    rows.update(stats_for(seg, lines, "k"))
    seg["k"] = np.where(k.notna(), "ALL bindings incl. local var/param/field", None)
    rows.update(stats_for(seg, lines, "k"))
    return rows


COLS = ["char_share", "token_share", "per_screen_mean", "per_screen_median", "line_frac"]


def write_csv(path, per_lang, pool, keyname):
    rows = []
    for lang, data in [("ALL", pool)] + list(per_lang.items()):
        for k, r in sorted(data.items(), key=lambda kv: -kv[1]["char_share"]):
            rows.append({"lang": lang, keyname: k, **{c: round(r[c], 6) for c in COLS}})
    pd.DataFrame(rows).to_csv(path, index=False)


def pct(x):
    return "-" if x == 0 else (f"{100 * x:.1f}%" if x >= 0.001 else f"{100 * x:.2f}%")


def wide(per_lang, pool, keys, col="char_share"):
    langs = list(per_lang)
    L = ["| | ALL | " + " | ".join(langs) + " |", "|---|---:|" + "---:|" * len(langs)]
    for k in keys:
        L.append(f"| {k} | {pct(pool.get(k, {}).get(col, 0))} | " +
                 " | ".join(pct(per_lang[l].get(k, {}).get(col, 0)) for l in langs) + " |")
    return L


def main():
    data = load()
    role_pl, bind_pl, const_pl = {}, {}, {}
    exit_raw = {}
    for lang, d in data.items():
        seg, lines = d["seg"], d["lines"]
        seg = seg.copy()
        seg["role2"] = seg.role.astype(str)
        rows = stats_for(seg, lines, "role2")
        vd = seg.role == "variable.def"
        seg["sub"] = np.where(vd, "variable.def." + seg.scope.astype(str), None)
        rows.update(stats_for(seg, lines, "sub"))
        # roles.yaml-selector keyword.exit (before text refinement), for comparison
        raw = seg.cap.isin(["keyword.return", "keyword.exception", "keyword.coroutine"]) | (
            seg.cap.astype(str).str.startswith("keyword") & seg.text.isin(["break", "continue"]))
        seg["sub"] = np.where(raw, "keyword.exit (raw selectors)", None)
        exit_raw[lang] = stats_for(seg, lines, "sub").get("keyword.exit (raw selectors)", {c: 0 for c in COLS})
        seg["sub"] = np.where(seg.role.eq("keyword.exit") & seg.text.eq("await"), "await", None)
        exit_raw[lang]["await"] = stats_for(seg, lines, "sub").get("await", {}).get("char_share", 0)
        role_pl[lang] = rows
        bind_pl[lang] = binding_rows(d["seg"], lines)
        const_pl[lang] = constant_rows(d["seg"], lines)
        print(lang, "done", flush=True)
    OUT.mkdir(exist_ok=True)
    rp, bp, cp = pooled(role_pl, COLS), pooled(bind_pl, COLS), pooled(const_pl, COLS)
    write_csv(OUT / "role_stats.csv", role_pl, rp, "role")
    write_csv(OUT / "binding_stats.csv", bind_pl, bp, "kind")
    write_csv(OUT / "constant_stats.csv", const_pl, cp, "class")
    write_md(data, role_pl, rp, bind_pl, bp, const_pl, cp, exit_raw)
    print("wrote out/role_stats.{csv,md}, out/binding_stats.csv, out/constant_stats.csv")


def write_md(data, role_pl, rp, bind_pl, bp, const_pl, cp, exit_raw):
    langs = list(role_pl)
    L = ["# Role statistics\n",
         "Generated by `harness/role_stats.py` from `harness/role_tokens.py`. Roles are the ids in "
         "`patterns/roles.yaml`. Each painted character's winning nvim-treesitter capture is mapped to "
         "a role by the most specific selector; uncaptured text is `default`. **ALL = unweighted mean "
         "over the 9 languages excluding elisp** (elisp's upstream query is sparse: no calls, no "
         "plain symbols, so ~41% of its ink is `default`; its rows are kept). ALL per_screen_median is "
         "the mean of per-language medians. Shares are of non-whitespace characters / tokens (token = "
         "one capture occurrence; uncaptured text split on whitespace). Screens = 40-line windows.\n",
         "## Char share by role\n"]
    order = sorted(rp, key=lambda k: -rp[k]["char_share"])
    order = [k for k in order if not k.startswith("variable.def.")]
    order.insert(order.index("variable.def") + 1, "variable.def.top")
    order.insert(order.index("variable.def") + 2, "variable.def.local")
    L += wide(role_pl, rp, order)
    L.append("\n`variable.def.top`/`.local` partition `variable.def` (top = not inside any "
             "function/method/lambda/closure; class bodies count as top).\n")
    L.append("## ALL: every column\n")
    L.append("| role | char share | token share | scr mean | scr median | lines |")
    L.append("|---|---:|---:|---:|---:|---:|")
    for k in order:
        r = rp[k]
        L.append(f"| {k} | {pct(r['char_share'])} | {pct(r['token_share'])} | {r['per_screen_mean']:.1f} | "
                 f"{r['per_screen_median']:.1f} | {pct(r['line_frac'])} |")
    L.append("\n## Token share by role\n")
    L += wide(role_pl, rp, order, "token_share")

    L.append("\n## Binding sites by kind (H4) — `out/binding_stats.csv`\n")
    L.append("Char share (all sites in the row are binding sites). parameter.def / field.def come "
             "from locals.scm `@local.definition.parameter/field` overlapping a parameter/field token "
             "(languages whose locals.scm lacks them show '-').\n")
    bk = ["function.def", "type.def", "macro.def", "constant.def", "variable.def.top", "variable.def.local",
          "parameter.def (locals)", "field.def (locals)",
          "ALL beacon bindings (fn/type/macro/const/top var)", "ALL bindings incl. local var/param/field"]
    L += wide(bind_pl, bp, bk)
    L.append("\nSame, token share:\n")
    L += wide(bind_pl, bp, bk, "token_share")
    L.append("\nSame, tokens per 40-line screen (mean):\n")
    langs_ = list(bind_pl)
    L.append("| | ALL | " + " | ".join(langs_) + " |")
    L.append("|---|---:|" + "---:|" * len(langs_))
    for k in bk:
        L.append(f"| {k} | {bp.get(k, {}).get('per_screen_mean', 0):.1f} | " + " | ".join(
            f"{bind_pl[l].get(k, {}).get('per_screen_mean', 0):.1f}" for l in langs_) + " |")

    L.append("\n## Readonly locals vs named constants (H5) — `out/constant_stats.csv`\n")
    L.append("Each row counts binding *and* use sites. Uses are resolved by name to a binding in the "
             "same innermost function, else to a file-level binding (no cross-file resolution, no "
             "shadowing, closures that use an outer function's local are unresolved). Classes come "
             "from the declaration construct: declared_const = Rust `const`/non-mut `static`, Go "
             "`const`, C `#define NAME` and top-level `const` objects, Java `static final` fields, "
             "elisp `defconst`, bash top-level `readonly`/`declare -r`; enum_member = Rust variants, "
             "C enumerators, Java enum constants, TS enum members; readonly_local = JS/TS `const` "
             "inside a function, Rust `let` without `mut`, Java `final` locals, C `const` locals (not "
             "pointer-to-const), Lua `<const>`, bash `local -r`. Python and Go have no readonly locals; "
             "Python has no declared constants. ALL_CAPS = `^_?[A-Z][A-Z0-9_]+$` on variable/constant/"
             "field tokens.\n")
    ck = list(next(iter(const_pl.values())).keys())
    L += wide(const_pl, cp, ck)
    L.append("\nSame, token share:\n")
    L += wide(const_pl, cp, ck, "token_share")
    L.append("\nReadonly locals as a fraction of all local-variable tokens (token share ratio): " + ", ".join(
        f"{l} {const_pl[l]['readonly_local (def+use)']['token_count'] / max(1, const_pl[l]['local variable, any (def+use)']['token_count']):.0%}"
        for l in langs) + ".\n")

    L.append("## keyword.exit: refined vs raw selectors\n")
    L.append("roles.yaml maps @keyword.exception and @keyword.coroutine to keyword.exit, but nvim paints "
             "try/catch/except/finally/else, async, Java `throws`, Rust `assert!`/`assert_eq!`/`panic!` "
             "macro names (and their `!`) and Lua's `coroutine` table with those captures. role_tokens.py "
             "keeps keyword.exit for exit words only (return, raise, throw, yield, await, break, "
             "continue, goto, from any keyword capture) and re-homes the rest (try/catch/... -> "
             "keyword.flow, async/throws -> keyword.decl, Rust assert macros -> macro.call, Lua "
             "coroutine -> module, others -> keyword.other). `goto` is included per the framework's "
             "exit family (C/Go only).\n")
    L.append("| | " + " | ".join(langs) + " |")
    L.append("|---|" + "---:|" * len(langs))
    L.append("| refined keyword.exit | " + " | ".join(pct(role_pl[l].get('keyword.exit', {}).get('char_share', 0)) for l in langs) + " |")
    L.append("| raw selectors | " + " | ".join(pct(exit_raw[l]['char_share']) for l in langs) + " |")
    L.append("| of which `await` (refined) | " + " | ".join(pct(exit_raw[l]['await']) for l in langs) + " |")

    L.append("\n## Binding-site detection coverage\n")
    for l in langs:
        d = data[l]
        s = d["seg"]
        b = s[s.role.isin(["variable.def", "constant.def"])]
        src = b.dsrc.value_counts().to_dict()
        imp = int((s.dkind == "import").sum())
        L.append(f"- {l}: " + (f"locals.scm {d['locals_patterns']} patterns ({len(d['locals_dropped'])} "
                 "dropped)" if d["locals_patterns"] else "**no locals.scm** (tree-sitter-elisp ships none); "
                 "binding = every @variable token, which its query only paints at defvar/defconst/let") +
                 f"; variable/constant bindings: {src.get('locals', 0)} via locals, "
                 f"{src.get('heuristic', 0)} via name-field heuristic, {src.get('query', 0)} via query; "
                 f"{imp} import-bound names left as use sites.")
    L.append("\n## Caveats\n")
    L += [
        "- Roles reflect what nvim-treesitter's queries paint. Python docstrings (@string.documentation) "
        "are `string` under roles.yaml, so Python's string share (34%) is largely docstrings. Bash "
        "`constant` is nvim's ALL_CAPS-variable heuristic (FOO in `$FOO`), so bash constant.* (~16%) "
        "is not about declared constants. Rust/C/Lua/Python/Java paint any ALL_CAPS identifier "
        "@constant, so constant.use mixes declared constants and convention.",
        "- No injections: comment.todo never fires (TODO markers live in the comment injection), "
        "and doc-comment markup stays comment/comment.doc.",
        "- locals.scm is incomplete: e.g. Rust `static` items, Java enum constants and some "
        "patterns are missed (partly recovered by the name-field heuristic), Lua global "
        "assignments are not definitions, Python re-assignments are (Python binding semantics). "
        "Function definitions come from highlights.scm (@function/@function.method). type.def = "
        "@type.definition plus @type tokens that locals.scm marks as definitions (most queries paint "
        "`class Foo`/`struct Foo` names as plain @type); Lua, bash and elisp have no type captures.",
        "- Import-bound names (@local.definition.import) are not counted as binding sites.",
        "- ALL rows average over 9 languages including zeros where a concept does not exist "
        "(no readonly locals in Python/Go/Lua in practice; no declared constants in Python).",
        "- Comment/string shares vary +/-10pp between codebases; token shares and per-screen "
        "counts are more stable.",
    ]
    (OUT / "role_stats.md").write_text("\n".join(L) + "\n")


if __name__ == "__main__":
    main()
