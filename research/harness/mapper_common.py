"""Shared loaders for pattern sets, roles, weights, ink share and adjacency.

Used by static_checks.py, mapper.py, score_palettes.py and ladder.py.

Interpretation choices (flagged in the reports as spec issues where relevant):
  * `inherits`: the child's families and styles are merged over the parent's key by key;
    channels and tiers come from the parent unless the child redefines them.
  * Draft 1 sets (landmark_v1, hybrid_v1, label) use `ladder`: LOWER rank = dropped/merged FIRST
    (the v1 YAML comment says the opposite; 00-framework §4's order meta -> exit -> prose ->
    definition only matches ascending rank). Draft 2 sets (landmark, hybrid) use `keep`: HIGHER =
    kept longer, i.e. also ascending = dropped first. drop_order() handles both.
  * Draft 2 sets are recognised by a `loud` tier (is_v2). Their tiers, in ascending salience, are
    faded < dim < default < quiet < loud < strong < popout. A family's quiet roles follow
    `quiet_fallback` (else default, NOT `fallback`) when the family is dropped.
  * A dropped family's roles follow `fallback`: {family: g} -> recolour with g (chained if g is
    also dropped); {family: null, tier: T, slant: S} -> default hue, tier T, slant S, variant
    removed. A family without a fallback (oddball) keeps its tier with default hue.
  * Overlay roles (mod.*) are excluded from pair analyses.
"""
from __future__ import annotations

import csv
import os
from functools import lru_cache
from itertools import combinations

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAT = os.path.join(ROOT, 'patterns')
OUT = os.path.join(ROOT, 'out')

SETS = ['landmark', 'hybrid', 'label', 'landmark_v1', 'hybrid_v1', 'reader']
V2_SETS = ['landmark', 'hybrid', 'reader']
TIER_RANK = {'faded': 0, 'default': 1, 'salient': 2, 'strong': 3, 'popout': 4, 'critical': 5}   # v1 sets
LOUD_TIERS = ('salient', 'loud', 'strong', 'popout')   # tiers whose hue use counts against capacity


def is_v2(s):
    return 'loud' in s.get('tiers', {})


def is_v3(s):
    """Draft 3 (reader): has a `recessive` tier (hued keywords below default) and multi-family quiet."""
    return 'recessive' in s.get('tiers', {})


def tier_order(s):
    """Declared tiers in ascending salience (YAML order), excluding the diagnostic layer."""
    return [t for t, d in s['tiers'].items() if 'layer' not in (d or {})]


def tier_rank(s, t):
    order = tier_order(s)
    return order.index(t if t in order else 'default')


def tier_above_default(s, t):
    return max(0, tier_rank(s, t) - tier_rank(s, 'default'))


def _y(name):
    with open(os.path.join(PAT, name)) as f:
        return yaml.safe_load(f)


@lru_cache(maxsize=None)
def roles():
    return _y('roles.yaml')['roles']


def role_ids(overlay=False):
    return [r['id'] for r in roles() if overlay or not r.get('overlay')]


@lru_cache(maxsize=None)
def role_info():
    return {r['id']: r for r in roles()}


@lru_cache(maxsize=None)
def load_set(name):
    raw = _y(f'{name}.yaml')
    if 'inherits' in raw:
        base = dict(load_set(raw['inherits']))
        out = {k: v for k, v in base.items()}
        out['families'] = {**base['families'], **raw.get('families', {})}
        out['styles'] = {**base['styles'], **raw.get('styles', {})}
        for k in ('channels', 'tiers'):
            if k in raw:
                out[k] = raw[k]
        out['name'] = raw['name']
        out['inherits'] = raw['inherits']
        return out
    return dict(raw)


def hue_families(s):
    return [f for f, d in s['families'].items() if d.get('hue')]


def rank_key(s):
    return 'keep' if any('keep' in d for d in s['families'].values()) else 'ladder'


def rank_of(s, f):
    return s['families'][f][rank_key(s)]


def drop_order(s):
    """Families in the order the YAML drops them (ascending `keep` / `ladder` rank)."""
    return sorted(hue_families(s), key=lambda f: rank_of(s, f))


def kept_by_ladder(s, k):
    order = drop_order(s)
    return set(order[len(order) - k:]) if k > 0 else set()


