"""Palette -> pattern mapper (00-framework.md §4).

    uv run --with coloraide --with pyyaml --with numpy --with scipy python harness/mapper.py \
        [palette-id ...] [--set landmark] [--mode A|B]
    (no ids: writes a handful of example themes to out/mapped/)

Steps, as implemented:
 1. Classify. surface = bg, default ink = fg. Inks = palette slots minus surfaces
    (base00/01/02/10/11, cursor/selection colours). Accent candidates = inks with OKLCH C >= 0.06
    (D4 reliable naming); greys = C < 0.04. reserve_diag (default OFF; opt-in, P:I9): the error colour
    (base08 / ANSI red / most chromatic red ink) and every candidate not D2 from it are removed;
    the error colour is kept for the diagnostic layer only.
 2. Derive. Each accent is shifted in OKLCH L (away from bg, gamut-fitted) toward the salient
    tier target |Lc| 45; the shift is capped at fidelity ΔE_OK <= MAX_FID (0.05). A candidate is
    kept if it then passes CS:L2 floor (|Lc| >= 35). Candidates within ΔE_OK 0.01 are merged;
    at most PER_NAME (3) candidates per hue name are kept, best first (L2 default, low fidelity,
    high chroma).
 3. Capacity = size of the largest set of candidates that are pairwise D2 (categorically
    distinct, D1 at the floor p=.5) AND each D2 from the default ink (fg). Exact max clique.
    CVD capacity: the same on simulated colours (fg, bg simulated too).
 4. Ladder. Hue families are dropped in ascending `ladder` rank until required <= capacity;
    roles of dropped families follow `fallback` (mapper_common.effective_styles).
 5. Assign. Enumerate every k-clique (k = kept families; capped at MAX_CLIQUES, best nodes
    first) × every permutation, and maximise
        pair  = Σ_{f<g} Â(f,g) · s(i_f, i_g)  +  Σ_f Â(f,∅) · s(i_f, fg)
                with Â = adjacency×weight between the families' roles (normalised to sum 1),
                s = 0.8·clip(D2 margin normal)/2 + 0.2·clip(D2 margin deutan)/2, clip to [-1, 2]
      + fit   = mode A: (Spearman(need rank, accent salience rank) + 1)/2,
                        need(f) = ink-weighted mean beacon value / ink share (weights.yaml, role_stats)
                mode B: mean habit score of the accent's hue name for the family (HABITS below)
      + node  = Σ_f (0.1·[|Lc| >= 45] − 2·fidelity)          (prefer undistorted, legible accents)
 6. Fill roles. salient/strong = family accent (strong adds bold); popout = accent pushed to Lc 60
    (same fidelity cap); variant lightness = a palette ink that is D3-related to the accent if
    one exists, else an L shift until D1 floor vs the accent; variant chroma-low = C×0.5 (≥ 0.045);
    faded = mix(fg, bg, t) with |Lc| = 30 (tier target); default = fg.
 7. evaluate() computes L1–L4, S1, confusion cost (normal + deutan), coloured ink (C2), C1.

Mode B habit table (from base16 styling.md via notes/02 §7 and the crosswalk's base16 column;
base24 makes the slot -> hue name mapping explicit: 08 red, 09 orange, 0A yellow, 0B green,
0C cyan, 0D blue, 0E magenta, 0F brown). Scores 0..1 per hue name:
    callable / definition  functions = base0D blue          blue 1, cyan .5, purple .3
    type                   classes = base0A yellow          yellow 1, orange .6, brown .5
    value                  strings = base0B green (most of the family's ink), constants/numbers = base09 orange
                                                            green 1, orange .6, yellow .4
    keyword / exit         keywords = base0E magenta        purple 1, pink .9, red .3
    meta                   preproc/macro ~ base0E/08, decorators ~0D, support/regex = base0C
                                                            cyan .7, pink .6, red .5, purple .5
    field                  variables/properties = base08    red 1, orange .4, pink .4
    prose                  comments = base03 (grey). No accent is grey, so prefer the low-key
                           hues builders use for comments   brown .6, cyan .4, green .3, blue .3
    oddball                TODO: no base16 rule; red/yellow is the common convention
                                                            red 1, yellow .7, orange .7
"""
from __future__ import annotations

import itertools
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import colour as K  # noqa: E402
import mapper_common as M  # noqa: E402

MAX_FID = 0.05
PER_NAME = 3
MAX_CLIQUES = 600
SAL_K = 1.5          # chroma pop-out weight in salience(): 100·1.5·C (C .1 ~ 15 Lc ~ one tier)
CVD_KINDS = ['deutan', 'protan', 'tritan']
RESERVE_DIAG = False  # P:I9 reservation is opt-in (user decision: red may be used for syntax)

HABITS = {
    'callable':   {'blue': 1, 'cyan': .5, 'purple': .3},
    'definition': {'blue': 1, 'cyan': .5, 'purple': .3},
    'type':       {'yellow': 1, 'orange': .6, 'brown': .5},
    'value':      {'green': 1, 'orange': .6, 'yellow': .4},
    'keyword':    {'purple': 1, 'pink': .9, 'red': .3},
    'syntax':     {'purple': 1, 'pink': .9, 'red': .3},     # reader: keywords (base16 keywords = base0E)
    'exit':       {'purple': 1, 'pink': .9, 'red': .3},
    'meta':       {'cyan': .7, 'pink': .6, 'red': .5, 'purple': .5},
    'field':      {'red': 1, 'orange': .4, 'pink': .4},
    'prose':      {'brown': .6, 'cyan': .4, 'green': .3, 'blue': .3},
    'oddball':    {'red': 1, 'yellow': .7, 'orange': .7},
}

SURFACE_SLOTS = {'base00', 'base01', 'base02', 'base10', 'base11', 'cursorColor', 'selectionBackground'}


# ------------------------------------------------------------------ palette side

def palette_inks(p):
    """[(slot, hex)] candidate inks (surfaces removed, deduplicated by hex)."""
    seen = set()
    out = []
    for slot, hx in p['colours'].items():
        if slot in SURFACE_SLOTS:
            continue
        hx = K.norm(hx)
        if hx in seen or hx == K.norm(p['bg']):
            continue
        seen.add(hx)
        out.append((slot, hx))
    return out


def error_colour(p):
    """The palette's diagnostic/error colour (P:I9): base08 for base16/base24, ANSI `red` for ansi16;
    if that slot is missing or achromatic (C < 0.06), the most chromatic ink named red. (slot, hex) or None."""
    slot = 'red' if p['family'] == 'ansi16' else 'base08'
    hx = p['colours'].get(slot)
    if hx and K.oklch(K.norm(hx))[1] >= K.NAME_C:
        return slot, K.norm(hx)
    reds = [(K.oklch(h)[1], sl, h) for sl, h in palette_inks(p) if K.hue_name(h) == 'red' and K.oklch(h)[1] >= K.NAME_C]
    if reds:
        _, sl, h = max(reds)
        return sl, h
    return None


LOUD_C = 0.08   # draft 2: loud tier requires OKLCH C >= 0.08 after derivation


def cand_kw(s):
    """Candidate / capacity parameters for a pattern set. Draft 2: loud accents need C >= 0.08 and
    distinct hue families need a different hue name (spec fix (a))."""
    return {'min_c': LOUD_C, 'strict': True} if M.is_v2(s) else {'min_c': K.NAME_C, 'strict': False}


def candidates(p, max_fid=MAX_FID, target=45.0, floor=35.0, reserve_diag=RESERVE_DIAG, min_c=K.NAME_C, strict=False):
    """Accent candidates. reserve_diag: drop the error colour and every candidate that is not D2 from it
    (it stays available to the diagnostic layer only). With strict (draft 2), D2 needs a different hue
    name, so the whole error hue name is reserved. min_c: chroma required after derivation."""
    bg = K.norm(p['bg'])
    err = error_colour(p) if reserve_diag else None
    out = []
    for slot, src in palette_inks(p):
        L, C, h = K.oklch(src)
        if C < K.NAME_C:
            continue
        if err and src == err[1]:
            continue
        hx, v, fid = K.shift_l_to_lc(src, bg, target, max_fid=max_fid) if max_fid > 0 else (src, K.alc(src, bg), 0.0)
        if v < floor or K.oklch(hx)[1] < max(K.GREY_C, min_c if min_c > K.NAME_C else 0):
            continue
        if err and not K.d2(hx, err[1], strict_name=strict):
            continue
        out.append({'slot': slot, 'src': src, 'hex': hx, 'lc': v, 'fid': fid,
                    'name': K.hue_name(hx), 'C': K.oklch(hx)[1], 'L': K.oklch(hx)[0]})
    # quality order, merge near-duplicates, cap per hue name
    out.sort(key=lambda c: (c['lc'] < target, c['fid'], -c['C']))
    kept = []
    per = {}
    for c in out:
        if any(K.de_ok(c['hex'], k['hex']) < 0.01 for k in kept):
            continue
        if per.get(c['name'], 0) >= PER_NAME:
            continue
        per[c['name']] = per.get(c['name'], 0) + 1
        kept.append(c)
    return kept


