"""Load nvim-treesitter highlight queries for the python tree-sitter binding and
assign every byte of a file to its winning highlight capture.

Approximations of nvim semantics (see harness/README.md):
  * `; inherits: a,b` resolved recursively (parents first, so child patterns win).
  * `#lua-match?` / `#not-lua-match?` translated to `#match?` / `#not-match?`
    with a Lua-pattern -> regex conversion (character classes, `-` lazy quantifier).
  * `#eq?`, `#not-eq?`, `#any-of?`, `#match?` handled natively by py-tree-sitter.
  * `#has-ancestor?`, `#not-has-ancestor?`, `#has-parent?`, `#not-has-parent?`,
    `#contains?` implemented in a predicate callback; unknown predicates pass (true).
  * `#set! priority N` honoured (default 100); other `#set!`/directives ignored.
  * Parsers are built at nvim-treesitter's pinned revisions (build_parsers.py);
    if absent, tree-sitter-language-pack grammars are used and patterns that do
    not compile (grammar drift) are dropped one by one; counts are reported.
  * Injections (regex, doc comments, printf formats, embedded languages) are NOT run.
  * Paint order: (priority, start asc, end desc, pattern index) - so higher
    priority wins, then innermost node, then the later pattern in the file.
  * Captures named spell/nospell/conceal/_* are not highlights and are ignored;
    @none paints as "default".
"""
import ctypes
import re
from functools import lru_cache
from pathlib import Path

import tree_sitter_language_pack as tslp
from tree_sitter import Language, Query, QueryCursor, QueryError

ROOT = Path(__file__).resolve().parent.parent
NVIM_Q = ROOT / "data" / "nvim-treesitter" / "runtime" / "queries"
ELISP_Q = ROOT / "data" / "tree-sitter-elisp" / "queries" / "highlights.scm"

# our lang -> (language-pack parser name, query dir name)
PARSERS = {
    "python": ("python", "python"),
    "javascript": ("javascript", "javascript"),
    "typescript": ("typescript", "typescript"),
    "rust": ("rust", "rust"),
    "go": ("go", "go"),
    "c": ("c", "c"),
    "lua": ("lua", "lua"),
    "bash": ("bash", "bash"),
    "elisp": ("elisp", None),  # Wilfred/tree-sitter-elisp upstream queries
    "java": ("java", "java"),
}

IGNORED = {"spell", "nospell", "conceal"}

# Local rewrites for patterns that do not compile against the pack's grammar.
# Each operator becomes its own pattern so a missing token only drops itself.
_LUA_OPS = "+ - * / // % ^ # == ~= <= >= < > .. & | ~ << >>".split()
PATCHES = {
    "lua": [
        ("(binary_expression\n  operator: _ @operator)", "\n".join(f'"{o}" @operator' for o in _LUA_OPS)),
        ("(unary_expression\n  operator: _ @operator)", ""),
    ],
}

# ---------------------------------------------------------------- query text


def read_with_inherits(qname, seen=None):
    seen = seen or set()
    if qname in seen:
        return ""
    seen.add(qname)
    path = NVIM_Q / qname / "highlights.scm"
    if not path.exists():
        return ""
    text = path.read_text()
    parts = []
    m = re.search(r"^;+\s*inherits\s*:?\s*([\w,() ]+)$", text, re.M)
    if m:
        for parent in m.group(1).split(","):
            parent = parent.strip().strip("()")
            if parent:
                parts.append(read_with_inherits(parent, seen))
    parts.append(text)
    return "\n".join(parts)


LUA_CLASSES = {
    "a": "A-Za-z", "d": "0-9", "l": "a-z", "u": "A-Z", "s": " \\t\\n\\r\\f\\v",
    "w": "A-Za-z0-9", "x": "0-9A-Fa-f", "p": "!-/:-@\\[-`{-~", "c": "\\x00-\\x1f",
}


def lua_to_regex(pat):
    out, i, in_set = [], 0, False
    while i < len(pat):
        ch = pat[i]
        if ch == "%" and i + 1 < len(pat):
            n = pat[i + 1]
            if n in LUA_CLASSES:
                cls = LUA_CLASSES[n]
                out.append(cls if in_set else f"[{cls}]")
            elif n.upper() in LUA_CLASSES and n.isupper():
                out.append(f"[^{LUA_CLASSES[n.lower()]}]")
            else:
                out.append(re.escape(n) if not in_set else ("\\" + n if n in "]\\^-" else n))
            i += 2
            continue
        if ch == "[" and not in_set:
            in_set = True
            out.append("[")
            if i + 1 < len(pat) and pat[i + 1] == "^":
                out.append("^")
                i += 1
        elif ch == "]" and in_set:
            in_set = False
            out.append("]")
        elif ch == "-" and not in_set:
            out.append("*?")
        elif ch == "\\":
            out.append("\\\\")
        else:
            out.append(ch)
        i += 1
    return "".join(out)


