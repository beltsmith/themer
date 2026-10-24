"""Paint the corpus with roles from patterns/roles.yaml and cache one row per
visible token segment, for role_stats.py, recoverability.py and adjacency.py.

Role assignment (most specific capture wins, as in highlight.py):
  * The winning highlight capture of each byte is mapped to a role id with the
    `captures` selectors of patterns/roles.yaml; an unlisted capture falls back
    by dropping its last dotted component (@function.method.call -> function.call
    via @function.method.call; @string.special.path -> @string.special ->
    string.escape). Uncaptured text and @none -> `default`.
  * @variable / @constant / @constant.macro tokens are split into binding vs use
    sites with the language's nvim-treesitter locals.scm `@local.definition*`
    captures (token node, or one of its 3 nearest ancestors, has exactly the span
    of a definition capture; `.associated` is ignored).  Supplementary
    heuristic: a token that is the `name` field of a *_item / *_declaration /
    *_definition / *_spec / enumerator / enum_variant / enum_constant node is
    also a binding (catches Rust static/enum variants, Java enum constants...).
    elisp has no locals.scm; its query only paints @variable at defvar/defconst
    names and let bindings, so every elisp @variable token is a binding.
  * Binding scope: `top` = no enclosing function/method/lambda/closure node
    (class bodies count as top), else `local`.
  * @type tokens that are a locals.scm definition (or the name field of a
    declaration node) -> type.def: most queries paint `class Foo`/`struct Foo`
    names as plain @type, and @type.definition only covers typedef-like forms.
  * @function.macro -> macro.def when its parent node is a definition
    (macro_definition, preproc_function_def, preproc_def), else macro.call.
  * keyword.exit = exit words only: any @keyword* token whose text is
    return/raise/throw/yield/await/break/continue/goto.  roles.yaml's selectors
    for keyword.exit (@keyword.exception, @keyword.coroutine) also paint
    try/catch/except/finally/else (-> keyword.flow), async/throws
    (-> keyword.decl), Rust assert!/panic! macro names (-> macro.call) and Lua's
    `coroutine` table (-> module); those are re-homed by text.
  * Import bindings (@local.definition.import) are not binding sites: they stay
    variable.use / constant.use with dkind="import".

A segment = maximal run of bytes owned by one capture occurrence, trimmed of
surrounding whitespace (strings/comments keep inner spaces); uncaptured text is
split on whitespace.  `occ` identifies the occurrence, so a string broken by an
escape is two segments of one token.

Writes data/cache/role_tokens.pkl  ({lang: {"seg": DataFrame, "lines": {...}}}).
Run: uv run --with tree-sitter --with tree-sitter-language-pack --with pandas \
       --with pyyaml python harness/role_tokens.py
"""
import json
import pickle
import re
import sys
from concurrent.futures import ProcessPoolExecutor
from functools import lru_cache
from pathlib import Path

import pandas as pd
import yaml
from tree_sitter import Parser, Query, QueryCursor, QueryError

sys.path.insert(0, str(Path(__file__).resolve().parent))
import highlight  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
CORPUS = ROOT / "data" / "corpus"
CACHE = ROOT / "data" / "cache"
WS = set(b" \t\r\n\f\v")

# ------------------------------------------------------------------ roles

SPLIT = {"variable": "variable", "constant": "constant", "constant.macro": "constant",
         "function.macro": "macro"}


@lru_cache(maxsize=None)
def selector_map():
    roles = yaml.safe_load((ROOT / "patterns" / "roles.yaml").read_text())["roles"]
    m = {}
    for r in roles:
        for c in r.get("captures", []) or []:
            c = c.lstrip("@")
            if c.startswith("local."):
                continue
            m.setdefault(c, r["id"])
    return m


def capture_role(cap):
    """Static capture -> role (before site splitting)."""
    if cap in ("none", "default"):
        return "default"
    if cap in SPLIT:
        return SPLIT[cap]
    m = selector_map()
    parts = cap.split(".")
    while parts:
        k = ".".join(parts)
        if k in SPLIT:
            return SPLIT[k]
        if k in m:
            return m[k]
        parts.pop()
    return "default"


EXIT_WORDS = {"return", "raise", "throw", "yield", "break", "continue", "goto"}  # not await: it resumes
# roles.yaml's keyword.exit selectors (@keyword.exception, @keyword.coroutine) also
# paint non-exits; those are re-homed by text (documented in role_stats.md).
NON_EXIT = {"try": "keyword.flow", "catch": "keyword.flow", "except": "keyword.flow",
            "finally": "keyword.flow", "else": "keyword.flow",
            "async": "keyword.decl", "throws": "keyword.decl"}

