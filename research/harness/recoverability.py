"""Lexical recoverability of roles (framework H2 / C3, H7).

Per language, a multinomial logistic regression predicts each visible token
segment's role (harness/role_tokens.py) from LEXICAL features only - no tree:
  * text shape: case class (lower / Capitalised / CAPS / mixed / none), snake_,
    camelCase, has-digit, length bucket, first-char class, first char and first
    two chars when not alphanumeric, last char when not alphanumeric
  * the exact text when it is one of the language's 300 most frequent segment
    texts (approximates closed classes: keywords, operators, punctuation)
  * previous and next non-whitespace character
  * previous segment's text when in the top 300
  * two conjunctions: shape x next char, shape x previous char (LR has no
    interactions otherwise; `foo(` vs `foo.` vs `Foo` is what readers use)
Evaluation: GroupKFold(5) by file, out-of-fold predictions.  Recoverability(role)
= recall.  Baseline = majority class.  Pairwise separability for every pair in
patterns/weights.yaml: binary LR on the segments of those two roles only
(accuracy, balanced accuracy, majority baseline).  ALL = mean over languages
excluding elisp (sparse query; its rows are kept).

Writes out/recoverability.csv, out/recoverability_confusion.csv,
out/recoverability_pairs.csv, out/recoverability.md.
Run: uv run --with pandas --with numpy --with scikit-learn --with pyyaml \
       python harness/recoverability.py
"""
import pickle
import re
import warnings
from collections import Counter
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np
import pandas as pd
import yaml
from sklearn.feature_extraction import DictVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import GroupKFold

warnings.filterwarnings("ignore")
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "out"
TOPN = 300
FOLDS = 5
EXCLUDE_FROM_ALL = {"elisp"}


def shape(t):
    letters = [c for c in t if c.isalpha()]
    if not letters:
        case = "none"
    elif all(c.islower() for c in letters):
        case = "lower"
    elif all(c.isupper() for c in letters):
        case = "caps" if len(letters) > 1 else "cap1"
    elif t[0].isupper() and all(c.islower() for c in letters[1:]):
        case = "Capitalised"
    else:
        case = "mixed"
    return case


def lenb(n):
    return "1" if n == 1 else "2" if n == 2 else "3-4" if n <= 4 else "5-8" if n <= 8 else \
        "9-16" if n <= 16 else "17-40" if n <= 40 else "41+"


def fclass(c):
    if c in "\"'`":
        return "quote"
    if c.isdigit():
        return "digit"
    if c.isalpha():
        return "alpha"
    if c == "_":
        return "underscore"
    return "punct"


def features(seg):
    texts = seg.text.astype(str).tolist()
    top = {t for t, _ in Counter(texts).most_common(TOPN)}
    prevc = seg.prevc.astype(str).tolist()
    nextc = seg.nextc.astype(str).tolist()
    files = seg.file.tolist()
    feats = []
    prev_text = None
    prev_file = None
    for i, t in enumerate(texts):
        if files[i] != prev_file:
            prev_text, prev_file = "^", files[i]
        sh = shape(t)
        f = {"case=" + sh: 1, "len=" + lenb(len(t)): 1, "first=" + fclass(t[0]): 1,
             "pc=" + prevc[i]: 1, "nc=" + nextc[i]: 1,
             "sh_nc=" + sh + nextc[i]: 1, "sh_pc=" + sh + prevc[i]: 1}
        if re.search(r"[A-Za-z0-9]_[A-Za-z0-9]", t):
            f["snake"] = 1
        if re.search(r"[a-z][A-Z]", t):
            f["camel"] = 1
        if any(c.isdigit() for c in t):
            f["digit"] = 1
        if not t[0].isalnum():
            f["c0=" + t[0]] = 1
            if len(t) > 1 and not t[1].isalnum():
                f["c01=" + t[:2]] = 1
                if len(t) > 2 and not t[2].isalnum():
                    f["c012=" + t[:3]] = 1
        if not t[-1].isalnum():
            f["cN=" + t[-1]] = 1
        if t in top:
            f["tok=" + t] = 1
        if prev_text in top or prev_text == "^":
            f["prev=" + prev_text] = 1
        feats.append(f)
        prev_text = t
    return feats