def compat(hexes, fg, bg, kind='normal', floor=35.0, level='floor', strict=False):
    """(ok_nodes, adjacency matrix) under a vision condition. level = D1 level used inside D2.
    Draft 2.1 (strict=True, i.e. draft-2 sets): under CVD simulation two loud families are distinct (and a family
    accent is distinct from fg) if D1 passes at the RELIABLE level (p=.8, lightness differences count); the hue-name
    rule applies under normal vision only."""
    sim = [K.cvd(h, kind) for h in hexes]
    sfg, sbg = K.cvd(fg, kind), K.cvd(bg, kind)
    n = len(hexes)
    if strict and kind != 'normal':
        dist = lambda a, b: K.d1(a, b, 'reliable')
    else:
        dist = lambda a, b: K.d2(a, b, level, strict)
    okn = [K.alc(s, sbg) >= floor and dist(s, sfg) for s in sim]
    A = np.zeros((n, n), bool)
    for i in range(n):
        for j in range(i + 1, n):
            if okn[i] and okn[j] and dist(sim[i], sim[j]):
                A[i, j] = A[j, i] = True
    return okn, A


def max_clique(okn, A):
    nodes = [i for i, o in enumerate(okn) if o]
    best = []

    def rec(R, P):
        nonlocal best
        if not P:
            if len(R) > len(best):
                best = R
            return
        if len(R) + len(P) <= len(best):
            return
        for v in list(P):
            if len(R) + len(P) <= len(best):
                return
            rec(R + [v], [u for u in P if A[v, u] and u > v])
            P = [u for u in P if u != v]
    rec([], nodes)
    return best


def k_cliques(okn, A, k, cap=MAX_CLIQUES):
    nodes = [i for i, o in enumerate(okn) if o]
    out = []

    def rec(R, P):
        if len(out) >= cap:
            return
        if len(R) == k:
            out.append(R)
            return
        for idx, v in enumerate(P):
            if len(R) + len(P) - idx < k:
                return
            rec(R + [v], [u for u in P[idx + 1:] if A[v, u]])
    rec([], nodes)
    return out


def capacity(p, kinds=('normal',) + tuple(CVD_KINDS), max_fid=MAX_FID, cands=None, level='floor', strict=False, min_c=K.NAME_C):
    cands = candidates(p, max_fid, min_c=min_c, strict=strict) if cands is None else cands
    fg, bg = K.norm(p['fg']), K.norm(p['bg'])
    hexes = [c['hex'] for c in cands]
    res = {}
    for kind in kinds:
        okn, A = compat(hexes, fg, bg, kind, level=level, strict=strict)
        res[kind] = len(max_clique(okn, A))
    return res


# ------------------------------------------------------------------ pattern side

def stat_roles(s, styles):
    """[(stat_key, role_id, style)] for C1/C2: splits scope: top-level roles into .top/.local."""
    ink, _ = M.ink_shares()
    out = []
    for rid in M.role_ids():
        st = styles.get(rid)
        if st is None:
            continue
        if st.get('scope') == 'top-level' and f'{rid}.top' in ink:
            out.append((f'{rid}.top', rid, st))
            loc = dict(styles['variable.use']) if 'variable.use' in styles else {'family': None, 'tier': 'default', 'bold': False}
            out.append((f'{rid}.local', rid, loc))
        else:
            out.append((rid, rid, st))
    return out


def family_need(s, kept, styles):
    ink, _ = M.ink_shares()
    _, beacon, _ = M.weights()
    need = {}
    v2 = M.is_v2(s)
    for f in kept:
        rs = [(k, rid) for k, rid, st in stat_roles(s, styles) if st.get('family') == f
              and (not v2 or st.get('tier') in M.LOUD_TIERS)]   # draft 2: quiet ink spends no loud salience
        tot = sum(ink.get(k, 0) for k, _ in rs)
        if tot > 0:
            val = sum(ink.get(k, 0) * beacon.get(rid, 1) for k, rid in rs) / tot
        else:
            val = np.mean([beacon.get(rid, 1) for _, rid in rs]) if rs else 1
        need[f] = val / max(tot, 1e-4)
    return need


def family_pair_weights(s, kept, styles):
    """Â(f,g) and Â(f,∅) from role adjacency × weight, normalised to sum 1."""
    fams = list(kept)
    idx = {f: i for i, f in enumerate(fams)}
    n = len(fams)
    A = np.zeros((n, n))
    Ad = np.zeros(n)
    ids = [r for r in M.role_ids() if styles.get(r) is not None]
    for a, b in itertools.combinations(ids, 2):
        fa, fb = styles[a]['family'], styles[b]['family']
        if fa == fb:
            continue
        v = M.adj(a, b) * M.pair_weight(a, b)
        if v <= 0:
            continue
        if fa in idx and fb in idx:
            A[idx[fa], idx[fb]] += v
            A[idx[fb], idx[fa]] += v
        elif fa in idx:
            Ad[idx[fa]] += v
        elif fb in idx:
            Ad[idx[fb]] += v
    tot = A.sum() / 2 + Ad.sum()
    if tot <= 0:
        A[:] = 1.0 / max(1, n * (n - 1))
        np.fill_diagonal(A, 0)
        Ad[:] = 0
        tot = 1
    return fams, A / tot, Ad / tot


_PERMS = {}


def perms(k):
    if k not in _PERMS:
        _PERMS[k] = np.array(list(itertools.permutations(range(k))), dtype=np.int16).reshape(-1, k)
    return _PERMS[k]


def assign_fams(cands, fams, A, Ad, need, mode, fg, bg, cliques, strict=False, v2=False):
    k = len(fams)
    if k == 0 or not cliques:
        return {}, 0.0
    n = len(cands)
    hexes = [c['hex'] for c in cands]
    dfg, dbg = K.cvd(fg, 'deutan'), K.cvd(bg, 'deutan')
    dh = [K.cvd(h, 'deutan') for h in hexes]

    def s_of(m_n, m_d):
        return 0.8 * np.clip(m_n, -1, 2) / 2 + 0.2 * np.clip(m_d, -1, 2) / 2

    def dm(a, b):    # deutan margin: draft 2.1 = D1 reliable margin (no name rule); draft 1 = D2 margin
        return K.de_text(a, b, 0.8) - 1.0 if v2 else K.d2_margin(a, b, strict_name=strict)
    S = np.zeros((n, n))
    for i in range(n):
        for j in range(i + 1, n):
            S[i, j] = S[j, i] = s_of(K.d2_margin(hexes[i], hexes[j], strict_name=strict), dm(dh[i], dh[j]))
    Sfg = np.array([s_of(K.d2_margin(h, fg, strict_name=strict), dm(d, dfg)) for h, d in zip(hexes, dh)])
    node = np.array([0.1 * (c['lc'] >= 45) - 2 * c['fid'] for c in cands])
    if v2:
        sal = np.array([K.salience_v2(h, fg, bg) for h in hexes])
    else:
        sal = np.array([K.salience(h, bg, chroma_k=SAL_K) for h in hexes])
    P = perms(k)
    C = np.array(cliques, dtype=np.int32)                 # (Q, k)
    X = C[:, P].reshape(-1, k)                             # (Q*P, k) node for family f at column f
    score = np.zeros(len(X))
    for f in range(k):
        score += Ad[f] * Sfg[X[:, f]] + node[X[:, f]] / k
        for g in range(f + 1, k):
            if A[f, g]:
                score += A[f, g] * S[X[:, f], X[:, g]]
    if mode == 'A':
        if k == 1:
            fit = np.ones(len(X))
        else:
            nv = np.array([need[f] for f in fams])
            nr = nv.argsort().argsort().astype(float)
            sr = sal[X].argsort(1).argsort(1).astype(float)
            nr -= nr.mean()
            sr -= sr.mean(1, keepdims=True)
            den = np.sqrt((nr ** 2).sum() * (sr ** 2).sum(1))
            fit = ((sr * nr).sum(1) / np.where(den > 0, den, 1) + 1) / 2
    else:
        H = np.array([[HABITS.get(f, {}).get(c['name'], 0.0) for c in cands] for f in fams])  # (k, n)
        fit = np.mean([H[f, X[:, f]] for f in range(k)], axis=0)
    total = score + fit
    b = int(total.argmax())
    return {f: int(X[b, i]) for i, f in enumerate(fams)}, float(total[b])