def translate_predicates(text):
    def repl(m):
        neg, cap, s = m.group(1), m.group(2), m.group(3)
        rx = lua_to_regex(s.encode().decode("unicode_escape"))
        if "." in rx:
            rx = "(?s)" + rx  # Lua '.' also matches newlines
        rx = rx.replace("\\", "\\\\").replace('"', '\\"')
        return f'(#{"not-" if neg else ""}match? {cap} "{rx}")'
    return re.sub(r'\(#(not-)?lua-match\?\s+(@[\w.]+)\s+"((?:[^"\\]|\\.)*)"\s*\)', repl, text)


def split_patterns(text):
    """Split query source into top-level patterns (each with trailing captures)."""
    chunks, i, n = [], 0, len(text)
    cur_start, depth = None, 0
    def flush(end):
        nonlocal cur_start
        if cur_start is not None:
            chunks.append(text[cur_start:end])
        cur_start = None
    while i < n:
        c = text[i]
        if c == ";":
            j = text.find("\n", i)
            i = n if j < 0 else j + 1
            continue
        if c == '"':
            if depth == 0 and cur_start is None:
                cur_start = i
            elif depth == 0 and _ends_pattern(text, cur_start, i):
                flush(i); cur_start = i
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            i = j + 1
            continue
        if c in "([":
            if depth == 0:
                if cur_start is None:
                    cur_start = i
                elif _ends_pattern(text, cur_start, i):
                    flush(i); cur_start = i
            depth += 1
        elif c in ")]":
            depth -= 1
        elif depth == 0 and not c.isspace() and cur_start is None:
            cur_start = i
        i += 1
    flush(n)
    return [c for c in chunks if c.strip()]


def _ends_pattern(text, start, i):
    # a new top-level form starts a new pattern unless the previous one is
    # still waiting for something (it always isn't at depth 0 in highlights)
    return True


PARSER_DIR = ROOT / "data" / "parsers"


def get_language(lang):
    """Prefer the parser built at nvim-treesitter's pinned revision
    (harness/build_parsers.py); fall back to tree-sitter-language-pack."""
    so = PARSER_DIR / f"{lang}.so"
    if so.exists():
        lib = ctypes.cdll.LoadLibrary(str(so))
        fn = getattr(lib, f"tree_sitter_{lang}")
        fn.restype = ctypes.c_void_p
        return Language(fn()), "pinned"
    return tslp.get_language(PARSERS[lang][0]), "language-pack"


@lru_cache(maxsize=None)
def load(lang):
    pname, qname = PARSERS[lang]
    language, origin = get_language(lang)
    src = ELISP_Q.read_text() if qname is None else read_with_inherits(qname)
    if origin == "language-pack":
        for old, new in PATCHES.get(lang, []):
            assert old in src, (lang, old)
            src = src.replace(old, new)
    src = translate_predicates(src)
    pats = split_patterns(src)
    kept, dropped = [], []
    for p in pats:
        try:
            Query(language, p)
            kept.append(p)
        except QueryError as e:
            dropped.append((p.strip().splitlines()[0][:80], str(e).splitlines()[0][:80]))
    query = Query(language, "\n".join(kept))
    return language, query, len(pats), dropped


# ---------------------------------------------------------------- predicates


def _node_text(n):
    return n.text.decode("utf-8", "replace") if n.text is not None else ""


def predicate(name, args, pattern_index, captures):
    def nodes():
        cap = args[0][0]
        return captures.get(cap, [])
    strs = [a for a, kind in args[1:] if kind == "string"]
    if name in ("has-ancestor?", "not-has-ancestor?"):
        ok = False
        for n in nodes():
            p = n.parent
            while p is not None:
                if p.type in strs:
                    ok = True
                    break
                p = p.parent
        return ok if name == "has-ancestor?" else not ok
    if name in ("has-parent?", "not-has-parent?"):
        ok = any(n.parent is not None and n.parent.type in strs for n in nodes())
        return ok if name == "has-parent?" else not ok
    if name == "contains?":
        return any(any(s in _node_text(n) for s in strs) for n in nodes())
    return True


# ---------------------------------------------------------------- painting


def paint(lang, source: bytes):
    """Return (tree, names, owner) where owner[i] is an index into `names`-tagged
    occurrence list for byte i (or -1 for default). `occ` is list of capture names
    per occurrence id."""
    language, query, _, _ = load(lang)
    from tree_sitter import Parser
    parser = Parser(language)
    tree = parser.parse(source)
    cursor = QueryCursor(query)
    occs = []  # (priority, start, -end, pattern, name, start, end)
    for pidx, caps in cursor.matches(tree.root_node, predicate):
        settings = query.pattern_settings(pidx) or {}
        try:
            prio = int(settings.get("priority", 100))
        except (TypeError, ValueError):
            prio = 100
        for cname, nodes in caps.items():
            if cname.startswith("_") or cname in IGNORED or cname.split(".")[0] in IGNORED:
                continue
            for nd in nodes:
                if nd.end_byte > nd.start_byte:
                    occs.append((prio, nd.start_byte, -nd.end_byte, pidx, cname))
    occs.sort()
    owner = [-1] * len(source)
    names = []
    for k, (prio, s, ne, pidx, cname) in enumerate(occs):
        names.append(cname)
        owner[s:-ne] = [k] * (-ne - s)
    return tree, names, owner
