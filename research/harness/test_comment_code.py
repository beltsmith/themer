"""Unit tests for the draft 3.2 comment.code heuristic (role_tokens.is_commented_code).
    uv run --with tree-sitter --with tree-sitter-language-pack --with pandas --with pyyaml python harness/test_comment_code.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from role_tokens import is_commented_code as f  # noqa: E402

CODE = [
    "// let x = compute(a, b);",                    # rust/c statement
    "# if user.is_admin:",                          # python block opener
    "#   result = fetch(url)",                      # python assignment
    "-- local n = #items",                          # lua assignment
    ";; (setq fill-column 100)",                    # elisp form
    "// }",                                         # closing brace
    "/* printf(\"%d\\n\", n); */",                  # c block, call
    "// self.cache.insert(key, value)",             # member call, no semicolon
    "# foo.bar = 3",
    "// if (x > 0) {",
    "//\tl, _ := net.Listen(\"tcp\", \":8033\")",   # go multi-assign
    "// return validate(obj)",
    "// assertArrayEquals(new",                     # continued call
]
PROSE = [
    "// This function returns the number of items in the list.",
    "# TODO: handle the empty case",
    "// Note: the lock must be held (see below)",
    "# The parser calls foo(bar) when it sees a comma and then stops",   # prose that mentions code
    "// we use `retry(3)` here because the server is flaky on startup",  # prose that mentions code
    "# Returns x if the cache is warm, otherwise y",
    "// e.g. a path like /tmp/foo",
    "/** Computes the sum of a and b. */",
    "#!/usr/bin/env python",
    "// ---------------------------------",
    "// see https://example.com/x(y);",
    "// send() detects HEAD",
    "// disambiguate app.use([fn])",
    "# If PAGER=bat, silently use 'less' instead to prevent",
    ";;;###autoload(autoload 'magit-log \"magit-log\" nil t)",
    ";;; mode ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;",
    "# shellcheck disable=SC2086",
    "// 127.65535 (tail 0xFFFF into 3 slots) -> 127.0.255.255;",
]

def main():
    bad = [t for t in CODE if not f(t)] + [t for t in PROSE if f(t)]
    for t in CODE:
        print("code ", f(t), t)
    for t in PROSE:
        print("prose", f(t), t)
    assert not bad, f"misclassified: {bad}"
    print(f"OK ({len(CODE)} code, {len(PROSE)} prose)")

if __name__ == "__main__":
    main()