# ------------------------------------------------------------------ fill roles

def lightness_variant(base, p, bg):
    for _, hx in palette_inks(p):
        if hx != base and K.d3(hx, base) and K.alc(hx, bg) >= 35:
            return hx, 0.0, 'palette'
    L, C, h = K.oklch(base)
    up = K.oklch(bg)[0] < 0.6
    for sign in ((1, -1) if up else (-1, 1)):
        for step in np.arange(0.02, 0.25, 0.01):
            hx = K.from_oklch(L + sign * step, C, h)
            if K.d1(hx, base, 'floor') and K.alc(hx, bg) >= 35:
                return hx, K.de_ok(hx, base), 'derived'
    return base, 0.0, 'none'


QUIET_C = (0.05, 0.09)      # draft 2.1 default; the pattern set's tiers.quiet.chroma overrides
QUIET_LC = 15.0
DIM_C, FADED_C = 0.04, 0.03


def _cap_c(hx, cmax):
    L, C, h = K.oklch(hx)
    return hx if C <= cmax else K.from_oklch(L, cmax, h)


def dim_faded(fg, bg, tiers):
    """Draft 2 dim and faded inks. dim: mix(fg, bg) to |Lc| = min(target 45, |Lc_fg| − below_default),
    chroma capped at 0.04 (achromatic or fg hue). faded: mix to |Lc| 30, C <= 0.03, lowered (to its floor 15)
    until D1 floor from dim. Returns (dim, faded, info)."""
    f = K.alc(fg, bg)
    dt, dfl = tiers['dim']['lc']
    below = tiers['dim'].get('below_default', 10)
    target = min(dt, f - below)
    dim, _ = K.fade_to_lc(fg, bg, target)
    dim = _cap_c(dim, DIM_C)
    ft, ffl = tiers['faded']['lc']
    faded = None
    t = min(ft, K.alc(dim, bg) - 1)
    while t >= ffl:
        fd, _ = K.fade_to_lc(fg, bg, t)
        fd = _cap_c(fd, FADED_C)
        if K.d1(fd, dim, 'floor'):
            faded = fd
            break
        t -= 1
    faded_ok = faded is not None
    if faded is None:
        faded = _cap_c(K.fade_to_lc(fg, bg, ffl)[0], FADED_C)
    dlc = K.alc(dim, bg)
    info = {'fg_limited': abs(f) < 50, 'dim': dim, 'dim_lc': round(dlc, 1), 'dim_floor_ok': dlc >= dfl - 0.5,
            'dim_below_fg_ok': f - dlc >= below - 0.5, 'dim_d1_fg': K.d1(dim, fg, 'floor'),
            'faded': faded, 'faded_lc': round(K.alc(faded, bg), 1), 'faded_distinct_ok': faded_ok}
    return dim, faded, info


def quiet_colour(acc, fg, bg, avoid, crange=QUIET_C, level='reliable'):
    """Draft 2.1 quiet tier: the family accent's hue with chroma in `crange` ([0.05, 0.09]) and |Lc| within 15 of fg,
    D1 at `level` (reliable, p=.8) from fg and from every colour in `avoid` (dim + other quiet colours in use).
    Candidates: OKLab mix(acc, fg, t), t in [0, 1] step .02, plus OKLCH (fg's L +/- .10, C in range, acc hue).
    Returns the most fg-like passing colour (min dE_OK to fg), or None (failure: recorded by the caller)."""
    f = K.alc(fg, bg)
    Lf = K.oklch(fg)[0]
    ha = K.oklch(acc)[2]
    pool = [K.mix(acc, fg, t) for t in np.arange(0, 1.0001, 0.02)]
    pool += [K.from_oklch(Lf + dl, c, ha) for c in np.arange(crange[0], crange[1] + 1e-9, 0.005)
             for dl in np.arange(-0.10, 0.1001, 0.01)]
    best = None
    for q in pool:
        C = K.oklch(q)[1]
        if not (crange[0] - 1e-3 <= C <= crange[1] + 1e-3):
            continue
        if abs(K.alc(q, bg) - f) > QUIET_LC:
            continue
        d = K.de_ok(q, fg)
        if best is not None and d >= best[0]:
            continue
        if not K.d1(q, fg, level) or any(not K.d1(q, a, level) for a in avoid):
            continue
        best = (d, q)
    return best[1] if best else None


def spare_accent(p, used_hexes, fg, bg, reserve_diag):
    """Popout ink: the most chromatic accent (reserve_diag respected) whose hue name differs from every
    family accent in use and from fg, D1 floor from fg, |Lc| >= 35. None if there is none."""
    used = {K.hue_name(h) for h in used_hexes} | {K.hue_name(fg)}
    best = None
    for c in candidates(p, reserve_diag=reserve_diag, strict=True):
        if c['name'] in used or not K.d1(c['hex'], fg, 'floor'):
            continue
        if best is None or c['C'] > best['C']:
            best = c
    return best


ASSIGNMENTS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'assignments.yaml')


def load_assignments(setname, pid):
    """Creator assignment {family: slot} for (set, palette id) from harness/assignments.yaml, or None."""
    import yaml
    with open(ASSIGNMENTS_FILE) as f:
        return (yaml.safe_load(f).get(setname) or {}).get(pid)


def creator_candidates(p, assign, max_fid, target=45.0):
    """Mode C: one candidate per assigned family, taken from the assigned slot (no filtering). Same lightness
    derivation as `candidates` (shift toward |Lc| target, fidelity cap max_fid)."""
    bg = K.norm(p['bg'])
    out = {}
    for f, slot in assign.items():
        src = K.norm(p['colours'][slot])
        hx, v, fid = K.shift_l_to_lc(src, bg, target, max_fid=max_fid) if max_fid > 0 else (src, K.alc(src, bg), 0.0)
        L, C, h = K.oklch(hx)
        out[f] = {'slot': slot, 'src': src, 'hex': hx, 'lc': v, 'fid': fid, 'name': K.hue_name(hx), 'C': C, 'L': L}
    return out


def conformance(s, fam_out, styles, extra, fg, bg):
    """Mode C report. Loud family pairs: D2 (D1 floor + different hue name) under normal vision; under deutan and
    protan D1 at the reliable level (draft 2.1, lightness counts). L2 per family (worst tier over its roles).
    Quiet value tint (string) and dim, from the v2 extras."""
    loud_fams = [f for f in fam_out if any(st and st.get('family') == f and st.get('tier') in M.LOUD_TIERS
                                          for st in styles.values())]
    pairs = {}
    for a, b in itertools.combinations(loud_fams, 2):
        ha, hb = fam_out[a]['hex'], fam_out[b]['hex']
        e = {'d2_normal': bool(K.d2(ha, hb, strict_name=True))}
        for kind in ('deutan', 'protan'):
            e[f'd1_reliable_{kind}'] = bool(K.d1(K.cvd(ha, kind), K.cvd(hb, kind), 'reliable'))
        e['ok'] = all(e.values())
        pairs[f'{a}/{b}'] = e
    l2 = {}
    for f in fam_out:
        tiers = [K.lc_tier(K.alc(fam_out[f]['hex'], bg), 'L2', bool(st.get('bold') or s['tiers'].get(st.get('tier'), {}).get('weight') == 'bold'))
                 for st in styles.values() if st and st.get('family') == f and st.get('tier') in M.LOUD_TIERS]
        l2[f] = K.worst(*tiers) if tiers else 'n/a'
    c = {'pairs': pairs, 'L2': l2, 'L2_ok': {f: t not in ('fail',) for f, t in l2.items()}}
    if 'quiet' in extra:
        sst = styles.get('string') or {}
        sf = sst.get('family')
        c['quiet_value_ok'] = bool(extra['quiet'].get(sf, {}).get('ok')) if sf in extra['quiet'] else None
        ti = extra['tiers']
        c['dim_ok'] = bool(ti['dim_floor_ok'] and ti['dim_below_fg_ok'])
    fails = [f'{k}: ' + ', '.join(n for n, v in (('D2', e['d2_normal']), ('deutan', e['d1_reliable_deutan']),
                                                  ('protan', e['d1_reliable_protan'])) if not v)
             for k, e in pairs.items() if not e['ok']]
    fails += [f'L2 {f} ({t})' for f, t in l2.items() if t == 'fail']
    if c.get('quiet_value_ok') is False:
        fails.append('quiet value tint')
    if c.get('dim_ok') is False:
        fails.append('dim')
    c['failures'] = fails
    c['conforms'] = not fails
    return c


