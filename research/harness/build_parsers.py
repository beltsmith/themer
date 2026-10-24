"""Build tree-sitter parsers at exactly the revisions nvim-treesitter pins
(lua/nvim-treesitter/parsers.lua), so its highlights.scm queries match the
grammar they were written for. tree-sitter-language-pack's newer grammars
drift (e.g. python's expression_statement became hidden, which makes the
docstring pattern match every string).

Output: data/parsers/<lang>.so  (elisp: built from data/tree-sitter-elisp HEAD).
Run:  uv run python harness/build_parsers.py   (needs git + cc)
"""
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
OUT = DATA / "parsers"
LOCK = DATA / "nvim-treesitter" / "lua" / "nvim-treesitter" / "parsers.lua"
LANGS = ["python", "javascript", "typescript", "rust", "go", "c", "lua", "bash", "java"]


def pinned(lang):
    text = LOCK.read_text()
    m = re.search(rf"^  {lang} = \{{\n(.*?)^  \}},", text, re.M | re.S)
    block = m.group(1)
    get = lambda k: (re.search(rf"{k} = '([^']+)'", block) or [None, None])[1]  # noqa: E731
    return get("url"), get("revision"), get("location")


def sh(*args, cwd=None):
    subprocess.run(args, cwd=cwd, check=True, capture_output=True)


def compile_so(src_dir, so):
    srcs = [str(src_dir / "parser.c")]
    if (src_dir / "scanner.c").exists():
        srcs.append(str(src_dir / "scanner.c"))
    sh("cc", "-shared", "-fPIC", "-O2", "-I", str(src_dir), *srcs, "-o", str(so))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    meta = {}
    for lang in LANGS:
        url, rev, loc = pinned(lang)
        repo = OUT / "src" / url.rstrip("/").split("/")[-1]
        if not (repo / ".git").exists():
            repo.mkdir(parents=True, exist_ok=True)
            sh("git", "init", "-q", cwd=repo)
            sh("git", "remote", "add", "origin", url, cwd=repo)
        sh("git", "fetch", "-q", "--depth", "1", "origin", rev, cwd=repo)
        sh("git", "checkout", "-q", "FETCH_HEAD", cwd=repo)
        src = (repo / loc / "src") if loc else (repo / "src")
        compile_so(src, OUT / f"{lang}.so")
        meta[lang] = f"{url}@{rev}" + (f" ({loc})" if loc else "")
        print(f"{lang:11s} {meta[lang]}")
    compile_so(DATA / "tree-sitter-elisp" / "src", OUT / "elisp.so")
    rev = subprocess.run(["git", "-C", str(DATA / "tree-sitter-elisp"), "rev-parse", "HEAD"],
                         capture_output=True, text=True).stdout.strip()
    print(f"elisp       https://github.com/Wilfred/tree-sitter-elisp@{rev}")


if __name__ == "__main__":
    main()
