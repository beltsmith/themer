"""Score every corpus palette against every pattern set and assignment mode (C1, C2, C6-C8, C10, H9, H10, H12).

    uv run --with coloraide --with pyyaml --with numpy --with scipy python harness/score_palettes.py [--limit N]

Writes out/palette_scores.csv (one row per palette × set × mode × reserve_diag) and out/palette_scores.md.
Sets: mapper_common.SETS (draft 2 landmark/hybrid, label, draft 1 landmark_v1/hybrid_v1).
Everything palette-specific is computed by harness/mapper.py (see its docstring for the algorithm).
"""
from __future__ import annotations

import csv
import os
import statistics as st
import sys
from collections import defaultdict
from multiprocessing import Pool

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import colour as K  # noqa: E402
import mapper as MP  # noqa: E402
import mapper_common as M  # noqa: E402

MODES = ['A', 'B']
HEAD = 'B'      # draft 2.1: mode B (habit-based hue assignment) is the headline mode; A is reported alongside
SPOT = ['base16/tomorrow-night', 'base16/solarized-light', 'ansi16/Builtin Tango Dark']
ALL_FAMS = ['definition', 'value', 'prose', 'exit', 'meta', 'oddball', 'callable', 'type', 'keyword', 'field']
S1_PAIRS = {1: ['faded<default', 'default<salient', 'salient<strong', 'strong<popout'],
            2: ['faded<dim', 'dim<default', 'default<quiet', 'quiet<loud', 'loud<strong', 'strong<popout']}   # old S1 breakdown (S1_sal)
QUIET_FAMS = ['value', 'definition']


def habit_fit(theme):
    fams = {f: v for f, v in theme['families'].items()}
    if not fams:
        return None
    return sum(MP.HABITS.get(f, {}).get(v['hue_name'], 0) for f, v in fams.items()) / len(fams)


def caps_for(p, reserve, v2):
    kw = {'min_c': MP.LOUD_C, 'strict': True} if v2 else {'min_c': K.NAME_C, 'strict': False}
    cands = MP.candidates(p, reserve_diag=reserve, **kw)
    caps = MP.capacity(p, cands=cands, strict=kw['strict'])
    caps['reliable'] = MP.capacity(p, kinds=('normal',), cands=cands, level='reliable', strict=kw['strict'])['normal']
    caps['n_cands'] = len(cands)
    # diagnostic: deutan capacity of the same pool when D2 may also be met by |ΔL_ok| >= .12 (draft-1 D2)
    caps['deutan_dl'] = MP.capacity(p, kinds=('deutan',), cands=cands, strict=False)['deutan'] if v2 else caps['deutan']
    return caps


def score_one(p):
    rows = []
    themes = {}
    raw = MP.candidates(p, max_fid=0.0, reserve_diag=False)
    cap_raw = MP.capacity(p, kinds=('normal',), cands=raw)['normal']   # near-mono flag: palette as given (v1 accent def)
    capc = {(r, v): caps_for(p, r, v) for r in (True, False) for v in (False, True)}
    jobs = [(False, sn, mo) for sn in M.SETS for mo in MODES] + [(True, sn, HEAD) for sn in M.SETS]   # headline: reserve_diag OFF
    for reserve, sn, mo in jobs:
        s = M.load_set(sn)
        v2 = M.is_v2(s)
        caps = capc[(reserve, v2)]
        th = MP.map_palette(p, sn, mo, reserve_diag=reserve)
        ev = MP.evaluate(th)
        fids = [v['fidelity'] for v in th['families'].values()]
        r = {
            'id': p['id'], 'pfamily': p['family'], 'variant': p['variant'], 'set': sn, 'version': 2 if v2 else 1, 'mode': mo,
            'reserve_diag': int(reserve),
            'n_cands': caps['n_cands'], 'cap_raw': cap_raw, 'cap': caps['normal'], 'cap_reliable': caps['reliable'],
            'cap_deutan': caps['deutan'], 'cap_deutan_dl': caps['deutan_dl'], 'cap_protan': caps['protan'], 'cap_tritan': caps['tritan'],
            'near_mono': int(cap_raw <= 1), 'required': th['hue_families_required'],
            'kept_n': len(th['families_kept']), 'kept': ' '.join(th['families_kept']),
            'dropped': ' '.join(th['families_dropped']),
            'fid_mean': round(sum(fids) / len(fids), 4) if fids else '', 'fid_max': max(fids) if fids else '',
            'var_fid_max': th['variant_fidelity_max'],
            'L1': ev['L1'], 'L2': ev['L2'], 'L3': ev['L3'], 'L4': ev['L4'], 'L123': ev['L123'], 'fg_lc': ev['fg_lc'],
            'S1': int(ev['S1']), 'S1_v1': int(ev['S1_v1']), 'S1_sal': int(ev['S1_sal']),
            'S1a': int(ev['S1a']), 'S1b': '' if ev['S1b'] is None else int(ev['S1b']),
            'confusion_normal_sep': round(ev['confusion_normal_sep'], 6), 'confusion_deutan_sep': round(ev['confusion_deutan_sep'], 6),
            'confusion_normal_disc_sep': round(ev['confusion_normal_disc_sep'], 7), 'confusion_deutan_disc_sep': round(ev['confusion_deutan_disc_sep'], 7),
            'C6_disc_sep': round(ev['C6_disc_sep'], 7),
            'need_sal_rho': '' if ev['need_sal_rho'] is None else ev['need_sal_rho'],
            'confusion_normal': round(ev['confusion_normal'], 6), 'confusion_deutan': round(ev['confusion_deutan'], 6),
            'confusion_normal_disc': round(ev['confusion_normal_disc'], 7), 'confusion_deutan_disc': round(ev['confusion_deutan_disc'], 7),
            'confused_pairs_normal': ev['confused_pairs_normal'], 'confused_pairs_deutan': ev['confused_pairs_deutan'],
            'beacon_loss': round(ev['beacon_loss'], 6),
            'C6_disc': round(ev['C6_disc'], 7), 'C6_raw': round(ev['C6_raw'], 6), 'C6_disc_deutan': round(ev['C6_disc_deutan'], 7),
            'coloured_ink': round(ev['coloured_ink'], 4),
            'ink_loud': round(ev['ink_split']['loud'], 4), 'ink_quiet': round(ev['ink_split']['quiet'], 4),
            'ink_dim': round(ev['ink_split']['dim'], 4), 'ink_faded': round(ev['ink_split']['faded'], 4),
            'sal_ink': round(ev['sal_weighted_ink'], 4), 'budget_tier': round(ev['salience_budget_tier'], 4),
            'C1_rho': round(ev['C1_rho'], 3), 'C1_rho_tier': round(ev['C1_rho_tier'], 3), 'C1_rho_v1model': round(ev['C1_rho_v1model'], 3),
            'beacon_coverage': round(ev['beacon_coverage'], 3),
            'habit_fit': '' if habit_fit(th) is None else round(habit_fit(th), 3),
            'assign': ' '.join(f"{f}:{v['hue_name']}" for f, v in th['families'].items()),
        }
        for pr in S1_PAIRS[2 if v2 else 1]:
            r[f'S1_{pr}'] = '' if pr not in ev['S1_pairs'] else int(ev['S1_pairs'][pr])
        for f in ALL_FAMS:
            r[f'ink_{f}'] = round(ev['coloured_ink_by_family'].get(f, 0.0), 4)
        if v2:
            q = th.get('quiet', {})
            for f in QUIET_FAMS:
                r[f'quiet_{f}'] = '' if f not in q else int(q[f]['ok'])
                r[f'quiet_C_{f}'] = '' if f not in q or not q[f]['ok'] else q[f]['C']
            ti = th['tiers']
            r['dim_ok'] = int(ti['dim_floor_ok'] and ti['dim_below_fg_ok'])
            r['fg_limited'] = int(ti['fg_limited'])
            r['strings_quiet'] = th['strings_quiet']
            r['quiet_any_fail'] = int(any(not v['ok'] for v in q.values()))
            r['quiet_borrowed_from'] = (th['quiet_borrow'] or {}).get('from', '')
            r['dim_lc'] = ti['dim_lc']
            r['faded_ok'] = int(ti['faded_distinct_ok'])
            r['popout_accent'] = int(th['popout'] is not None)
        rows.append(r)
        if p['id'] in SPOT and not reserve:
            th['checks'] = ev
            themes[(sn, mo)] = th
    return rows, (p['id'], themes) if themes else None