# ------------------------------------------------------------------ draft 3 (reader)

REC_BELOW = (6.0, 18.0)
REC_C = (0.04, 0.12)
QUIET3_C = (0.04, 0.08)   # default only; reader.yaml tiers.quiet.chroma is read
QUIET3_LC = 12.0
QUIET_CAP = 0.20      # joint quiet search: margins above this (de_text p=.8 − 1) earn nothing more


def _lch(L, C, h):
    return K.from_oklch(round(float(L), 4), round(float(C), 4), round(float(h), 2))


def recessive_colour(acc, fg, bg, avoid, below=REC_BELOW, crange=REC_C, level='reliable', max_sal=None):
    """Draft 3 recessive tier: the accent's OKLCH hue, lightness moved so |Lc| is `below` (6–18) under fg's, C in `crange`
    ([0.04, 0.12], measured after gamut fit). Must be D1 at `level` (reliable) from fg and every colour in `avoid` (dim,
    faded). Among passing points, the one with the largest de_text(p=.8) from fg. Returns (hex or None, info)."""
    f = K.alc(fg, bg)
    Lf = K.oklch(fg)[0]
    ha = K.oklch(acc)[2]
    best = None
    for c in np.unique(np.r_[np.arange(crange[0], crange[1] + 1e-9, 0.01), crange[1]]):
        for L in np.arange(max(0.0, Lf - 0.35), min(1.0, Lf + 0.35) + 1e-9, 0.01):
            q = _lch(L, c, ha)
            d = f - K.alc(q, bg)
            if not (below[0] <= d <= below[1]):
                continue
            C = K.oklch(q)[1]
            if not (crange[0] - 1e-3 <= C <= crange[1] + 1e-3):
                continue
            if max_sal is not None and K.salience_v2(q, fg, bg) > max_sal:
                continue
            if not K.d1(q, fg, level) or any(not K.d1(q, a, level) for a in avoid):
                continue
            m = K.de_text(q, fg, 0.8)
            if best is None or m > best[0]:
                best = (m, q)
    if best is None:
        return None, {'ok': False}
    q = best[1]
    return q, {'ok': True, 'hex': q, 'C': round(K.oklch(q)[1], 3), 'dlc_fg': round(K.alc(q, bg) - f, 1),
               'de_text_fg': round(best[0], 2), 'min_margin': round(min(K.de_text(q, a, 0.8) for a in [fg] + avoid) - 1, 2)}


def quiet_joint(accs, fg, bg, avoid, order, crange=QUIET3_C, lc_within=QUIET3_LC, level='reliable'):
    """Draft 3 quiet tier for several families at once. accs = {family: accent hex}; order = families, dropped first
    first (ascending keep). Each family's candidates: accent hue, C in `crange`, |Lc − Lc_fg| <= lc_within, D1 (`level`)
    from fg and every colour in `avoid` (recessive, dim). Pairwise: every two quiet colours D1 at `level`.
    Coordinate search over the candidate grids maximising (−Σ pairwise violation, min(QUIET_CAP, min margin),
    −Σ ΔE_OK to fg), two starts. If a violation remains, the family in the most violations (ties: lowest keep) fails
    and the search reruns without it. Returns {family: hex or None}, {family: reason}."""
    p = 0.8 if level == 'reliable' else 0.5
    f = K.alc(fg, bg)
    Lf = K.oklch(fg)[0]
    cand = {}
    fail = {}
    for fam, acc in accs.items():
        ha = K.oklch(acc)[2]
        cr = crange[fam] if isinstance(crange, dict) else crange
        pool = []
        for c in np.unique(np.r_[np.arange(cr[0], cr[1] + 1e-9, 0.01), cr[1]]):
            for L in np.arange(max(0.0, Lf - 0.16), min(1.0, Lf + 0.16) + 1e-9, 0.01):
                q = _lch(L, c, ha)
                if q in pool:
                    continue
                C = K.oklch(q)[1]
                if not (cr[0] - 1e-3 <= C <= cr[1] + 1e-3) or abs(K.alc(q, bg) - f) > lc_within:
                    continue
                own = min(K.de_text(q, a, p) for a in [fg] + avoid) - 1
                if own < 0:
                    continue
                pool.append(q)
        if pool:
            cand[fam] = pool
        else:
            fail[fam] = 'no candidate distinct from fg/recessive/dim'
    live = [x for x in order if x in cand]
    while True:
        if not live:
            break
        own = {x: np.array([min(K.de_text(q, a, p) for a in [fg] + avoid) - 1 for q in cand[x]]) for x in live}
        fgd = {x: np.array([K.de_ok(q, fg) for q in cand[x]]) for x in live}
        pm = {}
        for a, b in itertools.combinations(live, 2):
            pm[(a, b)] = np.array([[K.de_text(qa, qb, p) - 1 for qb in cand[b]] for qa in cand[a]])
            pm[(b, a)] = pm[(a, b)].T

        def score(sel):
            viol = sum(min(0.0, pm[(a, b)][sel[a], sel[b]]) for a, b in itertools.combinations(live, 2))
            mm = min([own[x][sel[x]] for x in live] + [pm[(a, b)][sel[a], sel[b]] for a, b in itertools.combinations(live, 2)])
            return (round(viol, 6), min(QUIET_CAP, mm), -sum(fgd[x][sel[x]] for x in live))
        best = None
        for start in ('own', 'chroma'):
            sel = {x: int(own[x].argmax()) if start == 'own' else int(np.argmax([K.oklch(q)[1] - 0.01 * K.de_ok(q, fg) for q in cand[x]]))
                   for x in live}
            cur = score(sel)
            for _ in range(12):
                moved = False
                for x in live:
                    for i in range(len(cand[x])):
                        if i == sel[x]:
                            continue
                        t = dict(sel)
                        t[x] = i
                        sc = score(t)
                        if sc > cur:
                            cur, sel, moved = sc, t, True
                if not moved:
                    break
            if best is None or cur > best[0]:
                best = (cur, sel)
        cur, sel = best
        if cur[0] >= 0:
            break
        cnt = {x: 0.0 for x in live}
        for a, b in itertools.combinations(live, 2):
            m = pm[(a, b)][sel[a], sel[b]]
            if m < 0:
                cnt[a] += 1 - m * 1e-3
                cnt[b] += 1 - m * 1e-3
        worst = max(live, key=lambda x: (cnt[x], -live.index(x)))
        fail[worst] = 'not distinct from another quiet colour'
        live.remove(worst)
    out = {x: None for x in accs}
    if live:
        for x in live:
            out[x] = cand[x][sel[x]]
    return out, fail


# reduced conformance (reader.yaml shedding comment): R0 full; R1 meta -> syntax loud; R2 + type -> callable;
# R3 = R2 with failing quiet cues -> default; R4 = R3 with keywords' recessive cue -> default; 'none' = loud
# families still fail (D2 normal / D1 reliable deutan+protan / L2) at R2.
READER_LEVELS = [('R0', frozenset()), ('R1', frozenset({'meta'})), ('R2', frozenset({'meta', 'type'}))]