def effective_styles(s, kept=None, order_dropped=None):
    """role -> style dict after dropping families not in `kept` (default: all kept).
    Style keys: family, tier, bold, slant, variant, strike, scope."""
    fams = s['families']
    kept = set(hue_families(s)) if kept is None else set(kept)
    tiers = s['tiers']
    out = {}
    for rid in role_ids(overlay=True):
        st = dict(s['styles'].get(rid, {}))
        if not st:
            out[rid] = None
            continue
        fam = st.get('family')
        seen = set()
        while fam is not None and fam not in kept:
            if fam in seen:
                fam = None
                break
            seen.add(fam)
            fb = fams.get(fam, {}).get('fallback')
            if fb is None:
                fam = None
                if st.get('tier') in ('quiet', 'recessive'):
                    st['tier'] = 'default'      # a family's reading-layer cue with nowhere to go: default ink
                break
            if fb.get('family'):
                fam = fb['family']
                # {family: g, tier: T} (reader: meta -> syntax loud): reading-layer roles (quiet/recessive) take tier T;
                # loud/strong roles keep their tier (bold binding sites stay bold).
                if fb.get('tier') and st.get('tier') in ('quiet', 'recessive'):
                    st['tier'] = fb['tier']
                continue
            qfb = fams.get(fam, {}).get('quiet_fallback')
            fam = None
            if st.get('tier') == 'quiet':
                # quiet roles: `quiet_fallback`, else default (same rule as a failed quiet colour). Without this,
                # hybrid's quiet definition use sites would inherit `fallback: strong` and turn bold.
                # Draft 2.1: {tier: quiet, family: any_kept, else: default} = borrow the quiet tint of any kept
                # family's accent (the mapper picks it); `else` when no family is kept. Never dim.
                qt = (qfb or {}).get('tier', 'default')
                if qt == 'quiet' and (qfb or {}).get('family') == 'any_kept':
                    if kept:
                        st['quiet_borrow'] = True
                    else:
                        st['tier'] = qfb.get('else', 'default')
                else:
                    st['tier'] = qt
            elif 'tier' in fb:
                st['tier'] = fb['tier']
            if 'slant' in fb:
                st['slant'] = fb['slant']
            st.pop('variant', None)
        st['family'] = fam
        tier = st.get('tier')
        st['bold'] = bool(st.get('weight') == 'bold' or (tier in tiers and tiers[tier].get('weight') == 'bold'))
        if st.get('bold_if') == 'top-level':
            # draft 3: `bold_if: top-level` = module-level bindings bold, locals plain (same split as `scope: top-level`)
            st['bold'] = True
            st['scope'] = 'top-level'
        out[rid] = st
    return out


@lru_cache(maxsize=None)
def weights():
    w = _y('weights.yaml')
    pairs = {}
    for a, b, v in w['pairs']:
        pairs[frozenset((a, b))] = v
    return w.get('default_pair', 1), w.get('beacon', {}), pairs


def pair_weight(a, b):
    d, _, pairs = weights()
    return pairs.get(frozenset((a, b)), d)


def must_differ_pairs(s):
    """[(a, b, w)]: roles in different families (null = its own group) at full capacity with w>0,
    plus any explicitly weighted pair (w>0) inside one family."""
    st = effective_styles(s)
    _, _, pairs = weights()
    out = []
    ids = [r for r in role_ids() if st.get(r) is not None]
    for a, b in combinations(ids, 2):
        w = pair_weight(a, b)
        if w <= 0:
            continue
        if st[a]['family'] != st[b]['family'] or frozenset((a, b)) in pairs:
            out.append((a, b, w))
    return out


def light_class(st, v2=False):
    if st['tier'] == 'faded':
        return 'faded'
    if v2:
        return 'dim' if st['tier'] == 'dim' else 'normal'
    if st.get('variant') == 'lightness':
        return 'variant'
    if st['tier'] == 'popout':
        return 'popout'
    return 'normal'


def chroma_class(st, v2=False):
    if not v2:
        return 'low' if st.get('variant') == 'chroma-low' else 'full'
    if st.get('quiet_borrow') and st['tier'] == 'quiet':
        return 'quiet'
    if st['family'] is None:
        return 'none'
    return 'quiet' if st['tier'] == 'quiet' else 'loud'


def channels_between(sa, sb, v2=False):
    """Channels that (by pattern design, palette-independent) distinguish two styles.
    v1: lightness counts only for designed differences: faded vs not, lightness variant vs base,
    popout (Lc 60 target) vs others. default (Lc>=60) vs salient (Lc>=45) is NOT counted,
    because both targets are minima and accents commonly sit at the fg's Lc.
    v2: lightness = faded / dim vs the rest (dim is >= 10 Lc below fg by construction);
    chroma = none / quiet / loud class (quiet is D1-distinct from fg and dim by construction).
    Loss of hue (H11 ablation) also removes chroma."""
    ch = []
    if sa['family'] != sb['family']:
        ch.append('hue')
    if light_class(sa, v2) != light_class(sb, v2):
        ch.append('lightness')
    if v2:
        if chroma_class(sa, True) != chroma_class(sb, True):
            ch.append('chroma')
    elif sa['family'] == sb['family'] and chroma_class(sa) != chroma_class(sb):
        ch.append('chroma')
    if sa['bold'] != sb['bold']:
        ch.append('weight')
    if (sa.get('slant') == 'italic') != (sb.get('slant') == 'italic'):
        ch.append('slant')
    if bool(sa.get('strike')) != bool(sb.get('strike')):
        ch.append('strike')
    return ch


