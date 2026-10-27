"""Generate the most readable reader theme from family -> hue-name assignments (PATTERNS.md, draft 3.2).

    uv run --with coloraide --with pyyaml --with numpy --with scipy python harness/generate.py \
        SPEC... [--name NAME] [--out FILE.el] [--json FILE]

SPEC is KEY=VALUE arguments and/or files of "Key value" lines, e.g.

    Background  #1c1d21
    Foreground  #dddfe4
    Syntax      red
    Callable    blue
    Type?       yellow
    Value       purple
    Meta?       green

Keys: background/bg, foreground/fg (hex, required); syntax, callable, value (required), type, meta: a hue name
(red orange yellow green cyan blue purple pink) or a hex, kept as given. A trailing `?` marks type/meta optional.
popout, binding: a hue name or hex (default: searched); binding `none` for no parameter tint.

Every candidate theme is scored by the reference mapper (mapper.map_reader, mode C), so the result conforms by the
same checks as `reader-theme-derive`. The search:
 1. Hue. Each named family's hue is searched within its hue name's OKLCH bin (2 degrees in from each end, 5 degree
    steps), by coordinate descent. For each set of hues the loud forms are fitted (step 2) and the theme scored:
    normal-vision level, then CVD level, then fewest MUST failures at R0 (full), then fewest CVD failures, then the
    least distinct pair among the reading cues (default, recessive, quiet) and the loud forms.
 2. Loud forms. Per hue, candidates at |Lc| 35..fg in steps of 5, chroma up to MAX_C (three steps), still carrying
    the hue name and C >= 0.08. Chosen by coordinate descent on the loud pairs: categorically distinct, then |Lc| >= 45,
    then reliably distinct under deutan/protan, then margins. Refined at the end on the full score.
 3. Popout (TODO ink and default UI accent): a hue name no family or fg uses, |Lc| >= 60 with the background
    readable on it at Lc 60, furthest from the loud colours.
 4. Parameter tint: the hue whose quiet tint passes and is furthest in hue from the other quiet cues.
Optional families are dropped when the theme without them reaches a better normal-vision level (shedding would
give the same faces; dropping lets the remaining families be re-optimised).

Writes a `reader-theme-deftheme` file (--out, default NAME-theme.el) and prints the report.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import colour as K  # noqa: E402
import mapper as Mp  # noqa: E402
import mapper_common as M  # noqa: E402

FAMILIES = ['syntax', 'callable', 'type', 'value', 'meta']
REQUIRED = ['syntax', 'callable', 'value']
NAMES = ['red', 'orange', 'yellow', 'green', 'cyan', 'blue', 'purple', 'pink']
KEYS = ['bg', 'fg'] + FAMILIES + ['popout', 'binding']
ALIASES = {'background': 'bg', 'foreground': 'fg'}
LEVEL_RANK = {'none': 0, 'R4': 1, 'R3': 2, 'R2': 3, 'R1': 4, 'R0': 5}
HUE_STEP = 5.0
MAX_C = 0.18
CHROMA_STEPS = (0.67, 0.83, 1.0)
LOUD_MIN_C = 0.08
SET = M.load_set('reader')
DROP_ORDER = M.drop_order(SET)          # meta, type, callable, syntax, value


# ------------------------------------------------------------------ input

def parse_pair(key, value, spec, optional):
    k = key.strip().lower()
    opt = k.endswith('?')
    k = ALIASES.get(k.rstrip('?'), k.rstrip('?'))
    if k not in KEYS:
        sys.exit(f'unknown key {key!r} (keys: {", ".join(KEYS)})')
    if opt and k not in ('type', 'meta'):
        sys.exit(f'only type and meta may be optional, not {k}')
    v = value.strip()
    if re.fullmatch(r'#?[0-9a-fA-F]{6}', v):
        v = K.norm(v if v.startswith('#') else '#' + v)
    else:
        v = v.lower()
        if v not in NAMES and not (k == 'binding' and v == 'none'):
            sys.exit(f'{k}: {value!r} is neither a hue name ({", ".join(NAMES)}) nor a hex')
    if k in ('bg', 'fg') and not v.startswith('#'):
        sys.exit(f'{k} must be a hex colour')
    spec[k] = v
    if opt:
        optional.add(k)


def parse_specs(args):
    spec, optional = {}, set()
    for a in args:
        if '=' in a:
            k, v = a.split('=', 1)
            parse_pair(k, v, spec, optional)
        elif os.path.isfile(a):
            for line in open(a):
                line = line.strip()
                if not line or line.startswith((';', '//')):
                    continue
                parts = line.split()
                if len(parts) != 2:
                    sys.exit(f'{a}: expected "Key value", got {line!r}')
                parse_pair(*parts, spec, optional)
        else:
            sys.exit(f'not KEY=VALUE or a file: {a}')
    for k in ['bg', 'fg'] + REQUIRED:
        if k not in spec:
            sys.exit(f'{k} is required')
    return spec, optional


# ------------------------------------------------------------------ hues and loud candidates

def hue_range(name):
    if name == 'pink':
        return 335.0, 372.0
    lo = 12.0
    for ub, n in K.HUE_BINS:
        if n == name:
            return lo, float(ub)
        lo = float(ub)
    raise ValueError(name)


def hues(name):
    lo, hi = hue_range(name)
    lo, hi = lo + 2, hi - 2
    n = max(1, round((hi - lo) / HUE_STEP))
    return [round((lo + i * (hi - lo) / n) % 360, 2) for i in range(n + 1)]


def solve(h, c, lc, bg):
    """Hex at hue h, chroma up to c (gamut-fitted at fixed L, h), with |Lc| ~ lc on bg; None if out of reach."""
    up = K.oklch(bg)[0] < 0.6
    if K.alc(K.from_oklch(1.0 if up else 0.0, c, h), bg) < lc:
        return None
    a, b = 0.0, 1.0
    for _ in range(25):
        m = (a + b) / 2
        if (K.alc(K.from_oklch(m, c, h), bg) >= lc) == up:
            b = m
        else:
            a = m
    return K.from_oklch(b if up else a, c, h)


_louds = {}


def louds(name, h, fg, bg):
    key = (name, h, fg, bg)
    if key not in _louds:
        out = []
        lc = 35.0
        while lc <= min(85.0, K.alc(fg, bg)):
            for k in CHROMA_STEPS:
                hx = solve(h, MAX_C * k, lc, bg)
                if hx and K.hue_name(hx) == name and K.oklch(hx)[1] >= LOUD_MIN_C and hx not in out:
                    out.append(hx)
            lc += 5
        _louds[key] = out
    return _louds[key]


# ------------------------------------------------------------------ scores

def pair(a, b):
    """(categorically distinct, CVD failures, margin) as mapper.conformance judges loud pairs; margin 1 = threshold."""
    dd = K.de_text(K.cvd(a, 'deutan'), K.cvd(b, 'deutan'), 0.8)
    dp = K.de_text(K.cvd(a, 'protan'), K.cvd(b, 'protan'), 0.8)
    return bool(K.d2(a, b, strict_name=True)), (dd < 1) + (dp < 1), min(K.de_text(a, b, 0.5), dd, dp)


def pairs(hexes):
    return [pair(a, b) for i, a in enumerate(hexes) for b in hexes[i + 1:]]


def loud_score(sel, bg):
    ps = pairs(list(sel.values()))
    ms = [p[2] for p in ps] or [3.0]
    return (-sum(not p[0] for p in ps), -sum(K.alc(h, bg) < 44.5 for h in sel.values()),
            -sum(p[1] for p in ps), min(ms) + sum(min(m, 1.5) for m in ms))


def descend(cands, start, score):
    """Coordinate descent over {family: [options]} from `start`, maximising score(sel)."""
    sel, cur = dict(start), score(start)
    for _ in range(10):
        moved = False
        for f, opts in cands.items():
            for o in opts:
                if o == sel[f]:
                    continue
                tr = dict(sel, **{f: o})
                s = score(tr)
                if s > cur:
                    sel, cur, moved = tr, s, True
        if not moved:
            break
    return sel, cur


def fit(cands, bg):
    """One loud colour per family: descent on loud_score from two starts (all near Lc 60; alternately 50 / 70)."""
    best = None
    for targets in ((60,), (50, 70)):
        start = {f: min(c, key=lambda h: abs(K.alc(h, bg) - targets[i % len(targets)]))
                 for i, (f, c) in enumerate(cands.items())}
        r = descend(cands, start, lambda s: loud_score(s, bg))
        if best is None or r[1] > best[1]:
            best = r
    return best[0]


def min_de(hexes):
    ds = [K.de_text(a, b, 0.8) for i, a in enumerate(hexes) for b in hexes[i + 1:]]
    return min(ds) if ds else 3.0


def palette(base, loud, popout=None):
    cols = {'base00': base['bg'], 'base05': base['fg']}
    cols.update({f: h for f, h in loud.items()})
    if popout:
        cols['popout'] = popout
    return {'id': 'generated', 'family': 'generated', 'variant': '', 'bg': base['bg'], 'fg': base['fg'],
            'colours': cols}


def theme(base, loud, popout=None):
    return Mp.map_reader(palette(base, loud, popout), assign={f: f for f in loud})


def score(t):
    """Higher is better: levels, R0 MUST failures, CVD failures, weakest reading / loud distinction."""
    r0 = t['levels_tried']['R0']['failures']
    must = sum(1 for x in r0 if not re.search(r': (deutan|protan)(, (deutan|protan))?$', x))
    cvd = sum(x.count('deutan') + x.count('protan') for x in r0)
    fg = t['fg']
    reading = [fg] + [x for x in [t['tiers'].get('recessive')] if x] + [q['hex'] for q in t['quiet'].values() if q['hex']]
    lm = min([p[2] for p in pairs([v['hex'] for v in t['families'].values()])] or [3.0])
    rm = min_de(reading)
    dim_loud = sum(K.alc(v['hex'], t['bg']) < 44.5 for v in t['families'].values())    # SHOULD loud Lc >= 45
    # Loud forms (definitions, literals) should stand apart from their own quiet form (calls, strings) by more than bold.
    flat = sum(not K.d1(v['hex'], t['quiet'][f]['hex'], 'reliable')
               for f, v in t['families'].items() if t['quiet'].get(f, {}).get('hex'))
    return (LEVEL_RANK[t['level_normal']], LEVEL_RANK[t['level']], -must, -cvd, -dim_loud - flat, min(1.5, rm, lm),
            rm + lm)


# ------------------------------------------------------------------ search

def search(base, fams, log):
    """fams {family: hue name | hex}. Returns (loud {family: hex}, theme, score)."""
    hs = {f: ([None] if v.startswith('#') else hues(v)) for f, v in fams.items()}
    cur = {f: h[len(h) // 2] for f, h in hs.items()}
    memo = {}

    def cands_for(sel):
        return {f: ([fams[f]] if fams[f].startswith('#') else louds(fams[f], sel[f], base['fg'], base['bg']))
                for f in fams}

    def evaluate(sel):
        key = tuple(sorted(sel.items(), key=lambda x: x[0]))
        if key not in memo:
            c = cands_for(sel)
            if any(not v for v in c.values()):
                memo[key] = None
            else:
                loud = fit(c, base['bg'])
                t = theme(base, loud)
                memo[key] = (loud, t, score(t))
        return memo[key]

    best = evaluate(cur)
    for p in range(4):
        moved = False
        for f, opts in hs.items():
            for h in opts:
                if h == cur[f]:
                    continue
                sel = dict(cur, **{f: h})
                r = evaluate(sel)
                if r and (best is None or r[2] > best[2]):
                    best, cur, moved = r, sel, True
            if best:
                log(f'pass {p + 1} {f:8s} {best[0][f]} score {fmt_score(best[2])}')
        if not moved:
            break
    if best is None:
        sys.exit(f'no loud colours reach the loud tier for {fams} on {base["bg"]}')
    # Refine the loud forms on the full score, hues fixed.
    cands = cands_for(cur)
    full = {}

    def full_score(sel):
        k = tuple(sorted(sel.items()))
        if k not in full:
            full[k] = score(theme(base, sel))
        return full[k]

    loud, s = descend(cands, best[0], full_score)
    if s > best[2]:
        log(f'refined loud forms, score {fmt_score(s)}')
        best = (loud, theme(base, loud), s)
    return best


def fmt_score(s):
    inv = {v: k for k, v in LEVEL_RANK.items()}
    return f'level {inv[s[0]]}/{inv[s[1]]} must {-s[2]} cvd {-s[3]} shoulds {-s[4]} margin {s[5]:.2f}'


def pick_popout(want, loud, fg, bg):
    if want and want.startswith('#'):
        return want
    used = {K.hue_name(h) for h in loud.values()} | {K.hue_name(fg)}
    names = [want] if want else [n for n in NAMES if n not in used]
    best = None
    for n in names:
        for h in hues(n):
            for lc in (60, 65, 70, 75, 80):
                hx = solve(h, MAX_C, lc, bg)
                if not hx or K.hue_name(hx) != n:
                    continue
                s = ((K.alc(hx, bg) >= 60) + (K.alc(bg, hx) >= 60),
                     min(3.0, min(K.de_text(hx, l, 0.8) for l in loud.values())), -K.alc(hx, bg))
                if best is None or s > best[0]:
                    best = (s, hx)
    return best[1] if best else None


def pick_binding(want, base, loud, popout, t):
    """Source colour whose quiet tint (mapper._binding_try) passes, furthest in hue from the other quiet cues and the
    recessive keywords (both reading-layer tints it sits among)."""
    if want == 'none':
        return None, None
    srcs = [want] if want and want.startswith('#') else \
        [s for n in ([want] if want else NAMES) for h in hues(n) if (s := solve(h, 0.12, 60, base['bg']))]
    p = palette(base, loud, popout)
    tints = [q['hex'] for q in t['quiet'].values() if q['hex']] + [x for x in [t['tiers'].get('recessive')] if x]
    t['_set'] = SET
    best = None
    for s in srcs:
        p['colours']['binding'] = s
        hx, _ = Mp._binding_try('binding', p, t, base['fg'], base['bg'])
        gap = min((K.dhue(hx, q) for q in tints), default=180.0) if hx else None
        if hx and (best is None or gap > best[2]):
            best = (s, hx, gap)
    del t['_set']
    return (best[0], best[1]) if best else (None, None)


# ------------------------------------------------------------------ output

def palette_names(slots):
    """[(key, hex)] -> (palette [(name, hex)], {key: name}); names are bg, fg or hue names."""
    pal, names = [], {}
    for k, hx in slots:
        hit = next((n for n, h in pal if h == hx), None)
        if hit is None:
            n = k if k in ('bg', 'fg') else K.hue_name(hx)
            if any(n == m for m, _ in pal):
                n = f'{n}-{k}'
            pal.append((n, hx))
            hit = n
        names[k] = hit
    return pal, names


def el_source(name, doc, desc, level, dropped, slots):
    pal, names = palette_names(slots)
    w = max(len(n) for n, _ in pal)
    lines = [f';;; {name}-theme.el --- {doc} -*- lexical-binding: t; -*-', '',
             ";; A reader-standard theme (research/PATTERNS.md); see `reader-theme-deftheme'.",
             ';; Generated by research/harness/generate.py from:', f';;   {desc}',
             f';; Conformance (reference mapper): {level}.'
             + (f'  Dropped optional families: {", ".join(dropped)}.' if dropped else ''),
             '', ';;; Code:', '', "(require 'reader-theme)", '', f'(reader-theme-deftheme {name}', f'  {json.dumps(doc)}']
    for i, (n, hx) in enumerate(pal):
        lines.append(('  :palette (' if i == 0 else '            ') + f'({n:<{w}} "{hx}")' + (')' if i == len(pal) - 1 else ''))
    for k, _ in slots:
        lines.append(f'  :{k} {names[k]}')
    lines[-1] += ')'
    lines += ['', f';;; {name}-theme.el ends here', '']
    return '\n'.join(lines)


def level_string(t):
    if t['level'] == 'R0' and t['level_normal'] == 'R0':
        return 'full+cvd'
    return 'full' if t['level_normal'] == 'R0' else t['level_normal']


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('spec', nargs='+', help='KEY=VALUE or a file of "Key value" lines')
    ap.add_argument('--name', default='reader-generated')
    ap.add_argument('--out', help='theme file (default NAME-theme.el)')
    ap.add_argument('--json', help='also write the chosen colours and the mapper result as JSON')
    ap.add_argument('-q', '--quiet', action='store_true')
    a = ap.parse_args(argv)
    spec, optional = parse_specs(a.spec)
    log = (lambda m: None) if a.quiet else (lambda m: print(m, file=sys.stderr))
    base = {'bg': spec['bg'], 'fg': spec['fg']}
    fams = {f: spec[f] for f in FAMILIES if f in spec}

    loud, t, s = search(base, fams, log)
    dropped = []
    for f in DROP_ORDER:
        if f in optional and f in fams and t['level_normal'] != 'R0':
            less = {k: v for k, v in fams.items() if k != f}
            log(f'{f} is optional and the theme is {t["level_normal"]}: trying without it')
            r = search(base, less, log)
            if LEVEL_RANK[r[1]['level_normal']] >= LEVEL_RANK[t['level_normal']]:
                fams, (loud, t, s) = less, r
                dropped.append(f)
                log(f'dropped {f}')

    popout = pick_popout(spec.get('popout'), loud, base['fg'], base['bg'])
    t = theme(base, loud, popout)
    bsrc, btint = pick_binding(spec.get('binding'), base, loud, popout, t)
    if bsrc:
        p = palette(base, loud, popout)
        p['colours']['binding'] = bsrc
        t = Mp.map_reader(p, assign={f: f for f in loud}, options={'binding': 'binding'})

    slots = [('bg', base['bg']), ('fg', base['fg'])] + [(f, loud[f]) for f in FAMILIES if f in loud]
    if bsrc:
        slots.append(('binding', bsrc))
    if popout:
        slots.append(('popout', popout))
    desc = ', '.join(f'{k}{"?" if k in optional else ""} {spec[k]}' for k in KEYS if k in spec)
    level = level_string(t)
    if dropped:
        # §3: a conforming theme has every family; without one it carries that family's §4 level.
        lv = 'R2' if 'type' in dropped else 'R1'
        level = f'{level} for the families kept; {lv} by §4 ({", ".join(dropped)} dropped)'
    out = a.out or f'{a.name}-theme.el'
    with open(out, 'w') as fh:
        fh.write(el_source(a.name, 'Generated on the reader standard.', desc, level, dropped, slots))

    print(f'{a.name}: {level} (normal vision {t["level_normal"]}, with CVD {t["level"]})')
    if dropped:
        print(f'dropped optional families: {", ".join(dropped)}')
    bg = base['bg']
    print(f'  {"bg":9s} {bg}\n  {"fg":9s} {base["fg"]}  Lc {K.alc(base["fg"], bg):.1f}')
    for f in FAMILIES:
        if f in loud:
            q = t['quiet'].get(f, {}).get('hex')
            L, C, h = K.oklch(loud[f])
            kept = '' if f in t['families'] else '  (shed)'
            form = f'recessive {t["tiers"].get("recessive")}' if f == 'syntax' else f'quiet {q or "-"}'
            print(f'  {f:9s} {loud[f]} {K.hue_name(loud[f]):6s} Lc {K.alc(loud[f], bg):4.1f} C {C:.3f} h {h:5.1f}'
                  f'  {form}{kept}')
    print(f'  {"dim":9s} {t["tiers"]["dim"]}  faded {t["tiers"]["faded"]}')
    if popout:
        print(f'  {"popout":9s} {popout} {K.hue_name(popout)}  Lc {K.alc(popout, bg):.1f} (also the UI accent)')
    if bsrc:
        b = t.get('binding') or {}
        print(f'  {"binding":9s} {bsrc} -> tint {b.get("hex")}  hue gap {b.get("hue_gap")}')
    for lv, info in t['levels_tried'].items():
        print(f'  {lv}: ' + ('; '.join(info['failures']) if info['failures'] else 'no failures'))
    print(f'wrote {out}')
    if a.json:
        with open(a.json, 'w') as fh:
            json.dump({'spec': spec, 'optional': sorted(optional), 'dropped': dropped, 'loud': loud,
                       'popout': popout, 'binding': bsrc, 'level': level, 'theme': t}, fh, indent=1, default=str)


if __name__ == '__main__':
    main(sys.argv[1:])