# ------------------------------------------------------------------ report helpers

def s1a(rs):
    return pct(sum(r['S1a'] for r in rs), len(rs))


def s1b(rs):
    xs = [r['S1b'] for r in rs if r['S1b'] != '']
    return f'{pct(sum(xs), len(xs))} (n={len(xs)})' if xs else 'n/a'


def pct(x, n):
    return f'{100 * x / n:.0f}%' if n else '–'


def med(xs):
    xs = [x for x in xs if x != '' and x is not None]
    return st.median(xs) if xs else float('nan')


def mean(xs):
    xs = [x for x in xs if x != '' and x is not None]
    return sum(xs) / len(xs) if xs else float('nan')


def groups(rows):
    g = defaultdict(list)
    for r in rows:
        g[(r['pfamily'], r['variant'])].append(r)
        g[('all', 'all')].append(r)
    return g


GROUP_ORDER = [('base16', 'dark'), ('base16', 'light'), ('base24', 'dark'), ('base24', 'light'),
               ('ansi16', 'dark'), ('ansi16', 'light'), ('all', 'all')]


def cap_table(rows, title):
    L = [title, '']
    L.append('| group | n | near-mono | median cap_raw | median cap | median cap_reliable | deutan | protan | tritan | cap ≥ 3 | cap ≥ 4 | cap ≥ 5 | cap ≥ 6 | deutan ≥ 3 | deutan ≥ 4 | deutan ≥ 5 |')
    L.append('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|')
    g = groups(rows)
    for k in GROUP_ORDER:
        rs = g.get(k, [])
        if not rs:
            continue
        ch = [r for r in rs if not r['near_mono']]
        n = len(ch)
        L.append(f"| {k[0]} {k[1]} | {len(rs)} | {len(rs) - n} | {med([r['cap_raw'] for r in rs])} | {med([r['cap'] for r in rs])} "
                 f"| {med([r['cap_reliable'] for r in rs])} | {med([r['cap_deutan'] for r in rs])} | {med([r['cap_protan'] for r in rs])} "
                 f"| {med([r['cap_tritan'] for r in rs])} "
                 + ' '.join(f"| {pct(sum(r['cap'] >= c for r in ch), n)}" for c in (3, 4, 5, 6))
                 + ' ' + ' '.join(f"| {pct(sum(r['cap_deutan'] >= c for r in ch), n)}" for c in (3, 4, 5)) + ' |')
    L.append('\n(Percentages exclude near-monochrome palettes.)\n')
    return L


def sensitivity(off, on):
    L = ['## Sensitivity: diagnostic hue reservation on (`reserve_diag=True`)\n',
         'Headline numbers (reserve off) let syntax use every accent, red included. Here the error colour (base08 / ANSI red) and every accent not D2 from it are '
         'reserved for the diagnostic layer (P:I9; for draft 2 sets D2 is name-only, so the whole error hue name is reserved). The same palettes are '
         'mapped with all accents available (headline mode only). Chromatic palettes.\n']
    L.append(f'| set (mode {HEAD}) | reserve | median cap | required | % cap ≥ required | % deutan cap ≥ required | kept (median) | coloured ink | sal.-weighted ink | disc. normal | beacon loss | C6 total (disc.) | C1 ρ |')
    L.append('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|')
    for sn in M.SETS:
        for nm, src in (('off', off), ('on', on)):
            rs = [r for r in src if r['set'] == sn and r['mode'] == HEAD and not r['near_mono']]
            n = len(rs)
            req = rs[0]['required']
            L.append(f"| {sn} | {nm} | {med([r['cap'] for r in rs])} | {req} | {pct(sum(r['cap'] >= req for r in rs), n)} "
                     f"| {pct(sum(r['cap_deutan'] >= req for r in rs), n)} | {med([r['kept_n'] for r in rs])} "
                     f"| {med([r['coloured_ink'] for r in rs]):.3f} | {med([r['sal_ink'] for r in rs]):.3f} "
                     f"| {mean([r['confusion_normal_disc'] for r in rs]):.5f} | {mean([r['beacon_loss'] for r in rs]):.4f} "
                     f"| {mean([r['C6_disc'] for r in rs]):.5f} | {med([r['C1_rho'] for r in rs]):.2f} |")
    L.append('')
    return L


