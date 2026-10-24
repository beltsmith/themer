"""Static checks on the pattern sets (C4 monosemy, C9 degradation, hue budget, coverage).

    uv run --with pyyaml python harness/static_checks.py   ->  out/static_checks.md

Palette-independent. Channel model: see mapper_common.channels_between().
If out/adjacency.csv exists, the C9 ablation (H11) also reports the adjacency-weighted
confusion cost (C6) when each of hue / weight / slant is removed.
"""
from __future__ import annotations

import os
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mapper_common as M  # noqa: E402

HUE_BUDGET = 5   # P:I2 category memory


def monosemy(s):
    """C4: each channel used only for its declared axis."""
    st = M.effective_styles(s)
    info = M.role_info()
    v = []
    fams = s['families']
    wax = s.get('channels', {}).get('weight')
    for rid, sty in st.items():
        if sty is None:
            continue
        raw = s['styles'][rid]
        site = info[rid].get('site')
        if sty['bold']:
            if not (site == 'binding' or sty['tier'] == 'popout'):
                v.append((rid, 'weight', f"bold (tier {sty['tier']}) on a role whose site is {site or 'unspecified'}; weight is declared = {wax}"))
            elif sty['tier'] == 'popout' and wax == 'site':
                v.append((rid, 'weight (note)', 'bold used for the popout tier as well as for binding sites: weight carries two axes (site, oddball)'))
        if sty.get('slant') == 'italic' or raw.get('slant'):
            if raw.get('family') != 'prose' and not (rid.startswith('comment') and s['channels'].get('slant') == 'prose'):
                v.append((rid, 'slant', 'italic on a non-prose role'))
        if raw.get('variant') == 'lightness':
            v.append((rid, 'lightness', f"lightness variant encodes a sub-kind inside family {raw.get('family')}, but lightness is declared = tier"))
        if raw.get('variant') == 'chroma-low':
            v.append((rid, 'chroma', 'chroma variant encodes site (use vs def); chroma is not a declared channel, and site is already declared = weight'))
        if raw.get('strike') and rid != 'mod.deprecated':
            v.append((rid, 'strike', 'strike outside deprecated'))
        f = raw.get('family')
        if f and f not in fams:
            v.append((rid, 'hue', f'family {f} not declared'))
        if raw.get('tier') in ('strong',) and site != 'binding':
            v.append((rid, 'tier', 'strong tier (bold) on non-binding role'))
    # binding roles that are not bold: weight does not fully encode site
    for rid, sty in st.items():
        if sty and info[rid].get('site') == 'binding' and not sty['bold']:
            v.append((rid, 'weight (incomplete)', f'binding-site role is not bold, so bold != {wax}'))
    # fallbacks that introduce channels
    for f, d in fams.items():
        fb = d.get('fallback') or {}
        if fb.get('slant') and f != 'prose':
            v.append((f'family:{f}', 'slant', 'fallback adds italic to a non-prose family'))
        if fb.get('tier') == 'strong':
            roles_f = [r for r, x in s['styles'].items() if x.get('family') == f and x.get('tier') != 'quiet']
            bad = [r for r in roles_f if info[r].get('site') != 'binding']
            if bad:
                v.append((f'family:{f}', 'weight', f'fallback tier strong (bold) reaches non-binding roles {bad}'))
        if 'fallback' not in d and not d.get('distinct_from_all') is None:
            pass
    for f, d in fams.items():
        if d.get('hue') and 'fallback' not in d:
            v.append((f'family:{f}', 'ladder', 'no fallback declared: when dropped its roles keep their tier with default hue (harness assumption)'))
    return v


def degradation(s, adjd=None):
    st = M.effective_styles(s)
    rows = []
    for a, b, w in M.must_differ_pairs(s):
        ch = M.channels_between(st[a], st[b], M.is_v2(s))
        rows.append((a, b, w, ch, adjd.get(frozenset((a, b)), 0.0) if adjd else None))
    return rows


def ablation_costs(s, adjd):
    """C6 cost (sum adj*w over must-differ pairs left with no channel) at full capacity,
    and after removing one channel. Hue loss = every hue collapses to default."""
    rows = degradation(s, adjd)
    out = {}
    for lost in (None, 'hue', 'weight', 'slant', 'lightness'):
        c = cd = 0.0
        n = 0
        for a, b, w, ch, ad in rows:
            rest = [x for x in ch if x != lost]
            if lost == 'hue':
                rest = [x for x in rest if x != 'chroma']
            if not rest:
                c += M.pair_cost(a, b)
                cd += M.pair_cost(a, b, discounted=True)
                n += 1
        out[lost or 'none'] = (c, cd, n)
    return out