def _reader_fill(p, s, styles, fam_out, reserve_diag, fg, bg):
    """Roles + extras for one reader level."""
    tiers = s['tiers']
    dim, faded, tier_info = dim_faded(fg, bg, tiers)
    rt = tiers['recessive']
    below = tuple(rt.get('below_default', REC_BELOW))
    rec = {'ok': None}
    rec_hex = None
    rec_fams = {st['family'] for st in styles.values() if st and st.get('tier') == 'recessive' and st.get('family') in fam_out}
    for fam in rec_fams:     # one family (syntax)
        # Spec-literal choice (max de_text from fg in the band). Harness addition: D1 (reliable) from the family's loud
        # accent too (keyword vs keyword.exit). Tried and rejected, because on muted creator palettes the loud accent is
        # itself weak (kanagawa exit salience < fg), so any loud-relative rule kills the cue: C <= C_loud (− .03), and
        # salience(recessive) <= salience(loud). `outshines_loud` records when keywords end up more salient than exits.
        rc = tuple(rt.get('chroma', REC_C))
        df = rt.get('distinct_from') or ['default', 'dim', 'faded', 'own_loud']   # 3.1: YAML list drives the avoid set
        rav = [{'dim': dim, 'faded': faded, 'own_loud': fam_out[fam]['hex']}[x] for x in df if x in ('dim', 'faded', 'own_loud')]
        rec_hex, rec = recessive_colour(fam_out[fam]['hex'], fg, bg, rav, below, rc,
                                        rt.get('distinct_level', 'reliable'))
        rec['family'] = fam
        # 3.1: the family's exit role is `strong` (bold), so the comparison gives the loud accent its bold term; the
        # draft-3 measure (no bold) is kept as outshines_loud_nobold.
        xb = any(st and st.get('family') == fam and tiers.get(st.get('tier'), {}).get('weight') == 'bold'
                 and st.get('tier') == 'strong' and rid.startswith('keyword.') for rid, st in styles.items())
        rec['outshines_loud'] = bool(rec_hex and K.salience_v2(rec_hex, fg, bg) > K.salience_v2(fam_out[fam]['hex'], fg, bg, xb))
        rec['outshines_loud_nobold'] = bool(rec_hex and K.salience_v2(rec_hex, fg, bg) > K.salience_v2(fam_out[fam]['hex'], fg, bg))
    qd = tiers['quiet']
    qfams = [f for f in M.drop_order(s) if f in fam_out
             and any(st and st.get('family') == f and st.get('tier') == 'quiet' for st in styles.values())]
    qdf = qd.get('distinct_from') or ['default', 'dim', 'recessive', 'other_quiet']   # 3.1: YAML list drives the avoid set
    avoid = ([rec_hex] if rec_hex and 'recessive' in qdf else []) + ([dim] if 'dim' in qdf else [])
    qcr = tuple(qd.get('chroma', QUIET3_C))     # no per-family cap (tried: C <= C_loud − .03 loses most kanagawa/zenburn quiets)
    qhex, qfail = quiet_joint({f: fam_out[f]['hex'] for f in qfams}, fg, bg, avoid, qfams,
                              qcr, float(qd.get('lc_within_default', QUIET3_LC)), qd.get('distinct_level', 'reliable'))
    quiet = {f: {'hex': qhex[f], 'ok': qhex[f] is not None, 'fallback': None if qhex[f] else 'default',
                 'reason': qfail.get(f), 'C': round(K.oklch(qhex[f])[1], 3) if qhex[f] else None,
                 'dlc_fg': round(K.alc(qhex[f], bg) - K.alc(fg, bg), 1) if qhex[f] else None} for f in qfams}
    sp = None
    if any(st and st.get('tier') == 'popout' and st.get('family') not in fam_out for st in styles.values()):
        sp = spare_accent(p, [v['hex'] for v in fam_out.values()], fg, bg, reserve_diag)
    roles = {}
    for rid, st in styles.items():
        if st is None:
            continue
        if rid == 'mod.deprecated':
            roles[rid] = {'fg': None, 'bold': False, 'italic': False, 'strike': True, 'family': None, 'tier': None, 'overlay': True}
            continue
        tier = st.get('tier', 'default')
        fam = st.get('family')
        hx = fg
        if fam in fam_out and tier == 'recessive':
            if rec_hex:
                hx = rec_hex
            else:
                fam, tier = None, 'default'
        elif fam in fam_out and tier == 'quiet':
            if quiet[fam]['ok']:
                hx = quiet[fam]['hex']
            else:
                fam, tier = None, 'default'
        elif fam in fam_out:
            hx = fam_out[fam]['hex']
        else:
            fam = None
            if tier == 'popout' and sp:
                hx, fam = sp['hex'], 'oddball'
            elif tier in ('quiet', 'recessive'):
                tier = 'default'
            else:
                hx = {'faded': faded, 'dim': dim}.get(tier, fg)
        bold = bool(st['bold'] or tiers.get(tier, {}).get('weight') == 'bold')
        roles[rid] = {'fg': hx, 'bold': bold, 'italic': st.get('slant') == 'italic', 'strike': bool(st.get('strike')),
                      'family': fam, 'tier': tier}
        if rid == 'mod.unnecessary':
            roles[rid]['overlay'] = True
    sst = styles.get('string') or {}
    sinfo = 'own' if sst.get('tier') == 'quiet' and quiet.get(sst.get('family'), {}).get('ok') else 'none'
    tier_info = dict(tier_info, recessive=rec_hex, recessive_ok=rec.get('ok'))
    extra = {'tiers': tier_info, 'quiet': quiet, 'recessive': rec, 'quiet_borrow': None, 'strings_quiet': sinfo,
             'popout': {'hex': sp['hex'], 'hue_name': sp['name'], 'slot': sp['slot'], 'C': round(sp['C'], 3)} if sp else None}
    return roles, extra


def _reader_checks(s, fam_out, styles, extra, fg, bg):
    c = conformance(s, fam_out, styles, extra, fg, bg)
    base = all(c['L2_ok'].values()) and c.get('dim_ok', True)
    loud_ok = all(e['ok'] for e in c['pairs'].values()) and base
    c['loud_ok_normal'] = all(e['d2_normal'] for e in c['pairs'].values()) and base
    rec_ok = extra['recessive'].get('ok') is not False
    q_ok = all(v['ok'] for v in extra['quiet'].values())
    if not rec_ok:
        c['failures'].append('recessive')
    c['failures'] += [f'quiet {f}' for f, v in extra['quiet'].items() if not v['ok']]
    c['failures'] = list(dict.fromkeys(x for x in c['failures'] if x != 'quiet value tint'))
    c['recessive_ok'] = rec_ok
    c['quiet_ok'] = {f: v['ok'] for f, v in extra['quiet'].items()}
    c['conforms'] = not c['failures']
    return loud_ok, rec_ok, q_ok, c


def _reader_level(built, key):
    """(built level, level name). First of R0..R2 where loud, recessive and every quiet pass; else R3 (R2 with quiet
    failures shed) if loud + recessive pass at R2; else R4 if loud passes at R2; else 'none' (first level tried)."""
    for b in built:
        if b['name'] != 'none' and all(b[key]):
            return b, b['name']
    last = built[-1]
    if last['name'] == 'R2':
        lo, ro, _ = last[key]
        if lo and ro:
            return last, 'R3'
        if lo:
            return last, 'R4'
    return built[0], 'none'


def map_reader(p, setname='reader', mode='C', max_fid=MAX_FID, reserve_diag=RESERVE_DIAG, assign=None):
    """Draft 3 (reader) mapping with reduced-conformance shedding. Mode C: the creator's slots, levels R0 -> R1 -> R2
    tried in turn. Modes A/B: capacity bounds the starting level (5 hues R0, 4 R1, 3 R2; fewer -> ladder drops,
    level 'none'). The first level whose loud families, recessive and every quiet colour pass is used; else R3 (quiet
    failures shed, R2 theme), else R4 (recessive failure shed too), else 'none' (the starting-level theme, failures listed)."""
    s = M.load_set(setname)
    fg, bg = K.norm(p['fg']), K.norm(p['bg'])
    err = error_colour(p)
    hf = M.hue_families(s)
    kw = cand_kw(s)
    if mode == 'C':
        if assign is None:
            assign = load_assignments(setname, p['id'])
        if not assign:
            raise ValueError(f'mode C needs an assignment for {setname} / {p["id"]}')
        assign = dict(assign)
        assign.pop('string_override', None)
        cc = creator_candidates(p, assign, max_fid)
        avail = set(f for f in hf if f in cc)
        cap, ncand = len(avail), 0
        plan = [(n, avail - shed) for n, shed in READER_LEVELS]
    else:
        cands = candidates(p, max_fid, reserve_diag=reserve_diag, **kw)
        ncand = len(cands)
        okn, Aok = compat([c['hex'] for c in cands], fg, bg, strict=kw['strict'])
        cap = len(max_clique(okn, Aok))
        plan = [(n, set(hf) - shed) for n, shed in READER_LEVELS if len(hf) - len(shed) <= cap]
        if not plan:
            plan = [('none', M.kept_by_ladder(s, min(len(hf), cap)))]
    built = []
    for name, kept in plan:
        styles = M.effective_styles(s, kept)
        fams, A, Ad = family_pair_weights(s, [f for f in M.drop_order(s) if f in kept], styles)
        need = family_need(s, fams, styles)
        if mode == 'C':
            lc = [cc[f] for f in fams]
            amap, obj = {f: i for i, f in enumerate(fams)}, 0.0
        else:
            lc = cands
            cl = k_cliques(okn, Aok, len(fams)) if fams else []
            amap, obj = assign_fams(cands, fams, A, Ad, need, mode, fg, bg, cl, strict=kw['strict'], v2=True)
        fam_out = {f: {'src': lc[i]['src'], 'slot': lc[i]['slot'], 'hex': lc[i]['hex'], 'fidelity': round(lc[i]['fid'], 4),
                       'hue_name': lc[i]['name'], 'lc': round(lc[i]['lc'], 1), 'need': round(need.get(f, 0), 3),
                       'C': round(lc[i]['C'], 3)} for f, i in amap.items()}
        roles, extra = _reader_fill(p, s, styles, fam_out, reserve_diag, fg, bg)
        lo, ro, qo, conf = _reader_checks(s, fam_out, styles, extra, fg, bg)
        built.append({'name': name, 'kept': kept, 'fam_out': fam_out, 'roles': roles, 'extra': extra, 'obj': obj,
                      'ok': (lo, ro, qo), 'ok_normal': (conf['loud_ok_normal'], ro, qo), 'conf': conf})
    pick, level = _reader_level(built, 'ok')
    level_normal = _reader_level(built, 'ok_normal')[1]
    kept = pick['kept']
    out = {
        'palette': p['id'], 'family': p['family'], 'variant': p['variant'], 'set': setname, 'mode': mode, 'version': 3,
        'bg': bg, 'fg': fg, 'max_fid': max_fid, 'capacity': cap, 'n_candidates': ncand, 'reserve_diag': reserve_diag,
        'diagnostic': {'error_slot': err[0], 'error': err[1]} if err else None,
        'hue_families_required': len(hf), 'families_kept': [f for f in M.drop_order(s) if f in kept][::-1],
        'families_dropped': [f for f in M.drop_order(s) if f not in kept],
        'objective': round(pick['obj'], 4), 'faded_mix_t': None, 'families': pick['fam_out'], 'roles': pick['roles'],
        'variant_fidelity_max': 0.0, 'level': level, 'level_normal': level_normal,
        'levels_tried': {b['name']: {'loud_ok': b['ok'][0], 'recessive_ok': b['ok'][1], 'quiet_ok': b['ok'][2],
                                     'failures': b['conf']['failures']} for b in built},
    }
    out.update(pick['extra'])
    out['conformance'] = dict(pick['conf'], level=level, level_normal=level_normal)
    if mode == 'C':
        out['assign'] = assign
    return out