def model():
    return LogisticRegression(max_iter=400, C=1.0, tol=1e-3)


def oof_predict(X, y, groups):
    pred = np.empty(len(y), dtype=object)
    for tr, te in GroupKFold(n_splits=FOLDS).split(X, y, groups):
        classes = np.unique(y[tr])
        if len(classes) == 1:
            pred[te] = classes[0]
            continue
        m = model().fit(X[tr], y[tr])
        pred[te] = m.predict(X[te])
    return pred


def run_lang(args):
    lang, seg, pairs = args
    seg = seg.sort_values(["file", "s"]).reset_index(drop=True)
    X = DictVectorizer().fit_transform(features(seg))
    y = seg.role.astype(str).values
    g = seg.file.values
    pred = oof_predict(X, y, g)
    roles = sorted(set(y))
    rows = []
    for r in roles:
        t, p = y == r, pred == r
        rows.append(dict(lang=lang, role=r, n=int(t.sum()), support_share=t.mean(),
                         recall=(t & p).sum() / t.sum(),
                         precision=(t & p).sum() / p.sum() if p.sum() else np.nan))
    conf = pd.crosstab(pd.Series(y, name="true"), pd.Series(pred, name="pred"))
    maj = Counter(y).most_common(1)[0]
    summary = dict(lang=lang, n=len(y), accuracy=(pred == y).mean(),
                   macro_recall=np.mean([r["recall"] for r in rows]),
                   majority_role=maj[0], majority_acc=maj[1] / len(y), n_features=X.shape[1])
    prow = []
    for a, b, w in pairs:
        m = np.isin(y, [a, b])
        na, nb = int((y == a).sum()), int((y == b).sum())
        rec = dict(lang=lang, role_a=a, role_b=b, weight=w, n_a=na, n_b=nb)
        if na < 10 or nb < 10 or len(set(g[m])) < FOLDS:
            prow.append({**rec, "accuracy": np.nan, "balanced_accuracy": np.nan,
                         "majority_acc": np.nan})
            continue
        pp = oof_predict(X[m], y[m], g[m])
        yy = y[m]
        prow.append({**rec, "accuracy": (pp == yy).mean(),
                     "balanced_accuracy": 0.5 * ((pp[yy == a] == a).mean() + (pp[yy == b] == b).mean()),
                     "majority_acc": max(na, nb) / (na + nb)})
    print(f"{lang}: acc={summary['accuracy']:.3f} maj={summary['majority_acc']:.3f}", flush=True)
    return lang, rows, conf, summary, prow


def mean_all(df, key, cols):
    d = df[~df.lang.isin(EXCLUDE_FROM_ALL)]
    nl = d.lang.nunique()
    g = d.groupby(key)[cols].mean().reset_index()
    g["n_langs"] = d.groupby(key).size().values
    g["lang"] = "ALL"
    return g, nl


