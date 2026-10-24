"""READING metric: how much token-class information the colours carry before anything is read.

    uv run --with coloraide --with pyyaml --with numpy --with scipy python harness/parse_load.py [--limit N]

Writes out/parse_load.csv (one row per theme × vision × punctuation variant) and out/parse_load.md.

Definitions
  * Reading classes (CLASS below): syntax, punctuation, operator, type, callable, binding, literal, string, comment, meta.
  * A theme gives each role a visual style (fg hex, bold, italic). variable.def.top uses the theme's variable.def style,
    variable.def.local uses variable.use's (locals are not top-level bindings in any set).
  * "Looks the same" clusters: union-find over role pairs with equal bold and italic whose colours are NOT D1-reliable
    distinct (colour.de_text p=.8 s=.1 < 1). Under deutan/protan the fg hexes are simulated first (colour.cvd).
  * Token distribution: out/role_stats.csv lang=ALL (unweighted mean over languages, elisp excluded). token_share for
    the entropy, per_screen_mean (tokens per 40-line screen) for the counts.
  * H = H(class | cluster) in bits per token. 0 = colour alone tells you every token's class; plain = H(class).
  * ambiguous/screen = tokens per screen whose cluster's majority class (by tokens) differs from their own class.
  * nopunct: punctuation tokens removed from the distribution (they are lexically trivial).
Themes: plain (fg only), landmark / label / reader mode C on the 4 creator palettes; landmark / label / reader mode B
on every palette in data/palettes.jsonl. Finding-side numbers (salience budget = sal_weighted_ink, C1 ρ, C6_disc,
beacon coverage) come from mapper.evaluate for the same themes.
"""
from __future__ import annotations

import csv
import math
import os
import statistics as stt
import sys
from collections import Counter, defaultdict
from multiprocessing import Pool

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import colour as K  # noqa: E402
import mapper as MP  # noqa: E402
import mapper_common as M  # noqa: E402

CLASS = {
    'keyword.decl': 'syntax', 'keyword.flow': 'syntax', 'keyword.other': 'syntax', 'keyword.exit': 'syntax',
    'variable.builtin': 'syntax', 'label': 'syntax',
    'punctuation': 'punctuation', 'operator': 'operator',
    'type.def': 'type', 'type.use': 'type', 'type.builtin': 'type', 'module': 'type',
    'function.def': 'callable', 'function.call': 'callable', 'function.builtin': 'callable',
    'variable.use': 'binding', 'variable.def.top': 'binding', 'variable.def.local': 'binding', 'parameter': 'binding',
    'field': 'binding', 'default': 'binding',
    'number': 'literal', 'boolean': 'literal', 'constant.use': 'literal', 'constant.builtin': 'literal',
    'constant.def': 'literal', 'string.escape': 'literal',
    'string': 'string', 'string.regexp': 'string',
    'comment': 'comment', 'comment.doc': 'comment', 'comment.todo': 'comment',
    'attribute': 'meta', 'preproc': 'meta', 'macro.def': 'meta', 'macro.call': 'meta',
}
STYLE_ROLE = {'variable.def.top': 'variable.def', 'variable.def.local': 'variable.use'}
CREATOR = ['base16/gruvbox-dark-medium', 'base16/monokai', 'base16/kanagawa', 'base16/zenburn']
SETS_C = ['landmark', 'label', 'reader']
SETS_B = ['landmark', 'label', 'reader']
VISIONS = ['normal', 'deutan', 'protan']


def token_dist():
    rows = [r for r in csv.DictReader(open(os.path.join(M.OUT, 'role_stats.csv'))) if r['lang'] == 'ALL']
    d = {}
    for r in rows:
        if r['role'] in CLASS:
            d[r['role']] = (float(r['token_share']), float(r['per_screen_mean']))
    return d


DIST = token_dist()


def styles_of(theme):
    """role -> (hex, bold, italic). theme None = plain."""
    out = {}
    for rid in DIST:
        if theme is None:
            out[rid] = ('plain', False, False)
            continue
        R = theme['roles']
        r = R.get(STYLE_ROLE.get(rid, rid)) or R['default']
        out[rid] = (r['fg'] or theme['fg'], bool(r['bold']), bool(r['italic']))
    return out