def coverage(s):
    ids = set(M.role_ids(overlay=True))
    styled = set(s['styles'])
    return sorted(ids - styled), sorted(styled - ids)


def main():
    adjd, adjsrc = M.adjacency()
    real_adj = not adjsrc.startswith('FALLBACK')
    L = ['# Static pattern checks (C4, C9, hue budget, coverage)', '',
         'Generated by `harness/static_checks.py`. Palette-independent. Sets are resolved with `inherits`.',
         'Channel model (see `mapper_common.channels_between`): *hue* = different family (null family = default ink);',
         'draft 1 sets: *lightness* only where the pattern designs it (faded tier, `variant: lightness`, popout Lc 60);',
         '*chroma* = `variant: chroma-low` within a family; default (Lc ≥ 60) vs salient (Lc ≥ 45) is not a lightness channel.',
         'Draft 2 sets (landmark, hybrid): *lightness* = faded / dim vs the rest; *chroma* = none / quiet / loud class',
         '(quiet and dim are D1-distinct at the reliable level by construction in the mapper, or the quiet colour fails and is recorded). *weight* = bold (tier strong/popout); *slant*; *strike*.',
         'Losing hue (H11 ablation) also removes chroma.',
         '',
         'Must-differ pairs = role pairs in different families (null family counts as its own group) with w > 0,',
         'plus explicitly weighted pairs inside one family. w = `weights.yaml` pair weight or `default_pair`.',
         f'Adjacency source: {adjsrc}. Separability: 2·balanced_accuracy − 1 from out/recoverability_pairs.csv (ALL) where listed, '
         'else 1 − (conf(a→b)+conf(b→a))/2 from out/recoverability_confusion.csv.', '']
    L.append('## Summary\n')
    L.append('| set | hue families | ≤ budget 5? | unstyled roles | unknown style keys | C4 violations | must-differ pairs | single-channel (hue/slant/weight) w≥2 | no channel at all |')
    L.append('|---|---:|---|---|---|---:|---:|---:|---:|')
    details = []
    for name in M.SETS:
        s = M.load_set(name)
        hf = M.hue_families(s)
        uns, unk = coverage(s)
        mono = monosemy(s)
        deg = degradation(s, adjd)
        flag = [r for r in deg if len(r[3]) == 1 and r[3][0] in ('hue', 'slant', 'weight') and r[2] >= 2]
        none_ = [r for r in deg if not r[3]]
        nviol = len([m for m in mono if 'note' not in m[1]])
        L.append(f"| {name} | {len(hf)} ({', '.join(hf)}) | {'yes' if len(hf) <= HUE_BUDGET else '**no**'} "
                 f"| {', '.join(uns) or '–'} | {', '.join(unk) or '–'} | {nviol} | {len(deg)} | {len(flag)} | {len(none_)} |")
        D = [f'## {name}' + (f" (inherits {s['inherits']})" if s.get('inherits') else ''), '']
        rk = M.rank_key(s)
        D.append(f"Hue families ({len(hf)}): " + ', '.join(f"{f} ({rk} {s['families'][f][rk]})" for f in hf)
                 + f". Budget {HUE_BUDGET} (P:I2): {'within' if len(hf) <= HUE_BUDGET else f'**over by {len(hf) - HUE_BUDGET}**'}"
                 + (" (oddball included; without it: %d)" % (len(hf) - 1) if 'oddball' in hf else '') + '.')
        D.append(f"YAML drop order (ascending `{rk}` = dropped first): {' → '.join(M.drop_order(s))}.")
        ranks = Counter(s['families'][f][rk] for f in hf)
        ties = [r for r, c in ranks.items() if c > 1]
        if ties:
            D.append(f"**Ladder ties** at rank(s) {ties}: " + '; '.join(
                ', '.join(f for f in hf if s['families'][f][rk] == r) for r in ties)
                + ". The harness breaks ties by YAML order.")
        D.append('')
        D.append('### C4 monosemy\n')
        if mono:
            D.append('| role / family | channel | issue |')
            D.append('|---|---|---|')
            for r, c, t in mono:
                D.append(f'| {r} | {c} | {t} |')
        else:
            D.append('No violations.')
        D.append('')
        D.append('### C9 degradation\n')
        D.append(f'{len(deg)} must-differ pairs. Channel-count histogram: '
                 + ', '.join(f'{k} channel(s): {v}' for k, v in sorted(Counter(len(r[3]) for r in deg).items())) + '.')
        D.append('')
        D.append('**Flagged** (one channel only, and that channel is hue, slant or weight, w ≥ 2):\n')
        if flag:
            D.append('| pair | w | only channel | adjacency | sep |')
            D.append('|---|---:|---|---:|---:|')
            for a, b, w, ch, ad in sorted(flag, key=lambda r: (-r[2], -(r[4] or 0))):
                D.append(f'| {a} / {b} | {w} | {ch[0]} | {ad:.4g} | {M.sep(a, b):.3f} |')
        else:
            D.append('None.')
        D.append('')
        D.append('**No distinguishing channel even at full capacity** (top 15 by adjacency·w; sep = lexical separability):\n')
        if none_:
            D.append('| pair | w | adjacency | adj·w | sep | adj·w·(1−sep) |')
            D.append('|---|---:|---:|---:|---:|---:|')
            for a, b, w, ch, ad in sorted(none_, key=lambda r: -(r[4] or 0) * r[2])[:15]:
                D.append(f'| {a} / {b} | {w} | {ad:.4g} | {ad * w:.4g} | {M.sep(a, b):.3f} | {M.pair_cost(a, b, True):.3g} |')
            D.append(f'\n({len(none_)} such pairs in total.)')
        else:
            D.append('None.')
        D.append('')
        D.append('Weighted pairs from `weights.yaml` (all of them, w ≥ 1):\n')
        D.append('| pair | w | channels |')
        D.append('|---|---:|---|')
        _, _, pw = M.weights()
        st = M.effective_styles(s)
        for k, w in pw.items():
            a, b = sorted(k)
            if w >= 1:
                D.append(f"| {a} / {b} | {w} | {', '.join(M.channels_between(st[a], st[b])) or '**none**'} |")
        D.append('')
        D.append('### H11 ablation (C6 cost when one channel is lost, full capacity)\n')
        ab = ablation_costs(s, adjd)
        D.append(f"Adjacency: {'measured' if real_adj else 'fallback (ink-share product), indicative only'}.\n")
        D.append('| channel lost | confused pairs | raw cost Σ adj·w | discounted Σ adj·w·(1−sep) |')
        D.append('|---|---:|---:|---:|')
        for k, (c, cd, n) in ab.items():
            D.append(f'| {k} | {n} | {c:.4g} | {cd:.4g} |')
        D.append('')
        details += D
    L.append('')
    L += details
    L.append('## Spec notes found by these checks\n')
    L.append('- Draft 1 (`*_v1`, label): `ladder` comment says "higher = merged/dropped first", but the numbers only match 00-framework §4 '
             '(meta → exit → prose → definition) if *lower* is dropped first. Harness uses lower-first. `oddball` has no fallback and '
             '`distinct_from_all` makes it a 6th hue in landmark_v1. Tier `lc` targets put `salient` (45) below `default` (60).')
    L.append('- Draft 2 (landmark, hybrid): `keep` = higher kept longer (same numeric direction as the harness ladder). Four loud hue '
             'families; oddball is not a hue family. `lightness+chroma` is one declared axis (salience), so quiet/dim/faded tiers '
             'are not monosemy violations; `weight` = landmark (binding sites and oddballs), so bold on popout is declared.')
    L.append('- Draft 2.1: when `value` is dropped, `string` follows `quiet_fallback: {tier: quiet, family: any_kept, else: default}`: it borrows the '
             'quiet tint of a kept family (static model: chroma class quiet, no hue channel), else default; never dim, so string/comment keeps '
             'lightness and chroma channels. In the static model a borrowed tint is assumed to exist whenever any family is kept.')
    L.append('- Draft 2.1 hybrid: `definition` now declares `quiet_fallback: {tier: default}`, so its quiet use sites (calls, types) go to default, not bold.')
    os.makedirs(M.OUT, exist_ok=True)
    with open(os.path.join(M.OUT, 'static_checks.md'), 'w') as f:
        f.write('\n'.join(L) + '\n')
    print('wrote out/static_checks.md')


if __name__ == '__main__':
    main()