def main():
    with (ROOT / "data" / "cache" / "role_tokens.pkl").open("rb") as fh:
        data = pickle.load(fh)
    w = yaml.safe_load((ROOT / "patterns" / "weights.yaml").read_text())
    pairs = [tuple(p) for p in w["pairs"]]
    jobs = [(lang, d["seg"][["file", "s", "text", "prevc", "nextc", "role"]], pairs)
            for lang, d in data.items()]
    with ProcessPoolExecutor(max_workers=len(jobs)) as ex:
        results = list(ex.map(run_lang, jobs))
    rec = pd.DataFrame([r for _, rows, _, _, _ in results for r in rows])
    summ = pd.DataFrame([s for _, _, _, s, _ in results])
    prs = pd.DataFrame([p for *_, prow in results for p in prow])
    conf_rows = []
    for lang, _, conf, _, _ in results:
        for t in conf.index:
            tot = conf.loc[t].sum()
            for p in conf.columns:
                if conf.loc[t, p]:
                    conf_rows.append(dict(lang=lang, true=t, pred=p, count=int(conf.loc[t, p]),
                                          frac_of_true=conf.loc[t, p] / tot))
    cf = pd.DataFrame(conf_rows)

    ra, _ = mean_all(rec, "role", ["support_share", "recall", "precision"])
    rec_out = pd.concat([ra, rec], ignore_index=True)[
        ["lang", "role", "recall", "precision", "support_share", "n", "n_langs"]]
    rec_out.to_csv(OUT / "recoverability.csv", index=False, float_format="%.4f")
    # pooled confusion: mean over languages of row-normalised fractions (absent = 0)
    langs_in = [l for l in cf.lang.unique() if l not in EXCLUDE_FROM_ALL]
    piv = {l: cf[cf.lang == l].pivot(index="true", columns="pred", values="frac_of_true") for l in langs_in}
    allr = sorted(set().union(*[set(p.index) | set(p.columns) for p in piv.values()]))
    pooled_conf = []
    for t in allr:
        have = [l for l in langs_in if t in piv[l].index]
        for p in allr:
            v = np.mean([piv[l].loc[t].get(p, 0) if p in piv[l].columns and not np.isnan(piv[l].loc[t].get(p, 0)) else 0
                         for l in have])
            if v > 0:
                pooled_conf.append(dict(lang="ALL", true=t, pred=p, count=np.nan, frac_of_true=v))
    cf = pd.concat([pd.DataFrame(pooled_conf), cf], ignore_index=True)
    cf.to_csv(OUT / "recoverability_confusion.csv", index=False, float_format="%.4f")
    pa, _ = mean_all(prs.dropna(subset=["accuracy"]), ["role_a", "role_b", "weight"],
                     ["accuracy", "balanced_accuracy", "majority_acc"])
    prs_out = pd.concat([pa, prs], ignore_index=True)
    prs_out.to_csv(OUT / "recoverability_pairs.csv", index=False, float_format="%.4f")
    write_md(rec, ra, summ, cf, prs, pa)
    print("wrote out/recoverability{,_confusion,_pairs}.csv, out/recoverability.md")


def f3(x):
    return "-" if pd.isna(x) else f"{x:.2f}"