def clusters(styles, vision):
    ids = list(styles)
    par = {r: r for r in ids}

    def find(x):
        while par[x] != x:
            par[x] = par[par[x]]
            x = par[x]
        return x
    sim = {r: (K.cvd(h, vision) if h != 'plain' else h) for r, (h, _, _) in styles.items()}
    for i, a in enumerate(ids):
        for b in ids[i + 1:]:
            ha, hb = sim[a], sim[b]
            if styles[a][1:] != styles[b][1:]:
                continue
            if ha == hb or not K.d1(ha, hb, 'reliable'):
                ra, rb = find(a), find(b)
                if ra != rb:
                    par[ra] = rb
    return {r: find(r) for r in ids}


def load(styles, vision, punct=True):
    cl = clusters(styles, vision)
    roles = [r for r in DIST if punct or CLASS[r] != 'punctuation']
    tot = sum(DIST[r][0] for r in roles)
    by = defaultdict(Counter)       # cluster -> class -> token share
    scr = defaultdict(Counter)      # cluster -> class -> tokens per screen
    for r in roles:
        by[cl[r]][CLASS[r]] += DIST[r][0] / tot
        scr[cl[r]][CLASS[r]] += DIST[r][1]
    H = 0.0
    amb = 0.0
    for c, cnt in by.items():
        pc = sum(cnt.values())
        for v in cnt.values():
            if v > 0:
                H -= v * math.log2(v / pc)
        maj = max(cnt, key=cnt.get)
        amb += sum(n for k, n in scr[c].items() if k != maj)
    return H, amb, len(by)


def rows_for(theme, sn, mode, pid):
    st = styles_of(theme)
    ev = MP.evaluate(theme) if theme is not None else None
    base = {'id': pid, 'set': sn, 'mode': mode or ''}
    if ev:
        base.update({'sal_ink': round(ev['sal_weighted_ink'], 4), 'C1_rho': round(ev['C1_rho'], 3),
                     'C6_disc': round(ev['C6_disc'], 7), 'confusion_normal_disc': round(ev['confusion_normal_disc'], 7),
                     'beacon_coverage': round(ev['beacon_coverage'], 3), 'S1a': int(ev['S1a']),
                     'S1b': '' if ev['S1b'] is None else int(ev['S1b']), 'coloured_ink': round(ev['coloured_ink'], 4)})
    if theme is not None and sn == 'reader':
        base.update({'level': theme['level'], 'level_normal': theme['level_normal'],
                     'recessive_ok': int(bool(theme['recessive'].get('ok'))),
                     'recessive_outshines_loud': int(bool(theme['recessive'].get('outshines_loud'))),
                     'kept': ' '.join(theme['families_kept'])})
        for f in ('type', 'callable', 'value', 'meta'):
            q = theme['quiet'].get(f)
            base[f'quiet_{f}'] = '' if q is None else int(q['ok'])
    out = []
    for v in VISIONS:
        for punct in (True, False):
            H, amb, n = load(st, v, punct)
            out.append(dict(base, vision=v, punct=int(punct), H=round(H, 4), ambiguous=round(amb, 2), n_clusters=n))
    return out


def one_palette(p):
    rows = []
    if p['id'] in CREATOR:
        rows += rows_for(None, 'plain', None, p['id'])
        for sn in SETS_C:
            rows += rows_for(MP.map_palette(p, sn, 'C'), sn, 'C', p['id'])
    for sn in SETS_B:
        rows += rows_for(MP.map_palette(p, sn, 'B'), sn, 'B', p['id'])
    return rows


def med(xs):
    xs = [x for x in xs if x != '' and x is not None]
    return stt.median(xs) if xs else float('nan')


def pct(n, d):
    return f'{100 * n / d:.0f}%' if d else '–'