# ------------------------------------------------------------------ corpus statistics

def _read_csv(path):
    with open(path, newline='') as f:
        return list(csv.DictReader(f))


@lru_cache(maxsize=None)
def ink_shares():
    """role -> pooled char share (lang=ALL row of out/role_stats.csv). Returns (dict, source)."""
    p = os.path.join(OUT, 'role_stats.csv')
    if os.path.exists(p):
        rows = _read_csv(p)
        cols = rows[0].keys()
        langc = next((c for c in ('lang', 'language') if c in cols), None)
        sharec = next((c for c in ('char_share', 'ink_share', 'share') if c in cols), None)
        rolec = 'role' if 'role' in cols else None
        if langc and sharec and rolec:
            d = {}
            for r in rows:
                if r[langc] in ('ALL', 'all', 'pooled') and r.get('scope', 'all') in ('all', '', 'ALL', None):
                    d[r[rolec]] = d.get(r[rolec], 0.0) + float(r[sharec] or 0)
            if d:
                return d, 'out/role_stats.csv (lang=ALL)'
    return _ink_from_captures(), 'out/ink_share.csv via roles.yaml selectors (FALLBACK)'


def _ink_from_captures():
    rows = [r for r in _read_csv(os.path.join(OUT, 'ink_share.csv')) if r['lang'] == 'pooled' and r['level'] == 'full']
    cap2role = {}
    for r in roles():
        for c in r.get('captures', []):
            cap2role.setdefault(c.lstrip('@'), r['id'])   # first listing wins
    cap2role['constant'] = 'constant.use'
    d = {}
    for r in rows:
        cap = r['capture']
        k = cap
        while k and k not in cap2role and k != 'default':
            k = k.rsplit('.', 1)[0] if '.' in k else ''
        role = 'default' if cap == 'default' else cap2role.get(k, 'default')
        d[role] = d.get(role, 0.0) + float(r['char_share'])
    return d


@lru_cache(maxsize=None)
def adjacency():
    """{frozenset(a,b): adjacency} pooled over languages. Returns (dict, source)."""
    p = os.path.join(OUT, 'adjacency.csv')
    if os.path.exists(p):
        rows = _read_csv(p)
        cols = list(rows[0].keys())
        ac = next((c for c in ('role_a', 'a', 'role1', 'r1', 'left') if c in cols), None)
        bc = next((c for c in ('role_b', 'b', 'role2', 'r2', 'right') if c in cols), None)
        vc = next((c for c in ('adjacent_skip_punct', 'adjacency', 'adj', 'weight', 'rate', 'per_line', 'share', 'count') if c in cols), None)
        langc = next((c for c in ('lang', 'language') if c in cols), None)
        if ac and bc and vc:
            d = {}
            for r in rows:
                if langc and r[langc] not in ('ALL', 'all', 'pooled'):
                    continue
                if r[ac] == r[bc]:
                    continue
                k = frozenset((r[ac], r[bc]))
                d[k] = d.get(k, 0.0) + float(r[vc] or 0)
            if d:
                return d, f'out/adjacency.csv ({vc})'
    ink, _ = ink_shares()
    d = {}
    for a, b in combinations(role_ids(), 2):
        d[frozenset((a, b))] = ink.get(a, 0) * ink.get(b, 0)
    return d, 'FALLBACK: product of ink shares (adjacency.csv missing)'


def adj(a, b):
    return adjacency()[0].get(frozenset((a, b)), 0.0)


@lru_cache(maxsize=None)
def separability():
    """{frozenset(a,b): lexical separability in [0,1]} and a source note.
    Pairs in out/recoverability_pairs.csv (lang=ALL): chance-corrected balanced accuracy, 2·bal − 1
    (binary LR, chance = 0.5). Other pairs: from the multi-class confusion matrix
    out/recoverability_confusion.csv (lang=ALL, frac_of_true): sep = 1 − (conf(a→b) + conf(b→a)) / 2."""
    sep = {}
    p = os.path.join(OUT, 'recoverability_pairs.csv')
    if os.path.exists(p):
        for r in _read_csv(p):
            if r.get('lang') == 'ALL' and r.get('balanced_accuracy'):
                sep[frozenset((r['role_a'], r['role_b']))] = max(0.0, 2 * float(r['balanced_accuracy']) - 1)
    conf = {}
    p2 = os.path.join(OUT, 'recoverability_confusion.csv')
    if os.path.exists(p2):
        for r in _read_csv(p2):
            if r['lang'] == 'ALL' and r['true'] != r['pred']:
                conf[(r['true'], r['pred'])] = float(r['frac_of_true'] or 0)
    ok = bool(sep or conf)
    return sep, conf, ok