# ------------------------------------------------------------------ locals


def read_locals(qname, seen=None):
    seen = seen or set()
    if qname in seen:
        return ""
    seen.add(qname)
    path = highlight.NVIM_Q / qname / "locals.scm"
    if not path.exists():
        return ""
    text = path.read_text()
    parts = []
    m = re.search(r"^;+\s*inherits\s*:?\s*([\w,() ]+)$", text, re.M)
    if m:
        for parent in m.group(1).split(","):
            parent = parent.strip().strip("()")
            if parent:
                parts.append(read_locals(parent, seen))
    parts.append(text)
    return "\n".join(parts)


@lru_cache(maxsize=None)
def load_locals(lang):
    qname = highlight.PARSERS[lang][1]
    if qname is None:
        return None, 0, []
    language = highlight.load(lang)[0]
    src = highlight.translate_predicates(read_locals(qname))
    kept, dropped = [], []
    for p in highlight.split_patterns(src):
        try:
            Query(language, p)
            kept.append(p)
        except QueryError as e:
            dropped.append(str(e).splitlines()[0][:80])
    return Query(language, "\n".join(kept)), len(kept) + len(dropped), dropped


FUNC_TYPES = {
    "function_definition", "function_declaration", "function_item", "function_expression",
    "function", "arrow_function", "method_definition", "method_declaration",
    "constructor_declaration", "compact_constructor_declaration", "lambda",
    "lambda_expression", "closure_expression", "func_literal", "generator_function",
    "generator_function_declaration", "static_initializer", "macro_definition",
}
DECL_PARENT = re.compile(r"(_item|_declaration|_definition|_spec|^enumerator|^enum_variant|"
                         r"^enum_constant|^enum_assignment|^property_signature)$")


def enclosing_func(node):
    p = node.parent
    while p is not None:
        if p.type in FUNC_TYPES:
            return p
        p = p.parent
    return None


def ancestors(node, limit=12):
    p, k = node.parent, 0
    while p is not None and k < limit:
        yield p
        p, k = p.parent, k + 1


def _child_types(n):
    return [c.type for c in n.children]


def _text(n):
    return n.text.decode("utf-8", "replace") if n.text is not None else ""


def decl_class(lang, node, local):
    """Classify a binding identifier by the language's declaration construct.
    Returns one of: declared_const, enum_member, module_const (JS/TS top-level
    `const`), readonly_local, mutable."""
    anc = list(ancestors(node))
    types = [a.type for a in anc]
    if lang in ("javascript", "typescript"):
        for a in anc:
            if a.type == "lexical_declaration":
                if a.children and a.children[0].type == "const":
                    return "readonly_local" if local else "module_const"
                return "mutable"
            if a.type == "enum_body" or a.type == "enum_assignment":
                return "enum_member"
            if a.type in FUNC_TYPES or a.type == "statement_block":
                break
        return "mutable"
    if lang == "rust":
        for a in anc:
            if a.type in ("const_item",):
                return "declared_const"
            if a.type == "static_item":
                return "mutable" if "mutable_specifier" in _child_types(a) else "declared_const"
            if a.type in ("enum_variant",):
                return "enum_member"
            if a.type == "mut_pattern":
                return "mutable"
            if a.type == "let_declaration":
                return "mutable" if "mutable_specifier" in _child_types(a) else "readonly_local"
            if a.type in ("block", "function_item", "closure_expression"):
                break
        return "mutable"
    if lang == "go":
        if "const_spec" in types[:3]:
            return "declared_const"
        return "mutable"
    if lang == "c":
        for a in anc[:6]:
            if a.type == "enumerator":
                return "enum_member"
            if a.type in ("preproc_def",):
                return "declared_const"
            if a.type == "declaration":
                quals = [c for c in a.children if c.type == "type_qualifier" and _text(c) == "const"]
                # const T *p is a pointer to const, not a readonly binding
                ptr = any(t == "pointer_declarator" for t in types[:types.index("declaration")])
                if quals and not ptr:
                    return "readonly_local" if local else "declared_const"
                return "mutable"
        return "mutable"
    if lang == "java":
        for a in anc[:4]:
            if a.type == "enum_constant":
                return "enum_member"
            if a.type in ("field_declaration", "constant_declaration", "local_variable_declaration"):
                mods = [c for c in a.children if c.type == "modifiers"]
                mt = _text(mods[0]) if mods else ""
                final = re.search(r"\bfinal\b", mt) is not None
                if a.type == "constant_declaration":
                    return "declared_const"
                if a.type == "field_declaration":
                    return "declared_const" if final and re.search(r"\bstatic\b", mt) else "mutable"
                return "readonly_local" if final else "mutable"
        return "mutable"
    if lang == "lua":
        for a in anc[:4]:
            if a.type == "variable_declaration":
                if re.search(r"<\s*(const|close)\s*>", _text(a).split("=")[0]):
                    return "readonly_local" if local else "declared_const"
                return "mutable"
        return "mutable"
    if lang == "bash":
        for a in anc[:3]:
            if a.type == "declaration_command":
                t = _text(a)
                if t.startswith("readonly") or re.match(r"(declare|local|typeset)\s+(-\w*r)", t):
                    return "readonly_local" if local else "declared_const"
                return "mutable"
        return "mutable"
    if lang == "elisp":
        for a in anc[:3]:
            if a.type == "special_form" and a.child_count > 1:
                return "declared_const" if _text(a.children[1]) == "defconst" else "mutable"
        return "mutable"
    return "mutable"  # python: no declared constants