def report(rows):
    L = ['# Parse load (READING metric)\n', 'Generated by `harness/parse_load.py`; definitions in its docstring. '
         'H = H(class | look-alike cluster), bits per token (lower = colour says more about what a token is). '
         'amb = ambiguous tokens per 40-line screen (cluster majority class ≠ own class). '
         '"no punct" drops punctuation tokens. Corpus: out/role_stats.csv lang=ALL.\n']
    get = lambda **k: [r for r in rows if all(r[a] == b for a, b in k.items())]
    plain = get(set='plain', vision='normal', punct=1)[0]
    L.append(f"Plain baseline: H(class) = {plain['H']:.3f} bits/token, amb = {plain['ambiguous']:.1f} tokens/screen "
             f"(no punct: H {get(set='plain', vision='normal', punct=0)[0]['H']:.3f}, amb {get(set='plain', vision='normal', punct=0)[0]['ambiguous']:.1f}).\n")
    # ---- creator palettes
    L.append('## Creator palettes (mode C)\n')
    L.append('| palette | set | H | amb/screen | H deutan | amb deutan | H protan | amb protan | H no punct | amb no punct | clusters | salience budget | C1 ρ | C6 disc | beacon cov. |')
    L.append('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|')
    for pid in CREATOR:
        for sn in ['plain', 'landmark', 'label', 'reader']:
            def g(v, pu, k):
                return get(id=pid, set=sn, vision=v, punct=pu)[0][k]
            r0 = get(id=pid, set=sn, vision='normal', punct=1)[0]
            fm = lambda k, f: (f % r0[k]) if r0.get(k, '') != '' else '–'
            L.append(f"| {pid.split('/')[1]} | {sn} | {g('normal', 1, 'H'):.3f} | {g('normal', 1, 'ambiguous'):.1f} | {g('deutan', 1, 'H'):.3f} | "
                     f"{g('deutan', 1, 'ambiguous'):.1f} | {g('protan', 1, 'H'):.3f} | {g('protan', 1, 'ambiguous'):.1f} | {g('normal', 0, 'H'):.3f} | "
                     f"{g('normal', 0, 'ambiguous'):.1f} | {g('normal', 1, 'n_clusters')} | {fm('sal_ink', '%.3f')} | {fm('C1_rho', '%.2f')} | "
                     f"{fm('C6_disc', '%.5f')} | {fm('beacon_coverage', '%.2f')} |")
    L.append('')
    L.append('Means over the 4 creator palettes:\n')
    L.append('| set | H | amb | H deutan | amb deutan | H protan | amb protan | H no punct | amb no punct | salience budget | C1 ρ | C6 disc |')
    L.append('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|')
    for sn in ['plain', 'landmark', 'label', 'reader']:
        def m(v, pu, k):
            xs = [r[k] for r in get(set=sn, vision=v, punct=pu) if r['mode'] in ('C', '') and r[k] != '']
            return sum(xs) / len(xs) if xs else float('nan')
        L.append(f"| {sn} | {m('normal', 1, 'H'):.3f} | {m('normal', 1, 'ambiguous'):.1f} | {m('deutan', 1, 'H'):.3f} | {m('deutan', 1, 'ambiguous'):.1f} | "
                 f"{m('protan', 1, 'H'):.3f} | {m('protan', 1, 'ambiguous'):.1f} | {m('normal', 0, 'H'):.3f} | {m('normal', 0, 'ambiguous'):.1f} | "
                 + ('– | – | – |' if sn == 'plain' else f"{m('normal', 1, 'sal_ink'):.3f} | {m('normal', 1, 'C1_rho'):.2f} | {m('normal', 1, 'C6_disc'):.5f} |"))
    L.append('')
    # ---- mode B, all palettes
    nb = len({r['id'] for r in rows if r['mode'] == 'B'})
    L.append(f'## All palettes, mode B (n = {nb}; medians)\n')
    L.append('| set | H | amb | H deutan | amb deutan | H protan | amb protan | H no punct | amb no punct | salience budget | C1 ρ | C6 disc | beacon cov. |')
    L.append('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|')
    for sn in SETS_B:
        def m(v, pu, k):
            return med([r[k] for r in get(set=sn, mode='B', vision=v, punct=pu)])
        L.append(f"| {sn} | {m('normal', 1, 'H'):.3f} | {m('normal', 1, 'ambiguous'):.1f} | {m('deutan', 1, 'H'):.3f} | {m('deutan', 1, 'ambiguous'):.1f} | "
                 f"{m('protan', 1, 'H'):.3f} | {m('protan', 1, 'ambiguous'):.1f} | {m('normal', 0, 'H'):.3f} | {m('normal', 0, 'ambiguous'):.1f} | "
                 f"{m('normal', 1, 'sal_ink'):.3f} | {m('normal', 1, 'C1_rho'):.2f} | {m('normal', 1, 'C6_disc'):.5f} | {m('normal', 1, 'beacon_coverage'):.2f} |")
    L.append('')
    # paired: reader better than landmark?
    byid = defaultdict(dict)
    for r in get(mode='B', vision='normal', punct=1):
        byid[r['id']][r['set']] = r
    pairs = [(d['reader'], d['landmark']) for d in byid.values() if 'reader' in d and 'landmark' in d]
    L.append(f"Paired, mode B: reader H < landmark H on {pct(sum(a['H'] < b['H'] for a, b in pairs), len(pairs))} of palettes; "
             f"median ΔH (reader − landmark) = {med([a['H'] - b['H'] for a, b in pairs]):+.3f} bits/token, "
             f"median Δamb = {med([a['ambiguous'] - b['ambiguous'] for a, b in pairs]):+.1f} tokens/screen; "
             f"median Δsalience budget = {med([a['sal_ink'] - b['sal_ink'] for a, b in pairs]):+.3f}.\n")
    # ---- reader conformance + quiet/recessive success
    rd = get(set='reader', mode='B', vision='normal', punct=1)
    L.append('## Reader conformance and reading-layer success, mode B\n')
    for key in ('level', 'level_normal'):
        c = Counter(r[key] for r in rd)
        L.append(f"- `{key}`: " + ', '.join(f"{k} {pct(c[k], len(rd))}" for k in ['R0', 'R1', 'R2', 'R3', 'R4', 'none'] if c[k]))
    L.append(f"- recessive ok: {pct(sum(r['recessive_ok'] for r in rd), len(rd))}; keywords more salient than exits (salience_v2): "
             f"{pct(sum(r['recessive_outshines_loud'] for r in rd if r['recessive_ok']), sum(r['recessive_ok'] for r in rd))} of successes")
    for f in ('type', 'callable', 'value', 'meta'):
        xs = [r[f'quiet_{f}'] for r in rd if r[f'quiet_{f}'] != '']
        L.append(f"- quiet {f}: {pct(sum(xs), len(xs))} ok (n = {len(xs)} palettes where the family is kept and has quiet roles)")
    kc = Counter(len(r['kept'].split()) for r in rd)
    L.append('- hue families kept: ' + ', '.join(f'{k}: {pct(kc[k], len(rd))}' for k in sorted(kc, reverse=True)))
    L.append('')
    L.append('## Reader conformance, creator palettes (mode C)\n')
    L.append('| palette | level | level (normal vision) | recessive | quiet type / callable / value / meta |')
    L.append('|---|---|---|---|---|')
    for pid in CREATOR:
        r = get(id=pid, set='reader', mode='C', vision='normal', punct=1)[0]
        q = ' / '.join({'': '–', 1: 'ok', 0: 'fail'}[r[f'quiet_{f}']] for f in ('type', 'callable', 'value', 'meta'))
        L.append(f"| {pid.split('/')[1]} | {r['level']} | {r['level_normal']} | {'ok' if r['recessive_ok'] else 'fail'}"
                 f"{' (outshines exits)' if r['recessive_outshines_loud'] else ''} | {q} |")
    L.append('')
    return L


def main(argv):
    pals = MP.load_palettes()
    if '--limit' in argv:
        n = int(argv[argv.index('--limit') + 1])
        pals = [p for p in pals if p['id'] in CREATOR] + [p for p in pals if p['id'] not in CREATOR][:n]
    rows = []
    with Pool(max(1, (os.cpu_count() or 2) - 1)) as pool:
        for i, rs in enumerate(pool.imap_unordered(one_palette, pals, chunksize=4)):
            rows += rs
            if i % 200 == 0:
                print(f'{i}/{len(pals)}', flush=True)
    order = {s: i for i, s in enumerate(['plain'] + SETS_B)}
    rows.sort(key=lambda r: (r['id'], r['mode'], order[r['set']], r['vision'], -r['punct']))
    fields = list(dict.fromkeys(k for r in rows for k in r))
    with open(os.path.join(M.OUT, 'parse_load.csv'), 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fields, restval='')
        w.writeheader()
        w.writerows(rows)
    with open(os.path.join(M.OUT, 'parse_load.md'), 'w') as f:
        f.write('\n'.join(report(rows)) + '\n')
    print('wrote out/parse_load.csv, out/parse_load.md')


if __name__ == '__main__':
    main(sys.argv[1:])