def report(rows_all, spots, ink_src, adj_src):
    rows = [r for r in rows_all if not r['reserve_diag']]
    rows_on = [r for r in rows_all if r['reserve_diag']]
    lam = M.beacon_lambda()
    L = ['# Palette scores (draft 2.1)', '',
         '**All headline numbers use `reserve_diag=False`** (red may be used for syntax; the hue assignment is the theme creator\'s business). '
         'See the sensitivity section for `reserve_diag=True` (error colour and accents not D2 from it kept out of syntax, P:I9). '
         f'**Headline mode: {HEAD}** (habit-based hue assignment); mode A (salience-driven) is reported alongside.', '',
         'Generated by `harness/score_palettes.py` (algorithm: `harness/mapper.py`, metrics: `harness/colour.py`). '
         f'Sets: {", ".join(M.SETS)} (landmark and hybrid = draft 2; *_v1 = draft 1, mapped exactly as before; label unchanged).',
         f'One row per palette × set × mode × reserve in `out/palette_scores.csv`. Ink shares: {ink_src}. Adjacency: {adj_src}.', '',
         '**Definitions used here.**',
         '- *capacity* (draft 1 sets) = largest set of accents (OKLCH C ≥ 0.06; L-shifted toward |Lc| 45 with ΔE_OK ≤ 0.05; must pass L2 floor |Lc| ≥ 35)'
         ' that are pairwise D2 (D1 at p = .5 and (hue name differs or |ΔL_ok| ≥ .12)) and each D2 from fg. '
         '**Draft 2 sets**: loud accents need C ≥ 0.08 after derivation, and D2 between hue families needs a different hue *name* '
         '(spec fix (a)) under normal vision; **draft 2.1: under CVD simulation two loud families (and a family vs fg) are distinct if D1 passes at the reliable level p = .8, lightness differences included, no name rule**; only loud/strong use counts against capacity. `cap_raw` = draft-1 definition, no derivation, no reservation '
         '(near-monochrome flag); `cap_reliable` = D1 at p = .8. CVD capacities simulate fg, bg and accents (Machado deutan/protan, Brettel tritan).',
         '- *near-monochrome* = cap_raw ≤ 1. Excluded from H9 denominators.',
         '- *L1–L3 tier* = worst of L1 (fg; WCAG < 4.5 caps it at floor), L2 (every hue-bearing role incl. quiet, bold lowers thresholds by 10), '
         'L3 (comment, comment.doc; must also be ≥ 10 Lc below fg or it is capped at floor).',
         f'- *salience* (spec fix (d), `colour.salience_v2`) = a·max(0, |Lc|−|Lc_fg|)/100 + b·C/0.15 + c·bold − d·max(0, |Lc_fg|−|Lc|)/100 with '
         f'a = {K.SAL_A}, b = {K.SAL_B}, c = {K.SAL_C}, d = {K.SAL_D} (1.0 = 100 Lc). Chosen so the declared order faded < dim < default < quiet < loud '
         f'< strong < popout holds with margin {K.S1_MARGIN} for the ideal palette documented in colour.py (fg Lc 60, faded 30, dim 45, quiet at fg '
         'lightness with C .055, loud at its Lc target 45 with the corpus-median accent C .128). b is the binding weight: b ≥ .462 is needed for a '
         'loud accent at Lc 45 to outrank a quiet tint at fg lightness.',
         f'- *S1* (draft 2.1) = two orderings only. **S1a** lightness: faded < dim < default by |Lc| (default = fg; tiers in use). **S1b** chroma: quiet < loud by OKLCH C '
         f'with margin ≥ {MP.S1B_MARGIN} (max C of quiet roles + margin ≤ min C of loud/strong hue roles; n/a, and not counted, when no quiet tint is drawn or the set has no quiet tier). '
         f'S1 = S1a and S1b. *S1 sal.* = the draft-2 all-adjacent-tiers salience check (margin {K.S1_MARGIN}), kept for comparison.',
         '- *confusion* (C6 pair term) = Σ adjacency × w over must-differ pairs whose rendered colours are not distinct and that differ in no style '
         'channel. Draft 1: D2 for different families, D1 floor for designed same-family pairs. Draft 2: name-D2 when the families differ and at least one '
         'role is loud/strong/popout; D1 floor for every designed tier distinction (quiet vs fg, dim vs default, quiet vs loud, quiet vs quiet). '
         '*disc.* = × (1 − lexical separability) (out/recoverability_pairs.csv, rerun after the docstring → comment.doc move). '
         f'*separable cost* (draft 2.1) = the same sums excluding the {len(M.unseparated_pairs())} role pairs that no set separates (both roles have the same family, tier, weight and slant in every set at full capacity), '
         'so the gaps between sets are visible; the excluded pairs are a fixed baseline.',
         f'- *beacon loss* (spec fix (b)) = Σ_roles beacon(role) · ink(role) · loss(role); loss = 1 if a role designed to stand out falls to plain '
         f'default ink without bold, 0.5 if it keeps bold or a quiet/dim/faded distinctness, else 0. *C6 total* = confusion + λ · beacon loss with '
         f'λ_disc = {lam["disc"]:.5f} (λ_raw = {lam["raw"]:.4f}): λ makes dropping every hue family of draft-2 landmark cost as much in beacon loss as '
         'in pair confusion (static model, `mapper_common.beacon_lambda`). Sensitivity at λ/3 and 3λ below.',
         '- *coloured ink* (C2, draft 1 definition) = ink share of roles drawn in a family colour with C ≥ 0.04. *loud / quiet / dim ink* = ink of hued '
         'roles at salient/loud/strong/popout, hued roles at quiet (only when the quiet colour exists), and roles at dim.',
         '- *salience-weighted ink* (C2 headline, draft 2) = Σ ink × salience⁺ (salience model above) = the salience budget. '
         '*budget (tier)* = the draft-1 budget Σ ink × (tier rank − default rank)⁺ using each set\'s own tier list.',
         '- *C1 ρ* = Spearman(salience model, ink share) over roles (variable.def split into .top/.local by its scope). `tier` = applied tier rank; '
         '`v1 model` = draft-1 pop-out salience |Lc| + 15·bold + 150·C.',
         '- *beacon coverage* = share of `weights.yaml` beacon value on roles drawn differently from plain default ink (hue, bold or a non-default tier; '
         'draft 1 counted hue or bold only, so faded/italic comments now count).',
         '']
    n_pal = len({r['id'] for r in rows})
    lm = [r for r in rows if r['set'] == 'landmark' and r['mode'] == HEAD]
    lm1 = [r for r in rows if r['set'] == 'landmark_v1' and r['mode'] == HEAD]
    nm = sum(r['near_mono'] for r in lm)
    L.append(f'{n_pal} palettes; {nm} near-monochrome (cap_raw ≤ 1).\n')

    L += cap_table(lm, '## Capacity by palette family: draft 2/2.1 (loud accents, C ≥ 0.08, name-D2 normal; D1 reliable under CVD)')
    L += cap_table(lm1, '## Capacity by palette family: draft 1 definition (C ≥ 0.06, D2 with ΔL)')

    # ---------------- H9 revised
    ch = [r for r in lm if not r['near_mono']]
    n = len(ch)
    req = ch[0]['required']
    L.append('## H9 (draft 2.1): can palettes carry draft-2 landmark?\n')
    L.append(f'Draft-2 landmark has {req} loud families (value, definition, exit, meta). H9: ≥ 80% of non-monochrome palettes keep all '
             f'{req} loud families under normal vision, and ≥ 60% keep ≥ {req - 1} under deutan and under protan. Capacity: normal = name-D2 clique; '
             f'CVD = clique under D1 at the reliable level (p = .8, lightness differences count, no name rule). Denominator: {n} chromatic palettes.\n')
    L.append('| need | normal (name-D2, D1 floor) | normal (D1 reliable) | deutan (D1 rel.) | protan (D1 rel.) | tritan (D1 rel.) | deutan, draft-1 D2 | threshold |')
    L.append('|---|---:|---:|---:|---:|---:|---:|---|')
    for k in (req, req - 1, req - 2):
        L.append(f"| ≥ {k} | {pct(sum(r['cap'] >= k for r in ch), n)} | {pct(sum(r['cap_reliable'] >= k for r in ch), n)} "
                 f"| {pct(sum(r['cap_deutan'] >= k for r in ch), n)} | {pct(sum(r['cap_protan'] >= k for r in ch), n)} "
                 f"| {pct(sum(r['cap_tritan'] >= k for r in ch), n)} | {pct(sum(r['cap_deutan_dl'] >= k for r in ch), n)} "
                 f"| {'≥ 80% normal' if k == req else ('≥ 60% deutan/protan' if k == req - 1 else '')} |")
    full = sum(r['cap'] >= req for r in ch)
    d3 = sum(r['cap_deutan'] >= req - 1 for r in ch)
    p3 = sum(r['cap_protan'] >= req - 1 for r in ch)
    v = 'holds' if full / n >= .8 and d3 / n >= .6 and p3 / n >= .6 else 'fails'
    L.append(f'\n**H9 {v}**: normal {pct(full, n)} keep all {req} (target 80%); deutan {pct(d3, n)} keep ≥ {req - 1} (target 60%); '
             f'protan {pct(p3, n)} keep ≥ {req - 1}. Under CVD, all {req}: deutan {pct(sum(r["cap_deutan"] >= req for r in ch), n)}, '
             f'protan {pct(sum(r["cap_protan"] >= req for r in ch), n)}.')
    ch1 = [r for r in lm1 if not r['near_mono']]
    n1 = len(ch1)
    L.append(f"For comparison, draft-1 H9 (landmark_v1, need 6 / 5 hue families, draft-1 D2): normal {pct(sum(r['cap'] >= 6 for r in ch1), n1)} / "
             f"{pct(sum(r['cap'] >= 5 for r in ch1), n1)}, deutan {pct(sum(r['cap_deutan'] >= 6 for r in ch1), n1)} / "
             f"{pct(sum(r['cap_deutan'] >= 5 for r in ch1), n1)}.\n")
    kc = defaultdict(int)
    for r in lm:
        kc[r['kept_n']] += 1
    L.append(f'Loud families kept (landmark, mode {HEAD}, all palettes): ' + ', '.join(f'{k}: {v}' for k, v in sorted(kc.items())) + '.\n')

    by = defaultdict(list)
    for r in rows:
        by[(r['set'], r['mode'])].append(r)

    # ---------------- summary tables
    L.append('## Summary by set and mode (all palettes)\n')
    L.append('### Capacity, legibility, salience order\n')
    L.append('| set | mode | hue families required | median cap available | % cap ≥ required | % deutan cap ≥ required | kept (median) | L1–L3 ≥ default | L1–L3 floor | L1–L3 fail | S1a (lightness) | S1b (chroma) | S1 both | need–salience ρ | habit fit |')
    L.append('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|')
    for sn in M.SETS:
        for mo in MODES:
            rs = by[(sn, mo)]
            ch = [r for r in rs if not r['near_mono']]
            n, nc = len(rs), len(ch)
            req = rs[0]['required']
            L.append(f"| {sn} | {mo} | {req} | {med([r['cap'] for r in rs])} | {pct(sum(r['cap'] >= req for r in ch), nc)} "
                     f"| {pct(sum(r['cap_deutan'] >= req for r in ch), nc)} | {med([r['kept_n'] for r in rs])} "
                     f"| {pct(sum(r['L123'] in ('strict', 'default') for r in rs), n)} | {pct(sum(r['L123'] == 'floor' for r in rs), n)} "
                     f"| {pct(sum(r['L123'] == 'fail' for r in rs), n)} | {s1a(rs)} | {s1b(rs)} | {pct(sum(r['S1'] for r in rs), n)} "
                     f"| {med([r['need_sal_rho'] for r in rs]):.2f} | {mean([r['habit_fit'] for r in rs]):.2f} |")
    L.append('\n(% cap ≥ required: chromatic palettes only.)\n')
    L.append('### Ink, salience budget, C1, confusion\n')
    L.append('| set | mode | coloured ink (C2 v1) | ≤ 35% | loud ink | quiet ink | dim ink | sal.-weighted ink (C2 headline) | budget (tier) | C1 ρ | ρ ≤ −0.5 | C1 ρ tier | C1 ρ v1-model | confusion normal | confusion deutan | disc. normal | disc. deutan | separable raw | separable disc. | separable disc. deutan | beacon loss | C6 total disc. | C6 total disc. separable | C6 total disc. deutan | beacon cov. |')
    L.append('|---|---|' + '---:|' * 23)
    for sn in M.SETS:
        for mo in MODES:
            rs = by[(sn, mo)]
            n = len(rs)
            L.append(f"| {sn} | {mo} | {med([r['coloured_ink'] for r in rs]):.3f} | {pct(sum(r['coloured_ink'] <= .35 for r in rs), n)} "
                     f"| {med([r['ink_loud'] for r in rs]):.3f} | {med([r['ink_quiet'] for r in rs]):.3f} | {med([r['ink_dim'] for r in rs]):.3f} "
                     f"| {med([r['sal_ink'] for r in rs]):.3f} | {med([r['budget_tier'] for r in rs]):.3f} "
                     f"| {med([r['C1_rho'] for r in rs]):.2f} | {pct(sum(r['C1_rho'] <= -.5 for r in rs), n)} | {med([r['C1_rho_tier'] for r in rs]):.2f} "
                     f"| {med([r['C1_rho_v1model'] for r in rs]):.2f} "
                     f"| {mean([r['confusion_normal'] for r in rs]):.4f} | {mean([r['confusion_deutan'] for r in rs]):.4f} "
                     f"| {mean([r['confusion_normal_disc'] for r in rs]):.5f} | {mean([r['confusion_deutan_disc'] for r in rs]):.5f} "
                     f"| {mean([r['confusion_normal_sep'] for r in rs]):.4f} | {mean([r['confusion_normal_disc_sep'] for r in rs]):.5f} | {mean([r['confusion_deutan_disc_sep'] for r in rs]):.5f} "
                     f"| {mean([r['beacon_loss'] for r in rs]):.4f} | {mean([r['C6_disc'] for r in rs]):.5f} | {mean([r['C6_disc_sep'] for r in rs]):.5f} | {mean([r['C6_disc_deutan'] for r in rs]):.5f} "
                     f"| {med([r['beacon_coverage'] for r in rs]):.2f} |")
    L.append('')

    # ---------------- S1
    L.append('### S1 (draft 2.1): lightness order and chroma order\n')
    L.append('S1a = faded < dim < default by |Lc|. S1b = quiet < loud by OKLCH C, margin ≥ 0.03 (draft-2 sets only; n = palettes where a quiet tint and a loud accent both exist). '
             'S1 sal. = the draft-2 all-adjacent-tiers salience check.\n')
    L.append('| set | mode | S1a | S1b | S1 both | S1 sal. (old) |')
    L.append('|---|---|---:|---:|---:|---:|')
    for sn in M.SETS:
        for mo in MODES:
            rs = by[(sn, mo)]
            L.append(f"| {sn} | {mo} | {s1a(rs)} | {s1b(rs)} | {pct(sum(r['S1'] for r in rs), len(rs))} | {pct(sum(r['S1_sal'] for r in rs), len(rs))} |")
    L.append('')

    # ---------------- quiet tier
    L.append('## Draft-2.1 tiers: quiet, dim, faded, popout\n')
    L.append('Quiet success = a colour exists with C in [0.05, 0.09], |Lc| within 15 of fg, and D1 at the **reliable** level (p = .8) from fg, dim and every other quiet colour in use; '
             'the most fg-like passing colour is chosen. On failure (or when the family is dropped) `quiet_fallback` applies: value → the quiet tint of whichever kept family accent '
             'has the best D1 margin vs fg and dim (**borrowed**), else default; never dim. Definition use sites (hybrid) → default. "own" = value kept and its quiet passed; '
             '"borrowed" = value dropped or failed and another family\'s tint is used; "none" = strings are default ink.\n')
    L.append('| set | mode | value quiet ok (own, when kept) | definition quiet ok | strings: own / borrowed / none | median quiet C (value) | any quiet colour failed | dim ok (≥ floor 20 and ≥ 10 below fg) | median dim Lc | fg_limited (|Lc fg| < 50) | faded D1 from dim | popout has spare accent |')
    L.append('|---|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|')
    for sn in M.V2_SETS:
        for mo in MODES:
            rs = by[(sn, mo)]
            n = len(rs)

            def qrate(f):
                xs = [r[f'quiet_{f}'] for r in rs if r.get(f'quiet_{f}', '') != '']
                return f'{pct(sum(xs), len(xs))} (n={len(xs)})' if xs else '–'
            sq = [r['strings_quiet'] for r in rs]
            L.append(f"| {sn} | {mo} | {qrate('value')} | {qrate('definition')} | {pct(sq.count('own'), n)} / {pct(sq.count('borrowed'), n)} / {pct(sq.count('none'), n)} "
                     f"| {med([r['quiet_C_value'] for r in rs]):.3f} | {pct(sum(r['quiet_any_fail'] for r in rs), n)} "
                     f"| {pct(sum(r['dim_ok'] for r in rs), n)} | {med([r['dim_lc'] for r in rs]):.1f} | {sum(r['fg_limited'] for r in rs)} ({pct(sum(r['fg_limited'] for r in rs), n)}) "
                     f"| {pct(sum(r['faded_ok'] for r in rs), n)} | {pct(sum(r['popout_accent'] for r in rs), n)} |")
    L.append('')
    lmH = by[('landmark', HEAD)]
    noval = sum(1 for r in lmH if 'value' not in r['kept'].split())
    L.append(f'Value dropped in landmark {HEAD}: {pct(noval, len(lmH))} of palettes (v2 draft: 11%). Strings are never dim in draft 2.1; the "none" share above is the strings-default share. '
             f'Palettes with |Lc(fg)| < 50 (`fg_limited`): {sum(r["fg_limited"] for r in lmH)} of {len(lmH)}; the dim tier there sits below Lc 40 because below_default 10 outranks the lc target.\n')

    # ---------------- coloured ink by family
    L.append('## C2: coloured ink by family (median share of non-whitespace ink, headline mode)\n')
    L.append('| set | ' + ' | '.join(ALL_FAMS) + ' | total |')
    L.append('|---|' + '---:|' * (len(ALL_FAMS) + 1))
    for sn in M.SETS:
        rs = by[(sn, HEAD)]
        L.append(f'| {sn} | ' + ' | '.join(f"{med([r[f'ink_{f}'] for r in rs]):.3f}" for f in ALL_FAMS)
                 + f" | {med([r['coloured_ink'] for r in rs]):.3f} |")
    L.append('\nAt full capacity (palettes that keep every family), headline mode:\n')
    L.append('| set | n | coloured ink | loud | quiet | dim | sal.-weighted ink | ' + ' | '.join(ALL_FAMS) + ' |')
    L.append('|---|---:|---:|---:|---:|---:|---:|' + '---:|' * len(ALL_FAMS))
    for sn in M.SETS:
        rs = [r for r in by[(sn, HEAD)] if r['kept_n'] == r['required']]
        if rs:
            L.append(f"| {sn} | {len(rs)} | {med([r['coloured_ink'] for r in rs]):.3f} | {med([r['ink_loud'] for r in rs]):.3f} "
                     f"| {med([r['ink_quiet'] for r in rs]):.3f} | {med([r['ink_dim'] for r in rs]):.3f} | {med([r['sal_ink'] for r in rs]):.3f} | "
                     + ' | '.join(f"{med([r[f'ink_{f}'] for r in rs]):.3f}" for f in ALL_FAMS) + ' |')
    L.append('')

    # ---------------- by palette group
    L.append('## Draft-2.1 landmark by palette group (headline mode)\n')
    L.append('| group | n | cap (median) | kept (median) | % all 4 | fid mean | L1–L3 ≥ default | L1–L3 fail | S1 | value quiet ok | disc. normal | C6 total | coloured ink | sal.-weighted ink | C1 ρ |')
    L.append('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|')
    g = groups(lm)
    for k in GROUP_ORDER:
        rs = g.get(k, [])
        if not rs:
            continue
        n = len(rs)
        xs = [r['quiet_value'] for r in rs if r.get('quiet_value', '') != '']
        L.append(f"| {k[0]} {k[1]} | {n} | {med([r['cap'] for r in rs])} | {med([r['kept_n'] for r in rs])} | {pct(sum(r['kept_n'] == r['required'] for r in rs), n)} "
                 f"| {mean([r['fid_mean'] for r in rs]):.4f} "
                 f"| {pct(sum(r['L123'] in ('strict', 'default') for r in rs), n)} | {pct(sum(r['L123'] == 'fail' for r in rs), n)} "
                 f"| {pct(sum(r['S1'] for r in rs), n)} | {pct(sum(xs), len(xs))} | {mean([r['confusion_normal_disc'] for r in rs]):.5f} "
                 f"| {mean([r['C6_disc'] for r in rs]):.5f} | {med([r['coloured_ink'] for r in rs]):.3f} | {med([r['sal_ink'] for r in rs]):.3f} "
                 f"| {med([r['C1_rho'] for r in rs]):.2f} |")
    L.append('')
    L.append('Tier failures (landmark, headline mode, all palettes): ' + ', '.join(
        f"{c}: fail {pct(sum(r[c] == 'fail' for r in lm), len(lm))}, floor {pct(sum(r[c] == 'floor' for r in lm), len(lm))}"
        for c in ('L1', 'L2', 'L3', 'L4')) + '.\n')

    # ---------------- H10
    L.append('## H10: mode A (salience-driven) vs mode B (conventional hue habits)\n')
    L.append('Paired per palette (same set, same kept families). "A better" = strictly lower.\n')
    L.append('| set | n | C1 ρ A | B | A better ρ | S1 A | S1 B | disc. A | disc. B | disc. A lower | disc. A higher | disc. deutan A | B | C6 total A | B | habit fit A | B |')
    L.append('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|')
    for sn in M.SETS:
        A = {r['id']: r for r in by[(sn, 'A')]}
        B = {r['id']: r for r in by[(sn, 'B')]}
        ids = sorted(set(A) & set(B))
        n = len(ids)
        L.append(f"| {sn} | {n} | {med([A[i]['C1_rho'] for i in ids]):.3f} | {med([B[i]['C1_rho'] for i in ids]):.3f} "
                 f"| {pct(sum(A[i]['C1_rho'] < B[i]['C1_rho'] for i in ids), n)} "
                 f"| {pct(sum(A[i]['S1'] for i in ids), n)} | {pct(sum(B[i]['S1'] for i in ids), n)} "
                 f"| {mean([A[i]['confusion_normal_disc'] for i in ids]):.5f} | {mean([B[i]['confusion_normal_disc'] for i in ids]):.5f} "
                 f"| {pct(sum(A[i]['confusion_normal_disc'] < B[i]['confusion_normal_disc'] - 1e-12 for i in ids), n)} "
                 f"| {pct(sum(A[i]['confusion_normal_disc'] > B[i]['confusion_normal_disc'] + 1e-12 for i in ids), n)} "
                 f"| {mean([A[i]['confusion_deutan_disc'] for i in ids]):.5f} | {mean([B[i]['confusion_deutan_disc'] for i in ids]):.5f} "
                 f"| {mean([A[i]['C6_disc'] for i in ids]):.5f} | {mean([B[i]['C6_disc'] for i in ids]):.5f} "
                 f"| {mean([A[i]['habit_fit'] for i in ids]):.2f} | {mean([B[i]['habit_fit'] for i in ids]):.2f} |")
    L.append('')

    # ---------------- H12
    L.append('## H12: all sets (headline mode; mode A below)\n')
    L.append('| set | mode | hue families | kept (median) | % at full capacity | sal.-weighted ink | budget (tier) | coloured ink | loud ink | disc. normal | disc. deutan | separable disc. | separable disc. deutan | beacon loss | C6 total | C6 total separable | beacon coverage | C1 ρ | C1 ρ tier | S1a | S1b | L1–L3 ≥ default |')
    L.append('|---|---|' + '---:|' * 20)
    for mo in [HEAD] + [m for m in MODES if m != HEAD]:
        for sn in M.SETS:
            rs = by[(sn, mo)]
            n = len(rs)
            L.append(f"| {sn} | {mo} | {rs[0]['required']} | {med([r['kept_n'] for r in rs])} | {pct(sum(r['kept_n'] == r['required'] for r in rs), n)} "
                     f"| {med([r['sal_ink'] for r in rs]):.3f} | {med([r['budget_tier'] for r in rs]):.3f} | {med([r['coloured_ink'] for r in rs]):.3f} "
                     f"| {med([r['ink_loud'] for r in rs]):.3f} "
                     f"| {mean([r['confusion_normal_disc'] for r in rs]):.5f} | {mean([r['confusion_deutan_disc'] for r in rs]):.5f} "
                     f"| {mean([r['confusion_normal_disc_sep'] for r in rs]):.5f} | {mean([r['confusion_deutan_disc_sep'] for r in rs]):.5f} "
                     f"| {mean([r['beacon_loss'] for r in rs]):.4f} | {mean([r['C6_disc'] for r in rs]):.5f} | {mean([r['C6_disc_sep'] for r in rs]):.5f} "
                     f"| {med([r['beacon_coverage'] for r in rs]):.2f} | {med([r['C1_rho'] for r in rs]):.2f} | {med([r['C1_rho_tier'] for r in rs]):.2f} "
                     f"| {s1a(rs)} | {s1b(rs)} | {pct(sum(r['L123'] in ('strict', 'default') for r in rs), n)} |")
    L.append('')
    for x, y in (('landmark', 'label'), ('landmark', 'landmark_v1'), ('hybrid', 'landmark'), ('hybrid', 'hybrid_v1')):
        A = {r['id']: r for r in by[(x, HEAD)]}
        B = {r['id']: r for r in by[(y, HEAD)]}
        ids = sorted(set(A) & set(B))
        n = len(ids)
        L.append(f"- Paired {x} vs {y} (mode {HEAD}, n = {n}): {x} has lower disc. confusion in "
                 f"{pct(sum(A[i]['confusion_normal_disc'] < B[i]['confusion_normal_disc'] - 1e-12 for i in ids), n)} (higher in "
                 f"{pct(sum(A[i]['confusion_normal_disc'] > B[i]['confusion_normal_disc'] + 1e-12 for i in ids), n)}), lower separable disc. confusion in "
                 f"{pct(sum(A[i]['confusion_normal_disc_sep'] < B[i]['confusion_normal_disc_sep'] - 1e-12 for i in ids), n)} (higher in "
                 f"{pct(sum(A[i]['confusion_normal_disc_sep'] > B[i]['confusion_normal_disc_sep'] + 1e-12 for i in ids), n)}), lower C6 total in "
                 f"{pct(sum(A[i]['C6_disc'] < B[i]['C6_disc'] - 1e-12 for i in ids), n)}, lower deutan disc. in "
                 f"{pct(sum(A[i]['confusion_deutan_disc'] < B[i]['confusion_deutan_disc'] - 1e-12 for i in ids), n)}, lower salience-weighted ink in "
                 f"{pct(sum(A[i]['sal_ink'] < B[i]['sal_ink'] for i in ids), n)}, lower coloured ink in "
                 f"{pct(sum(A[i]['coloured_ink'] < B[i]['coloured_ink'] for i in ids), n)}; keeps all families "
                 f"{pct(sum(A[i]['kept_n'] == A[i]['required'] for i in ids), n)} vs {pct(sum(B[i]['kept_n'] == B[i]['required'] for i in ids), n)}.")
    L.append('\nNote: confusion is computed over each set\'s *own* must-differ pairs; beacon loss over each set\'s *own* design.\n')

    # ---------------- λ sensitivity
    L.append('## C6 beacon-loss weight: sensitivity (headline mode, discounted)\n')
    L.append(f'C6 total = disc. confusion + k·λ·beacon loss, λ = {lam["disc"]:.5f}.\n')
    L.append('| set | mean disc. confusion | mean beacon loss | C6 at λ/3 | C6 at λ | C6 at 3λ | share of C6 from beacon loss at λ |')
    L.append('|---|---:|---:|---:|---:|---:|---:|')
    for sn in M.SETS:
        rs = by[(sn, HEAD)]
        c = mean([r['confusion_normal_disc'] for r in rs])
        b = mean([r['beacon_loss'] for r in rs])
        L.append(f"| {sn} | {c:.5f} | {b:.4f} | {c + lam['disc'] * b / 3:.5f} | {c + lam['disc'] * b:.5f} | {c + 3 * lam['disc'] * b:.5f} "
                 f"| {pct(lam['disc'] * b, c + lam['disc'] * b)} |")
    L.append('')
    L.append('Ranking of sets by mean C6 total (headline mode): ' + '; '.join(
        f"k = {k}: " + ' < '.join(sorted(M.SETS, key=lambda sn: mean([r['confusion_normal_disc'] + k * lam['disc'] * r['beacon_loss'] for r in by[(sn, HEAD)]])))
        for k in (1 / 3, 1, 3)).replace('k = 0.3333333333333333', 'k = 1/3') + '.\n')

    L += sensitivity(rows, rows_on)

    # ---------------- spot checks
    L.append('## Spot checks (role → colour)\n')
    for pid, themes in spots:
        th = themes.get(('landmark', HEAD))
        if not th:
            continue
        cols = [('landmark', 'B'), ('landmark', 'A'), ('hybrid', 'B'), ('label', 'B'), ('landmark_v1', 'B')]
        L.append(f"### {pid} ({th['variant']}; bg {th['bg']}, fg {th['fg']}, |Lc| fg {th['checks']['fg_lc']})\n")
        L.append(f"Draft-2 capacity {th['capacity']}; kept {th['families_kept']}; dropped {th['families_dropped'] or '–'}; "
                 f"reserved for diagnostics: {th['diagnostic']}. dim `{th['tiers']['dim']}` (Lc {th['tiers']['dim_lc']}), faded `{th['tiers']['faded']}` "
                 f"(Lc {th['tiers']['faded_lc']}); quiet: " + ', '.join(f"{f} `{q['hex']}` (C {q['C']})" if q['ok'] else f"{f} failed → {q['fallback']}"
                                                                         for f, q in th['quiet'].items())
                 + f"; popout: {('`' + th['popout']['hex'] + '` ' + th['popout']['hue_name']) if th['popout'] else 'fg bold'}.\n")
        L.append('Family accents:\n')
        L.append('| family | ' + ' | '.join(f'{a} {b}' for a, b in cols) + ' |')
        L.append('|---|' + '---|' * len(cols))
        fams = list(dict.fromkeys(f for c in cols for f in (themes.get(c) or {}).get('families', {})))

        def cell(t, f):
            if not t or f not in t['families']:
                return '–'
            v = t['families'][f]
            return f"`{v['hex']}` {v['hue_name']} ({v['slot']}, fid {v['fidelity']}, Lc {v['lc']})"
        for f in fams:
            L.append(f'| {f} | ' + ' | '.join(cell(themes.get(c), f) for c in cols) + ' |')
        L.append('\nRoles (landmark, headline mode; salience = draft-2 model):\n')
        L.append('| role | fg | |Lc| | C | hue | bold | family | tier | salience |')
        L.append('|---|---|---:|---:|---|---|---|---|---:|')
        for rid, r in th['roles'].items():
            if r.get('fg') is None:
                L.append(f"| {rid} | (inherit) | | | | | | strike | |")
                continue
            L.append(f"| {rid} | `{r['fg']}` | {K.alc(r['fg'], th['bg']):.0f} | {K.oklch(r['fg'])[1]:.3f} | {K.hue_name(r['fg'])} | {'B' if r['bold'] else ''} "
                     f"| {r['family'] or ''} | {r['tier']} | {K.salience_v2(r['fg'], th['fg'], th['bg'], r['bold']):.2f} |")
        c = th['checks']
        L.append(f"\nChecks: L1 {c['L1']}, L2 {c['L2']}, L3 {c['L3']}, L4 {c['L4']}; S1 {c['S1']} ({', '.join(f'{k} {v}' for k, v in c['S1_pairs'].items())}); "
                 f"confusion {c['confusion_normal']:.4f} (disc. {c['confusion_normal_disc']:.5f}; {c['confused_pairs_normal']} pairs), deutan {c['confusion_deutan']:.4f} "
                 f"(disc. {c['confusion_deutan_disc']:.5f}); beacon loss {c['beacon_loss']:.4f}; coloured ink {c['coloured_ink']:.3f} "
                 f"(loud {c['ink_split']['loud']:.3f}, quiet {c['ink_split']['quiet']:.3f}, dim {c['ink_split']['dim']:.3f}); sal.-weighted ink {c['sal_weighted_ink']:.3f}; "
                 f"C1 ρ {c['C1_rho']:.2f} (tier {c['C1_rho_tier']:.2f}).\n")
    return L