def map_palette(p, setname='landmark', mode='A', max_fid=MAX_FID, reserve_diag=RESERVE_DIAG, assign=None):
    """mode 'C' = creator assignment: `assign` = {family: slot} (plus optional label-only `string_override: slot`).
    Each family uses its assigned slot's colour (lightness-derived to the tier target, fidelity cap max_fid); no ladder
    drops; `conformance` is attached instead."""
    s = M.load_set(setname)
    if M.is_v3(s):
        return map_reader(p, setname, mode, max_fid, reserve_diag, assign)
    v2 = M.is_v2(s)
    kw = cand_kw(s)
    fg, bg = K.norm(p['fg']), K.norm(p['bg'])
    err = error_colour(p)
    hf = M.hue_families(s)
    string_override = None
    if mode == 'C':
        if assign is None:
            assign = load_assignments(setname, p['id'])
        if not assign:
            raise ValueError(f'mode C needs an assignment for {setname} / {p["id"]}')
        assign = dict(assign)
        string_override = assign.pop('string_override', None)
        cc = creator_candidates(p, assign, max_fid)
        kept = set(f for f in hf if f in cc)
        cands, cap = [], len(kept)
    else:
        cands = candidates(p, max_fid, reserve_diag=reserve_diag, **kw)
        hexes = [c['hex'] for c in cands]
        okn, Aok = compat(hexes, fg, bg, strict=kw['strict'])
        cap = len(max_clique(okn, Aok))
        k = min(len(hf), cap)
        kept = M.kept_by_ladder(s, k)
    styles = M.effective_styles(s, kept)
    # deterministic family order (YAML drop order): ties in the assignment objective are broken by it
    fams, A, Ad = family_pair_weights(s, [f for f in M.drop_order(s) if f in kept], styles)
    need = family_need(s, fams, styles)
    if mode == 'C':
        amap, obj = {}, 0.0
        cands = [cc[f] for f in fams]
        amap = {f: i for i, f in enumerate(fams)}
    else:
        cl = k_cliques(okn, Aok, k) if k else []
        amap, obj = assign_fams(cands, fams, A, Ad, need, mode, fg, bg, cl, strict=kw['strict'], v2=v2)
    tiers = s['tiers']
    fam_out = {}
    for f, i in amap.items():
        c = cands[i]
        fam_out[f] = {'src': c['src'], 'slot': c['slot'], 'hex': c['hex'], 'fidelity': round(c['fid'], 4),
                      'hue_name': c['name'], 'lc': round(c['lc'], 1), 'need': round(need.get(f, 0), 3),
                      'C': round(c['C'], 3)}
    roles = {}
    var_fid = []
    extra = {}
    if v2:
        dim, faded, tier_info = dim_faded(fg, bg, tiers)
        fade_t = None
        # quiet colours, highest-keep family first; each must pass D1 (reliable) vs fg, dim and earlier quiets
        qd = tiers['quiet']
        crange = tuple(qd.get('chroma') or QUIET_C)
        qlevel = 'reliable' if qd.get('distinct_level', 'reliable') == 'reliable' else 'floor'
        quiet = {}
        quiet_fams = [f for f in sorted(fam_out, key=lambda f: -M.rank_of(s, f))
                      if any(st and st.get('family') == f and st.get('tier') == 'quiet' for st in styles.values())]
        for f in quiet_fams:
            q = quiet_colour(fam_out[f]['hex'], fg, bg, [dim] + [v['hex'] for v in quiet.values() if v['hex']], crange, qlevel)
            qfb = s['families'][f].get('quiet_fallback') or {}
            quiet[f] = {'hex': q, 'ok': q is not None, 'fallback': None if q else qfb.get('tier', 'default'),
                        'C': round(K.oklch(q)[1], 3) if q else None,
                        'dlc_fg': round(K.alc(q, bg) - K.alc(fg, bg), 1) if q else None}
        # borrowed quiet tint (quiet_fallback {tier: quiet, family: any_kept}): quiet roles of dropped families, and of
        # kept families whose own quiet colour failed. Best D1 margin vs fg and dim over the kept accents.
        need_borrow = any(st and st.get('quiet_borrow') for st in styles.values()) or any(
            not v['ok'] and v['fallback'] == 'quiet' for v in quiet.values())
        borrow = None
        if need_borrow:
            used = [dim] + [v['hex'] for v in quiet.values() if v['hex']]
            best = None
            for f in fam_out:
                q = quiet_colour(fam_out[f]['hex'], fg, bg, used, crange, qlevel)
                if q is None:
                    continue
                m = min(K.de_text(q, fg, 0.8), K.de_text(q, dim, 0.8))
                if best is None or m > best[0]:
                    best = (m, q, f)
            if best:
                borrow = {'hex': best[1], 'from': best[2], 'C': round(K.oklch(best[1])[1], 3), 'margin': round(best[0], 2),
                          'dlc_fg': round(K.alc(best[1], bg) - K.alc(fg, bg), 1)}
        # how do the strings end up: own accent tint / borrowed tint / none (default)
        sinfo = 'none'
        sst = styles.get('string')
        if sst and sst.get('tier') == 'quiet':
            if sst.get('family') in fam_out and quiet.get(sst['family'], {}).get('ok'):
                sinfo = 'own'
            elif borrow and (sst.get('quiet_borrow') or quiet.get(sst.get('family'), {}).get('fallback') == 'quiet'):
                sinfo = 'borrowed'
        sp = None
        if any(st and st.get('tier') == 'popout' and st.get('family') not in fam_out for st in styles.values()):
            sp = spare_accent(p, [v['hex'] for v in fam_out.values()], fg, bg, reserve_diag)
        extra = {'tiers': tier_info, 'quiet': quiet, 'quiet_borrow': borrow, 'strings_quiet': sinfo,
                 'popout': {'hex': sp['hex'], 'hue_name': sp['name'], 'slot': sp['slot'], 'C': round(sp['C'], 3)} if sp else None}
    else:
        faded, fade_t = K.fade_to_lc(fg, bg, tiers['faded']['lc'][0])
    for rid, st in styles.items():
        if st is None:
            continue
        if rid == 'mod.deprecated':
            roles[rid] = {'fg': None, 'bold': False, 'italic': False, 'strike': True, 'family': None, 'tier': None, 'overlay': True}
            continue
        tier = st.get('tier', 'default')
        fam = st.get('family')
        if v2:
            qfrom = None
            if tier == 'quiet' and fam is None and st.get('quiet_borrow'):
                b = extra['quiet_borrow']
                if b:
                    hx, qfrom = b['hex'], b['from']
                else:
                    tier = 'default'
            elif fam in fam_out and tier == 'quiet':
                q = extra['quiet'][fam]
                if q['ok']:
                    hx = q['hex']
                else:
                    b = extra['quiet_borrow']
                    if q['fallback'] == 'quiet' and b:
                        fam, hx, qfrom = None, b['hex'], b['from']
                    else:
                        fam, tier = None, ('default' if q['fallback'] == 'quiet' else q['fallback'])
            if qfrom:
                pass
            elif fam in fam_out:
                if tier != 'quiet':
                    hx = fam_out[fam]['hex']
            else:
                fam = None
                if tier == 'popout' and extra['popout']:
                    hx, fam = extra['popout']['hex'], 'oddball'
                else:
                    hx = {'faded': faded, 'dim': dim}.get(tier, fg)
        elif fam in fam_out:
            hx = fam_out[fam]['hex']
            if tier == 'popout':
                hx, _, fpop = K.shift_l_to_lc(fam_out[fam]['src'], bg, tiers['popout']['lc'][0], max_fid=max_fid)
                if K.alc(hx, bg) < K.alc(fam_out[fam]['hex'], bg):
                    hx = fam_out[fam]['hex']
            v = st.get('variant')
            if v == 'lightness':
                hx, vf, how = lightness_variant(hx, p, bg)
                var_fid.append(vf)
            elif v == 'chroma-low':
                hx = K.chroma_scale(hx, 0.5)
                var_fid.append(K.de_ok(hx, fam_out[fam]['hex']))
        else:
            fam = None
            if tier == 'faded':
                hx = faded
            elif tier == 'popout':
                hx = fg
            else:
                hx = fg
        bold = st['bold'] if not v2 else bool(st['bold'] or tiers.get(tier, {}).get('weight') == 'bold')
        roles[rid] = {'fg': hx, 'bold': bold, 'italic': st.get('slant') == 'italic',
                      'strike': bool(st.get('strike')), 'family': fam, 'tier': tier}
        if v2 and qfrom:
            roles[rid]['quiet_from'] = qfrom
        if rid == 'mod.unnecessary':
            roles[rid]['overlay'] = True
    if string_override and 'string' in roles and roles['string'].get('family'):
        sc = creator_candidates(p, {'string': string_override}, max_fid)['string']
        roles['string']['fg'] = sc['hex']
        extra['string_override'] = {'slot': string_override, 'hex': sc['hex']}
    out = {
        'palette': p['id'], 'family': p['family'], 'variant': p['variant'], 'set': setname, 'mode': mode,
        'version': 2 if v2 else 1,
        'bg': bg, 'fg': fg, 'max_fid': max_fid, 'capacity': cap, 'n_candidates': len(cands),
        'reserve_diag': reserve_diag,
        'diagnostic': {'error_slot': err[0], 'error': err[1]} if err else None,
        'hue_families_required': len(hf), 'families_kept': [f for f in M.drop_order(s) if f in kept][::-1],
        'families_dropped': [f for f in M.drop_order(s) if f not in kept],
        'objective': round(obj, 4), 'faded_mix_t': None if fade_t is None else round(fade_t, 3),
        'families': fam_out, 'roles': roles,
        'variant_fidelity_max': round(max(var_fid), 4) if var_fid else 0.0,
    }
    out.update(extra)
    if mode == 'C':
        out['assign'] = assign
        out['conformance'] = conformance(s, fam_out, styles, extra, fg, bg)
    return out