def write_md(rec, ra, summ, cf, prs, pa):
    langs = list(summ.lang)
    L = ["# Lexical recoverability of roles\n",
         "Generated by `harness/recoverability.py`. Per language, multinomial logistic regression on "
         "lexical features only (token shape, exact text if among the language's 300 most frequent "
         "segment texts, previous/next non-whitespace character, previous segment text if top-300, "
         "shape x prev/next char). Unit = visible token segment (role_tokens.py; punctuation counts). "
         "GroupKFold(5) by file, out-of-fold. **Recoverability = recall.** ALL = unweighted mean over "
         "languages excluding elisp (sparse query, 41% `default`); `n_langs` = languages where the role "
         "occurs.\n",
         "## Overall\n",
         "| lang | segments | accuracy | macro recall | majority class | majority acc |",
         "|---|---:|---:|---:|---:|---:|"]
    for r in summ.itertuples():
        L.append(f"| {r.lang} | {r.n} | {r.accuracy:.3f} | {r.macro_recall:.3f} | {r.majority_role} | "
                 f"{r.majority_acc:.3f} |")
    s = summ[~summ.lang.isin(EXCLUDE_FROM_ALL)]
    L.append(f"| ALL | | {s.accuracy.mean():.3f} | {s.macro_recall.mean():.3f} | | {s.majority_acc.mean():.3f} |")
    L.append("\n## Recall (recoverability) per role\n")
    order = ra.sort_values("recall", ascending=False).role.tolist()
    order += sorted(set(rec.role) - set(order))
    L.append("`support` = mean share of segments. Rare roles (support < 0.1%) are penalised by the "
             "unweighted classifier, so low recall there partly reflects rarity.\n")
    L.append("| role | ALL recall | ALL precision | support | " + " | ".join(langs) + " |")
    L.append("|---|---:|---:|---:|" + "---:|" * len(langs))
    for r in order:
        a = ra[ra.role == r]
        cells = []
        for l in langs:
            x = rec[(rec.lang == l) & (rec.role == r)]
            cells.append(f3(x.recall.iloc[0]) if len(x) else "")
        L.append(f"| {r} | {f3(a.recall.iloc[0]) if len(a) else ''} | "
                 f"{f3(a.precision.iloc[0]) if len(a) else ''} | "
                 f"{(f'{100 * a.support_share.iloc[0]:.2f}%') if len(a) else ''} | " + " | ".join(cells) + " |")
    L.append("\n## Where each role goes wrong (ALL, mean row-normalised confusion, top 3 errors >= 2%)\n")
    a = cf[cf.lang == "ALL"]
    for r in order:
        x = a[(a.true == r) & (a.pred != r) & (a.frac_of_true >= 0.02)].sort_values("frac_of_true", ascending=False).head(3)
        if len(x):
            L.append(f"- **{r}** -> " + ", ".join(f"{p} {v:.0%}" for p, v in zip(x.pred, x.frac_of_true)))
    L.append("\n## Pairwise separability (pairs from patterns/weights.yaml)\n")
    L.append("Binary LR restricted to segments of the two roles, same features, GroupKFold(5). "
             "`bal` = balanced accuracy (mean of the two recalls), `maj` = majority-class accuracy for "
             "the pair. '-' = a role has < 10 segments in that language.\n")
    L.append("| pair | w | ALL acc | ALL bal | ALL maj | " + " | ".join(f"{l} bal" for l in langs) + " |")
    L.append("|---|---:|---:|---:|---:|" + "---:|" * len(langs))
    for r in pa.sort_values("balanced_accuracy").itertuples():
        cells = []
        for l in langs:
            x = prs[(prs.lang == l) & (prs.role_a == r.role_a) & (prs.role_b == r.role_b)]
            cells.append(f3(x.balanced_accuracy.iloc[0]) if len(x) else "-")
        L.append(f"| {r.role_a} / {r.role_b} | {r.weight} | {r.accuracy:.3f} | {r.balanced_accuracy:.3f} | "
                 f"{r.majority_acc:.3f} | " + " | ".join(cells) + " |")
    L.append("\n## Caveats\n")
    L += [
        "- Labels are nvim-treesitter's paint, so recoverability is 'how much of what the query knows "
        "is visible in the glyphs'. Roles the query cannot see either (e.g. variable.def needs locals; "
        "field vs variable at a use site) are bounded by that.",
        "- The top-300 vocabulary is computed on the whole language corpus (unsupervised counts, not "
        "labels), so closed classes are visible to every fold.",
        "- One segment = one example, so long comments/strings and one-char punctuation weigh the same. "
        "Recall is per segment, not per character.",
        "- A linear model with two conjunctions is a lower bound on lexical recoverability; a reader "
        "also sees wider context (indentation, the whole line).",
        "- Closed classes are approximated by the top-300 texts, so rare keywords fall outside it "
        "(Rust `break`/`continue`, C `true`/`false`) and look like identifiers; a reader who knows "
        "the language would not make that error.",
        "- Some labels are themselves lexical rules in the queries (ALL_CAPS identifier -> @constant "
        "in Python/Rust/C/Java/Lua/bash; `self`/`this` -> variable.builtin), so their recoverability "
        "is high by construction. See corpus_findings.md for declared-constant shape.",
        "- keyword.exit here is the refined role (exit words only); see out/role_stats.md.",
    ]
    (OUT / "recoverability.md").write_text("\n".join(L) + "\n")


if __name__ == "__main__":
    main()