def sep(a, b):
    s, conf, ok = separability()
    k = frozenset((a, b))
    if k in s:
        return s[k]
    if not ok:
        return 0.0
    return 1.0 - (conf.get((a, b), 0.0) + conf.get((b, a), 0.0)) / 2


def pair_cost(a, b, discounted=False):
    """C6 contribution of a confused must-differ pair: adjacency × w (× (1 − separability))."""
    c = adj(a, b) * pair_weight(a, b)
    return c * (1 - sep(a, b)) if discounted else c


# ------------------------------------------------------------------ beacon loss (spec fix (b))

def role_ink_key(rid, st, ink):
    """Ink-share key for a role: top-level-scoped roles use the `.top` share only."""
    if st and st.get('scope') == 'top-level' and f'{rid}.top' in ink:
        return f'{rid}.top'
    return rid


def _designed(st):
    return st is not None and (st.get('family') is not None or st.get('bold') or (st.get('tier') or 'default') != 'default')


def role_loss(full, cur):
    """Beacon loss of one role: 1 if a role designed to stand out falls to plain default (no bold);
    0.5 if it loses its hue (or its quiet tint) but keeps bold or a dim/quiet/faded distinctness;
    0 if it keeps its designed treatment (or was never designed to stand out)."""
    if not _designed(full):
        return 0.0
    same = (cur.get('family') == full.get('family') and bool(cur.get('bold')) == bool(full.get('bold'))
            and (cur.get('tier') or 'default') == (full.get('tier') or 'default'))
    if same or (cur.get('family') is not None and full.get('family') is not None):
        return 0.0        # kept, or merged into another hue family (C6 pairs price the merge)
    if not cur.get('bold') and (cur.get('tier') or 'default') == 'default' and cur.get('family') is None:
        return 1.0
    return 0.5


def beacon_loss(s, cur_styles):
    """Σ_roles beacon(role) · ink(role) · loss(role) against the set's full-capacity design."""
    ink, _ = ink_shares()
    _, beacon, _ = weights()
    full = effective_styles(s)
    tot = 0.0
    for rid in role_ids():
        f = full.get(rid)
        c = cur_styles.get(rid)
        if f is None or c is None:
            continue
        b = beacon.get(rid, 0)
        if not b:
            continue
        tot += b * ink.get(role_ink_key(rid, f, ink), 0.0) * role_loss(f, c)
    return tot


@lru_cache(maxsize=None)
def beacon_lambda():
    """λ that puts beacon loss on the confusion-cost scale (spec fix (b)): on the draft-2 landmark set,
    λ = [C6(no hue families) − C6(all kept)] / [BL(no hue families) − BL(all kept)], i.e. dropping every
    family costs as much in beacon loss as in pair confusion. Static channel model. Returns
    {'raw': λ, 'disc': λ} for the raw and recoverability-discounted C6."""
    s = load_set('landmark')
    out = {}
    v2 = is_v2(s)
    md = must_differ_pairs(s)
    st_full = effective_styles(s)
    st_none = effective_styles(s, set())
    for key, disc in (('raw', False), ('disc', True)):
        c_full = sum(pair_cost(a, b, disc) for a, b, w in md if not channels_between(st_full[a], st_full[b], v2))
        c_none = sum(pair_cost(a, b, disc) for a, b, w in md if not channels_between(st_none[a], st_none[b], v2))
        bl = beacon_loss(s, st_none) - beacon_loss(s, st_full)
        out[key] = (c_none - c_full) / bl if bl > 0 else 0.0
    return out


# ------------------------------------------------------------------ separable cost (draft 2.1)

@lru_cache(maxsize=None)
def unseparated_pairs():
    """Role pairs (frozenset) that NO pattern set separates: in every set in SETS the two roles end up with the
    same family, tier, weight, slant and strike at full capacity (no static channel). Their confusion cost is a
    fixed baseline; 'separable cost' excludes them so differences between sets are visible."""
    ids = role_ids()
    sets = [(load_set(n), is_v2(load_set(n))) for n in SETS]
    sts = [effective_styles(s) for s, _ in sets]
    out = set()
    for a, b in combinations(ids, 2):
        if all(st.get(a) is not None and st.get(b) is not None and not channels_between(st[a], st[b], v2)
               for st, (_, v2) in zip(sts, sets)):
            out.add(frozenset((a, b)))
    return out