# ------------------------------------------------------------------ evaluation

def _confused(ra, rb, kind, same_family_design, fg, bg, v2=False):
    """v1: D2 for pairs of different families, D1 floor for designed same-family pairs.
    v2: D2 with a different hue NAME (spec fix (a)) only when the two roles are in different families and
    at least one of them is drawn loud (loud/strong/popout); every other distinction (quiet tint vs fg,
    dim vs default, quiet vs loud of one family, two quiet tints) is designed as D1 floor."""
    if (ra['bold'] != rb['bold']) or (ra['italic'] != rb['italic']) or (ra['strike'] != rb['strike']):
        return False
    a, b = K.cvd(ra['fg'], kind), K.cvd(rb['fg'], kind)
    if a == b:
        return True
    if v2:
        loud = ra['tier'] in M.LOUD_TIERS and ra.get('family') or rb['tier'] in M.LOUD_TIERS and rb.get('family')
        if ra.get('family') != rb.get('family') and loud:
            return not K.d2(a, b, strict_name=True)
        return not K.d1(a, b, 'floor')
    if same_family_design:
        return not K.d1(a, b, 'floor')
    return not K.d2(a, b)


def role_salience(r, fg, bg):
    return K.salience_v2(r['fg'], fg, bg, r['bold'])


def s1_check(s, R, fg, bg, margin=K.S1_MARGIN):
    """S1 (draft 2): for every pair of adjacent declared tiers that are in use (after fallbacks),
    min salience(upper tier roles) >= max salience(lower tier roles) + margin. Returns (ok, {pair: ok})."""
    by = {}
    for rid, r in R.items():
        if r.get('overlay') or not r.get('fg') or r.get('tier') is None:
            continue
        by.setdefault(r['tier'], []).append(role_salience(r, fg, bg))
    used = [t for t in M.tier_order(s) if t in by]
    res = {}
    for lo, hi in zip(used, used[1:]):
        res[f'{lo}<{hi}'] = min(by[hi]) >= max(by[lo]) + margin
    return all(res.values()), res


S1B_MARGIN = 0.03   # S1b: loud chroma exceeds quiet chroma by at least this much (OKLCH C)


def s1_ab(s, R, fg, bg):
    """Draft 2.1 S1: two orderings only.
    (a) lightness: faded < dim < default by |Lc| (default = fg). Checked over the tiers in use; strict inequality.
    (b) chroma: quiet < loud by OKLCH C with margin S1B_MARGIN: max C(quiet roles) + margin <= min C(loud/strong roles).
        None when no quiet role is tinted (nothing to order) or the set has no quiet tier.
    Returns (a, b)."""
    by = {}
    for rid, r in R.items():
        if r.get('overlay') or not r.get('fg') or r.get('tier') is None:
            continue
        by.setdefault(r['tier'], []).append(r)
    lc = lambda rs, f: f(K.alc(r['fg'], bg) for r in rs)
    f_fg = K.alc(fg, bg)
    # ascending |Lc| across present tiers: faded < dim < default
    a = True
    present = [(t, by[t]) for t in ('faded', 'dim', 'recessive') if by.get(t)]   # draft 3: recessive sits below default
    for i in range(len(present) - 1):
        a &= lc(present[i][1], max) < lc(present[i + 1][1], min)
    if present:
        a &= lc(present[-1][1], max) < f_fg
    b = None
    if M.is_v2(s):
        quiet = by.get('quiet', [])
        loud = [r for t in ('loud', 'strong') for r in by.get(t, []) if r.get('family')]
        if quiet and loud:
            b = max(K.oklch(r['fg'])[1] for r in quiet) + S1B_MARGIN <= min(K.oklch(r['fg'])[1] for r in loud)
    return bool(a), (None if b is None else bool(b))