# ------------------------------------------------------------------ painting


def paint_occurrences(lang, src):
    language, query, _, _ = highlight.load(lang)
    tree = Parser(language).parse(src)
    occs = []
    for pidx, caps in QueryCursor(query).matches(tree.root_node, highlight.predicate):
        settings = query.pattern_settings(pidx) or {}
        try:
            prio = int(settings.get("priority", 100))
        except (TypeError, ValueError):
            prio = 100
        for cname, nodes in caps.items():
            if cname.startswith("_") or cname in highlight.IGNORED or cname.split(".")[0] in highlight.IGNORED:
                continue
            for nd in nodes:
                if nd.end_byte > nd.start_byte:
                    occs.append((prio, nd.start_byte, -nd.end_byte, pidx, cname, nd))
    occs.sort(key=lambda o: o[:5])
    owner = [-1] * len(src)
    for k, (_, s, ne, _, _, _) in enumerate(occs):
        owner[s:-ne] = [k] * (-ne - s)
    return tree, occs, owner


def local_defs(lang, tree):
    q = load_locals(lang)[0]
    if q is None:
        return {}
    defs = {}
    for _, caps in QueryCursor(q).matches(tree.root_node, highlight.predicate):
        for cname, nodes in caps.items():
            if cname.startswith("local.definition") and not cname.endswith("associated"):
                kind = cname[len("local.definition"):].lstrip(".") or "bare"
                for nd in nodes:
                    defs.setdefault((nd.start_byte, nd.end_byte), kind)
    return defs


def def_kind(node, defs):
    n = node
    for _ in range(4):
        if n is None:
            break
        k = defs.get((n.start_byte, n.end_byte))
        if k is not None:
            return k, "locals"
        n = n.parent
    p = node.parent
    if p is not None and DECL_PARENT.search(p.type):
        nm = p.child_by_field_name("name")
        if nm is not None and nm.start_byte == node.start_byte and nm.end_byte == node.end_byte:
            return "name_field", "heuristic"
    return None, None


def char_of(b):
    if b is None:
        return "^"
    return chr(b) if b < 0x80 else "~"


