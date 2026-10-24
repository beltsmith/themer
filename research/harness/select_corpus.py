"""Randomly sample source files per language from data/corpus/ clones.

Caps each language at MAX_FILES files / MAX_LINES lines (whichever first),
seeded for reproducibility. Writes data/corpus_manifest.json (kept in git),
recording repo, commit and relative path of every selected file.

Run:  uv run python harness/select_corpus.py   (from research/)
"""
import json
import random
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORPUS = ROOT / "data" / "corpus"
SEED = 20261023
MAX_FILES = 150
MAX_LINES = 30_000
MAX_FILE_LINES = 6_000      # skip generated/amalgamated monsters
MAX_LINE_LEN = 500          # skip minified files

EXCLUDE_DIRS = {".git", "node_modules", "vendor", "deps", "third_party", "dist",
                "build", "target", "fixtures", "__snapshots__", ".github",
                "_meta"}  # neovim's generated API stubs (pure doc comments)

# lang -> (extensions, [(repo_dir, [subdirs])])
LANGS = {
    "python": ((".py",), [("psf_requests", ["src", "tests"]), ("pallets_flask", ["src", "tests", "examples"])]),
    "javascript": ((".js", ".mjs", ".cjs"), [("expressjs_express", ["lib", "test", "examples", "index.js"]),
                                             ("axios_axios", ["lib", "test", "examples", "index.js"])]),
    "typescript": ((".ts", ".mts"), [("colinhacks_zod", ["packages"]), ("sindresorhus_ky", ["source", "test"])]),
    "rust": ((".rs",), [("BurntSushi_ripgrep", ["crates"]), ("sharkdp_bat", ["src", "tests", "build"])]),
    "go": ((".go",), [("spf13_cobra", ["."]), ("gin-gonic_gin", ["."])]),
    "c": ((".c", ".h"), [("valkey-io_valkey", ["src"]), ("libuv_libuv", ["src", "include", "test"])]),
    "lua": ((".lua",), [("neovim_neovim", ["runtime/lua"]), ("nvim-telescope_telescope.nvim", ["lua", "plugin"])]),
    "bash": ((".sh", ".bash"), [("nvm-sh_nvm", ["."]), ("Bash-it_bash-it", ["."])]),
    "elisp": ((".el",), [("magit_magit", ["lisp"]), ("company-mode_company-mode", ["."])]),
    "java": ((".java",), [("google_gson", ["."]), ("apache_commons-lang", ["src"])]),
}


def candidates(repo, subdirs, exts):
    base = CORPUS / repo
    for sd in subdirs:
        p = base / sd
        files = [p] if p.is_file() else p.rglob("*")
        for f in files:
            if not f.is_file() or f.suffix not in exts or f.name.endswith(".d.ts"):
                continue
            rel = f.relative_to(base)
            if any(part in EXCLUDE_DIRS for part in rel.parts[:-1]):
                continue
            if "min." in f.name or ".gen." in f.name or f.name == "_meta.lua":
                continue
            yield f


def main():
    rng = random.Random(SEED)
    manifest = {"seed": SEED, "max_files": MAX_FILES, "max_lines": MAX_LINES, "repos": {}, "langs": {}}
    for lang, (exts, repos) in LANGS.items():
        pool = []
        for repo, subdirs in repos:
            sha = subprocess.run(["git", "-C", str(CORPUS / repo), "rev-parse", "HEAD"],
                                 capture_output=True, text=True).stdout.strip()
            manifest["repos"][repo] = sha
            for f in sorted(set(candidates(repo, subdirs, exts))):
                try:
                    text = f.read_text(encoding="utf-8")
                except (UnicodeDecodeError, OSError):
                    continue
                lines = text.splitlines()
                if not lines or len(lines) > MAX_FILE_LINES or max(map(len, lines)) > MAX_LINE_LEN:
                    continue
                pool.append((repo, str(f.relative_to(CORPUS / repo)), len(lines)))
        # interleave repos fairly: shuffle each repo's files then alternate
        by_repo = {}
        for item in pool:
            by_repo.setdefault(item[0], []).append(item)
        for v in by_repo.values():
            rng.shuffle(v)
        order = []
        while any(by_repo.values()):
            for k in list(by_repo):
                if by_repo[k]:
                    order.append(by_repo[k].pop())
        chosen, total = [], 0
        for repo, rel, n in order:
            if len(chosen) >= MAX_FILES or total >= MAX_LINES:
                break
            if total + n > MAX_LINES * 1.1:
                continue
            chosen.append({"repo": repo, "path": rel, "lines": n})
            total += n
        manifest["langs"][lang] = {"files": chosen, "n_files": len(chosen), "n_lines": total,
                                   "pool_files": len(pool)}
        per_repo = {}
        for c in chosen:
            per_repo[c["repo"]] = per_repo.get(c["repo"], 0) + c["lines"]
        print(f"{lang:11s} files={len(chosen):4d} lines={total:6d} pool={len(pool):5d} {per_repo}")
    out = ROOT / "data" / "corpus_manifest.json"
    out.write_text(json.dumps(manifest, indent=1))
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