def evaluate(theme, setname=None):
    from scipy.stats import spearmanr
    s = M.load_set(setname or theme['set'])
    v2 = M.is_v2(s)
    fg, bg = theme['fg'], theme['bg']
    R = theme['roles']
    ink, _ = M.ink_shares()
    res = {}
    # L1
    v = K.alc(fg, bg)
    t = K.lc_tier(v, 'L1')
    if K.wcag(fg, bg) < 4.5 and t in ('strict', 'default'):
        t = 'floor'
    res['L1'] = t
    res['fg_lc'] = round(v, 1)
    # L2: hue-bearing roles
    l2 = [K.lc_tier(K.alc(r['fg'], bg), 'L2', r['bold']) for rid, r in R.items() if r.get('family') and not r.get('overlay')]
    res['L2'] = K.worst(*l2) if l2 else 'strict'
    # L3: prose roles
    l3 = []
    for rid in ('comment', 'comment.doc'):
        r = R.get(rid)
        if not r:
            continue
        lv = K.alc(r['fg'], bg)
        tt = K.lc_tier(lv, 'L3')
        if lv > v - 10 and tt in ('strict', 'default'):
            tt = 'floor'
        l3.append(tt)
    res['L3'] = K.worst(*l3) if l3 else 'strict'
    l4 = [K.lc_tier(K.alc(r['fg'], bg), 'L4') for r in R.values() if r.get('tier') == 'faded' and r.get('fg')]
    res['L4'] = K.worst(*l4) if l4 else 'strict'
    res['L123'] = K.worst(res['L1'], res['L2'], res['L3'])
    # S1 (draft 2 salience model, all sets)
    ok, pairs = s1_check(s, R, fg, bg)
    res['S1_sal'] = bool(ok)       # draft-2 all-adjacent-tiers salience check (superseded by 2.1 S1a/S1b)
    res['S1_pairs'] = pairs
    res['S1a'], res['S1b'] = s1_ab(s, R, fg, bg)
    res['S1'] = res['S1a'] and res['S1b'] is not False
    # S1 as computed for draft 1 (kept for comparison)
    def sal(r, k):
        return K.salience(r['fg'], bg, r['bold'], chroma_k=k)
    by_tier = {}
    for rid, r in R.items():
        if r.get('overlay') or not r.get('fg'):
            continue
        by_tier.setdefault(r['tier'], []).append(r)
    s1a = True
    if 'faded' in by_tier and 'default' in by_tier:
        s1a &= max(K.alc(r['fg'], bg) for r in by_tier['faded']) + 7.5 <= K.alc(fg, bg)
    if 'popout' in by_tier and 'strong' in by_tier:
        s1a &= min(sal(r, K.HK_K) for r in by_tier['popout']) >= max(sal(r, K.HK_K) for r in by_tier['strong']) + 7.5
    s1b = True
    hued_sal = [sal(r, SAL_K) for r in by_tier.get('salient', []) + by_tier.get('loud', []) if r.get('family')]
    if hued_sal:
        s1b = min(hued_sal) >= K.salience(fg, bg, chroma_k=SAL_K) + 7.5
    res['S1_v1'] = bool(s1a and s1b)
    # family need order vs measured salience (mode A target)
    fams = theme['families']
    if len(fams) >= 2:
        fl = list(fams)
        sv = [K.salience_v2(fams[f]['hex'], fg, bg) for f in fl] if v2 else [K.salience(fams[f]['hex'], bg, chroma_k=SAL_K) for f in fl]
        rho = spearmanr([fams[f]['need'] for f in fl], sv)[0]
        res['need_sal_rho'] = None if rho != rho else round(float(rho), 3)
    else:
        res['need_sal_rho'] = None
    # confusion cost (C6) + beacon loss
    styles_full = M.effective_styles(s)
    md = M.must_differ_pairs(s)
    lam = M.beacon_lambda()
    unsep = M.unseparated_pairs()
    for kind in ('normal', 'deutan'):
        cost = disc = scost = sdisc = 0.0
        n = 0
        for a, b, w in md:
            if a not in R or b not in R:
                continue
            same = styles_full[a]['family'] == styles_full[b]['family']
            if _confused(R[a], R[b], kind, same, fg, bg, v2):
                cost += M.pair_cost(a, b)
                disc += M.pair_cost(a, b, discounted=True)
                n += 1
                if frozenset((a, b)) not in unsep:
                    scost += M.pair_cost(a, b)
                    sdisc += M.pair_cost(a, b, discounted=True)
        res[f'confusion_{kind}'] = cost
        res[f'confusion_{kind}_disc'] = disc
        res[f'confusion_{kind}_sep'] = scost           # separable cost: excludes pairs no set separates
        res[f'confusion_{kind}_disc_sep'] = sdisc
        res[f'confused_pairs_{kind}'] = n
    cur = {rid: {'family': r['family'], 'tier': r['tier'], 'bold': r['bold']} for rid, r in R.items()}
    bl = M.beacon_loss(s, cur)
    res['beacon_loss'] = bl
    res['C6_disc'] = res['confusion_normal_disc'] + lam['disc'] * bl
    res['C6_raw'] = res['confusion_normal'] + lam['raw'] * bl
    res['C6_disc_deutan'] = res['confusion_deutan_disc'] + lam['disc'] * bl
    res['C6_disc_sep'] = res['confusion_normal_disc_sep'] + lam['disc'] * bl
    res['fg_limited'] = bool(theme.get('tiers', {}).get('fg_limited', False))
    res['strings_quiet'] = theme.get('strings_quiet', '')
    # C2 / C1 / budget
    styles = {rid: {'family': r['family'], 'tier': r['tier'], 'bold': r['bold'], 'scope': s['styles'].get(rid, {}).get('scope') or ('top-level' if s['styles'].get(rid, {}).get('bold_if') == 'top-level' else None),
                    'qfrom': r.get('quiet_from')}
              for rid, r in R.items()}
    styles['variable.use'] = {'family': None, 'tier': 'default', 'bold': False}
    col = 0.0
    byfam = {}
    split = {'loud': 0.0, 'quiet': 0.0, 'recessive': 0.0, 'dim': 0.0, 'faded': 0.0}
    tier_r, pop_r, sal_r, inks = [], [], [], []
    swi = 0.0
    budget_tier = 0.0
    for key, rid, st in stat_roles(s, styles):
        r = R[rid]
        sh = ink.get(key, 0.0)
        fam = st.get('family')
        local = key.endswith('.local')
        hx = fg if local else r['fg']
        bold = False if local else st.get('bold', False)
        tier = 'default' if local else (st.get('tier') or 'default')
        if (fam or st.get('qfrom')) and not local and K.oklch(hx)[1] >= K.GREY_C:
            col += sh
            byfam[fam or st['qfrom']] = byfam.get(fam or st['qfrom'], 0) + sh
        if not local:
            if fam and tier in M.LOUD_TIERS:
                split['loud'] += sh
            elif (fam or st.get('qfrom')) and tier == 'quiet':
                split['quiet'] += sh
            elif fam and tier == 'recessive':
                split['recessive'] += sh
            elif tier == 'dim':
                split['dim'] += sh
            elif tier == 'faded':
                split['faded'] += sh
        sv = K.salience_v2(hx, fg, bg, bold)
        swi += sh * max(0.0, sv)
        budget_tier += sh * M.tier_above_default(s, tier)
        tier_r.append(M.tier_rank(s, tier))
        pop_r.append(K.salience(hx, bg, bold, chroma_k=SAL_K))
        sal_r.append(sv)
        inks.append(sh)
    _, beacon, _ = M.weights()
    tot = sum(beacon.values())
    # beacon coverage: beacon value on roles that differ from plain default ink (hue, bold, or a non-default tier)
    cov = sum(v for rid, v in beacon.items() if rid in R and (R[rid]['family'] or R[rid]['bold'] or (R[rid]['tier'] or 'default') != 'default'))
    res['beacon_coverage'] = cov / tot if tot else 0.0
    res['coloured_ink'] = col
    res['coloured_ink_by_family'] = byfam
    res['ink_split'] = split
    res['sal_weighted_ink'] = swi          # C2 headline (draft 2) = salience budget
    res['salience_budget_tier'] = budget_tier
    res['C1_rho_tier'] = float(spearmanr(tier_r, inks)[0])
    res['C1_rho'] = float(spearmanr(sal_r, inks)[0])
    res['C1_rho_v1model'] = float(spearmanr(pop_r, inks)[0])
    return res


# ------------------------------------------------------------------ CLI

def load_palettes():
    with open(os.path.join(M.ROOT, 'data', 'palettes.jsonl')) as f:
        return [json.loads(l) for l in f]


EXAMPLES = ['base16/tomorrow-night', 'base16/solarized-light', 'base16/gruvbox-dark-hard', 'base24/dracula',
            'ansi16/Builtin Tango Dark', 'base16/nord']


def main(argv):
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('ids', nargs='*')
    ap.add_argument('--set', default=None)
    ap.add_argument('--mode', default=None)
    a = ap.parse_args(argv)
    pals = {p['id']: p for p in load_palettes()}
    ids = a.ids or [i for i in EXAMPLES if i in pals]
    sets = [a.set] if a.set else M.SETS
    modes = [a.mode] if a.mode else ['A', 'B']
    od = os.path.join(M.OUT, 'mapped')
    os.makedirs(od, exist_ok=True)
    for pid in ids:
        if pid not in pals:
            print('unknown palette', pid, [k for k in pals if pid.lower() in k.lower()][:10])
            continue
        for sn in sets:
            for mo in modes:
                th = map_palette(pals[pid], sn, mo)
                th['checks'] = evaluate(th)
                fn = os.path.join(od, f"{pid.replace('/', '__').replace(' ', '_')}__{sn}__{mo}.json")
                with open(fn, 'w') as f:
                    json.dump(th, f, indent=1)
                fams = ', '.join(f"{f}={v['hex']}({v['hue_name']},{v['slot']})" for f, v in th['families'].items())
                print(f"{pid} {sn} {mo}: cap={th['capacity']} kept={th['families_kept']} {fams}")


if __name__ == '__main__':
    main(sys.argv[1:])