def analyse(job):
    lang, fidx, path = job
    src = path.read_bytes()
    tree, occs, owner = paint_occurrences(lang, src)
    defs = local_defs(lang, tree)
    n = len(src)
    # line starts
    line_of = []
    ln = 0
    for b in src:
        line_of.append(ln)
        if b == 10:
            ln += 1
    nonblank = sorted({line_of[i] for i in range(n) if src[i] not in WS})

    # per-occurrence role + binding info
    occ_info = {}

    def info(k):
        if k in occ_info:
            return occ_info[k]
        _, s, ne, _, cap, nd = occs[k]
        cap = "default" if cap == "none" else cap
        role = capture_role(cap)
        rec = {"cap": cap, "role": role, "scope": "", "dkind": "", "dsrc": "", "cls": "",
               "func": -1}
        text = src[s:-ne].decode("utf-8", "replace")
        if role.startswith("keyword") and text in EXIT_WORDS:
            rec["role"] = "keyword.exit"
        elif role.startswith("keyword") and lang == "rust" and src[-ne:-ne + 1] == b"!":
            rec["role"] = "macro.call"  # assert!/panic! painted as keywords by nvim queries
        elif role == "keyword.exit":
            if text in NON_EXIT:
                rec["role"] = NON_EXIT[text]
            elif lang == "rust":  # assert!/assert_eq!/panic! macro names and their `!`
                rec["role"] = "macro.call"
            elif text == "coroutine":  # lua: the coroutine library table
                rec["role"] = "module"
            else:  # python `raise .. from`, go `go`
                rec["role"] = "keyword.other"
        elif cap == "type":
            kind, srcd = def_kind(nd, defs)
            if kind is not None and kind != "import":
                rec["role"], rec["dkind"], rec["dsrc"] = "type.def", kind, srcd
        elif role in ("variable", "constant", "parameter", "field", "macro"):
            f = enclosing_func(nd)
            rec["func"] = f.start_byte if f is not None else -1
            local = f is not None
            if lang == "elisp" and role == "variable":
                kind, srcd = "var", "query"
            else:
                kind, srcd = def_kind(nd, defs)
            if role == "macro":
                isdef = nd.parent is not None and nd.parent.type in (
                    "macro_definition", "preproc_function_def", "preproc_def")
                rec["role"] = "macro.def" if isdef else "macro.call"
            elif role in ("parameter", "field"):
                rec["dkind"] = "def" if kind is not None else ""
            elif kind is not None and kind != "import":
                rec["role"] = role + ".def"
                rec["scope"] = "local" if local else "top"
                rec["dkind"], rec["dsrc"] = kind, srcd
                rec["cls"] = decl_class(lang, nd, local)
            else:
                rec["role"] = role + ".use"
                rec["dkind"] = kind or ""  # "import" bindings stay use-coloured
        occ_info[k] = rec
        return rec

    rows = []
    i = 0
    while i < n:
        b = src[i]
        if b in WS:
            i += 1
            continue
        k = owner[i]
        j = i
        if k >= 0:
            while j < n and owner[j] == k:
                j += 1
            e = j
            while e > i and src[e - 1] in WS:
                e -= 1
            rec = info(k)
            occ = k
        else:
            while j < n and owner[j] == -1 and src[j] not in WS:
                j += 1
            e = j
            rec = {"cap": "default", "role": "default", "scope": "", "dkind": "", "dsrc": "",
                   "cls": "", "func": -1}
            occ = -1 - i
        seg = src[i:e]
        p = i - 1
        while p >= 0 and src[p] in WS:
            p -= 1
        q = e
        while q < n and src[q] in WS:
            q += 1
        nch = sum(1 for c in seg if c not in WS and not (0x80 <= c < 0xC0))
        rows.append((fidx, occ, rec["role"], rec["cap"], seg[:80].decode("utf-8", "replace"),
                     i, e, line_of[i], line_of[e - 1], nch,
                     char_of(src[p] if p >= 0 else None), char_of(src[q] if q < n else None),
                     rec["scope"], rec["dkind"], rec["dsrc"], rec["cls"], rec["func"]))
        i = j
    return lang, fidx, rows, nonblank


COLS = ["file", "occ", "role", "cap", "text", "s", "e", "l0", "l1", "nch", "prevc", "nextc",
        "scope", "dkind", "dsrc", "cls", "func"]


def main():
    manifest = json.loads((ROOT / "data" / "corpus_manifest.json").read_text())
    jobs = []
    files = {}
    for lang, info in manifest["langs"].items():
        files[lang] = [f"{f['repo']}/{f['path']}" for f in info["files"]]
        for fi, f in enumerate(info["files"]):
            jobs.append((lang, fi, CORPUS / f["repo"] / f["path"]))
    out = {lang: {"rows": [], "lines": {}, "files": files[lang]} for lang in files}
    with ProcessPoolExecutor() as ex:
        for lang, fi, rows, nonblank in ex.map(analyse, jobs, chunksize=4):
            out[lang]["rows"].extend(rows)
            out[lang]["lines"][fi] = nonblank
    res = {}
    for lang, d in out.items():
        df = pd.DataFrame(d["rows"], columns=COLS)
        for c in ("role", "cap", "scope", "dkind", "dsrc", "cls", "prevc", "nextc"):
            df[c] = df[c].astype("category")
        q = load_locals(lang)
        res[lang] = {"seg": df, "lines": d["lines"], "files": d["files"],
                     "locals_patterns": q[1], "locals_dropped": q[2]}
        unk = sorted({c for c in df["cap"].unique() if capture_role(c) == "default"} - {"default", "none"})
        print(f"{lang:11s} segs={len(df)} roles={df['role'].nunique()} locals={q[1]} "
              f"dropped={len(q[2])} unmapped_caps={unk}", flush=True)
    CACHE.mkdir(parents=True, exist_ok=True)
    with (CACHE / "role_tokens.pkl").open("wb") as fh:
        pickle.dump(res, fh)
    print("wrote", CACHE / "role_tokens.pkl")


if __name__ == "__main__":
    main()