def main(argv):
    limit = None
    if '--limit' in argv:
        limit = int(argv[argv.index('--limit') + 1])
    pals = MP.load_palettes()
    if limit:
        keep = [p for p in pals if p['id'] in SPOT]
        pals = keep + [p for p in pals if p['id'] not in SPOT][:limit]
    ink_src = M.ink_shares()[1]
    adj_src = M.adjacency()[1]
    rows, spots = [], []
    with Pool(max(1, (os.cpu_count() or 2) - 1)) as pool:
        for i, (rs, sp) in enumerate(pool.imap_unordered(score_one, pals, chunksize=4)):
            rows += rs
            if sp:
                spots.append(sp)
            if i % 100 == 0:
                print(f'{i}/{len(pals)}', flush=True)
    rows.sort(key=lambda r: (r['id'], r['reserve_diag'], M.SETS.index(r['set']), r['mode']))
    spots.sort(key=lambda x: SPOT.index(x[0]))
    fields = list(dict.fromkeys(k for r in rows for k in r))
    with open(os.path.join(M.OUT, 'palette_scores.csv'), 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fields, restval='')
        w.writeheader()
        w.writerows(rows)
    with open(os.path.join(M.OUT, 'palette_scores.md'), 'w') as f:
        f.write('\n'.join(report(rows, spots, ink_src, adj_src)) + '\n')
    print('wrote out/palette_scores.csv, out/palette_scores.md')


if __name__ == '__main__':
    main(sys.argv[1:])
