"""Draft 3.2: sample detected comment.code segments per language for a precision eyeball -> out/comment_code_samples.md.
    uv run --with pandas python harness/comment_code_samples.py
Seeded random sample of 10 per language from data/cache/role_tokens.pkl (text is the first 80 chars)."""
import pickle
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
data = pickle.load(open(ROOT / "data" / "cache" / "role_tokens.pkl", "rb"))
L = ["# comment.code samples (draft 3.2 heuristic)\n",
     "Seeded random sample of 10 detected segments per language, for a precision eyeball. Text is truncated to 80 chars and "
     "multi-line comments show their first line.\n"]
for lang, d in data.items():
    seg = d["seg"]
    cc = seg[seg.role == "comment.code"]
    allc = seg[seg.role.isin(["comment", "comment.code"])]
    L.append(f"## {lang}: {len(cc)} of {len(allc)} comments ({100 * len(cc) / max(1, len(allc)):.1f}%)\n")
    rng = random.Random(3)
    idx = rng.sample(range(len(cc)), min(10, len(cc)))
    for i in idx:
        r = cc.iloc[i]
        txt = r.text.splitlines()[0] if r.text else ""
        L.append(f"- `{d['files'][r.file].split('/', 1)[1][-40:]}:{r.l0 + 1}` `{txt.strip()}`")
    L.append("")
(ROOT / "out" / "comment_code_samples.md").write_text("\n".join(L))
