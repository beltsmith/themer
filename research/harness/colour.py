"""Colour metric library for the palette harness (00-framework.md §1.3, notes/03 "Recommended metrics").

All inputs are sRGB hex strings ('#rrggbb'). Everything is cached by hex, so repeated
calls are cheap. Run `uv run --with coloraide python harness/colour.py` for the self-tests
(values checked against notes/03).

Checks implemented (IDs from notes/03 "Checks and thresholds"):
  D1 distinguishable as text      de_text(p=.8) >= 1 reliable, de_text(p=.5) >= 1 floor
  D2 categorically different      D1 and (hue-name differs or |dL_ok| >= .12)
  D3 same family / related        same hue name, |dh| <= 25, D1 floor passes
  D4 hue carries meaning          C_ok >= .04 (meaningful) / >= .06 (reliably nameable)
  L1-L4                           APCA |Lc| tiers, see lc_tier()

Hue names: OKLCH hue bins anchored on the basic colour terms of notes/03 §5 (centres
red 25, orange 55, yellow 95, green 140, cyan 195, blue 250, purple 305, pink 345).
Boundaries were placed between those centres and calibrated so that named reference
colours fall where their names say (computed in OKLCH with coloraide 8.13.1):
  pink   [335, 12)   #ff0080 h=2.5, Solarized magenta h=355.9, Dracula pink h=346.8
  red    [12, 37)    #ff0000 h=29.2, Solarized red h=27.1, Dracula red h=24.4
  orange [37, 75)    Solarized orange h=39.5, #ff8000 h=53, #ffa500 h=70.7
  yellow [75, 116)   gold h=95, #ffff00 h=109.8, Solarized yellow h=85.7, Dracula yellow h=112.8
  green  [116, 175)  Solarized green h=118.6, #00ff00 h=142.5
  cyan   [175, 225)  #00ffff h=194.8, Solarized cyan h=187.4, Nord frost h=217.5
  blue   [225, 275)  deepskyblue h=231.6, #0000ff h=264.1, Solarized blue h=244.9
  purple [275, 335)  Solarized violet h=279.1, Dracula purple h=301.9, #ff00ff h=328.4
  brown  = orange/yellow hue (37 <= h < 116) with L_ok < 0.50 (Berlin & Kay brown is
           dark orange/yellow; XKCD 'brown' #653700 has L_ok 0.386, 'tan' 0.776)
  grey   = C_ok < 0.04 (D4: hue below text-size chroma threshold)
Cyan and yellow are narrow and blue is wide, as notes/03 §5 says.
"""
from __future__ import annotations

import os
import sys
from functools import lru_cache

from coloraide import Color

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apca import apca_lc as _apca_lc  # noqa: E402  (verified implementation)

# ---------------------------------------------------------------- conversions


def norm(h: str) -> str:
    h = h.strip().lower()
    if not h.startswith('#'):
        h = '#' + h
    if len(h) == 4:
        h = '#' + ''.join(c * 2 for c in h[1:])
    return h[:7]


@lru_cache(maxsize=None)
def oklch(h: str) -> tuple[float, float, float]:
    L, C, hue = Color(h).convert('oklch').coords()
    if hue != hue:  # NaN for achromatic
        hue = 0.0
    return (L, C, hue)


@lru_cache(maxsize=None)
def oklab(h: str) -> tuple[float, float, float]:
    return tuple(Color(h).convert('oklab').coords())


@lru_cache(maxsize=None)
def lab65(h: str) -> tuple[float, float, float]:
    return tuple(Color(h).convert('lab-d65').coords())


def to_hex(c: Color) -> str:
    return c.convert('srgb').fit('srgb').to_string(hex=True, compress=False)


def from_oklch(L: float, C: float, h: float) -> str:
    return to_hex(Color('oklch', [max(0.0, min(1.0, L)), max(0.0, C), h]))


@lru_cache(maxsize=None)
def de_ok(a: str, b: str) -> float:
    (l1, a1, b1), (l2, a2, b2) = oklab(a), oklab(b)
    return ((l1 - l2) ** 2 + (a1 - a2) ** 2 + (b1 - b2) ** 2) ** 0.5


@lru_cache(maxsize=None)
def de_00(a: str, b: str) -> float:
    return Color(a).delta_e(b, method='2000')


# ---------------------------------------------------------------- Szafir line model


def nd_line(p: float, s: float):
    """Szafir 2018 Eqs 14-16 (lines): per-axis CIELAB noticeable difference."""
    return [p / (c - k / s) for c, k in ((0.0742, 0.0023), (0.0623, 0.0015), (0.0425, 0.0009))]


_ND = {}


@lru_cache(maxsize=None)
def de_text(a: str, b: str, p: float = 0.8, s: float = 0.1) -> float:
    """Szafir 2018 Eq 4, CIELAB D65. >= 1 means a fraction p of viewers see a difference."""
    key = (p, s)
    if key not in _ND:
        _ND[key] = nd_line(p, s)
    nL, na, nb = _ND[key]
    (l1, a1, b1), (l2, a2, b2) = lab65(a), lab65(b)
    return (((l1 - l2) / nL) ** 2 + ((a1 - a2) / na) ** 2 + ((b1 - b2) / nb) ** 2) ** 0.5


# ---------------------------------------------------------------- contrast


@lru_cache(maxsize=None)
def lc(text: str, bg: str) -> float:
    return _apca_lc(text, bg)


def alc(text: str, bg: str) -> float:
    """|APCA Lc|."""
    return abs(lc(text, bg))


@lru_cache(maxsize=None)
def wcag(a: str, b: str) -> float:
    return Color(a).contrast(b, method='wcag21')


# ---------------------------------------------------------------- hue names

HUE_BINS = [  # (upper bound exclusive, name), walked in order from 12
    (37, 'red'), (75, 'orange'), (116, 'yellow'), (175, 'green'),
    (225, 'cyan'), (275, 'blue'), (335, 'purple'),
]
GREY_C = 0.04   # D4 meaningful
NAME_C = 0.06   # D4 reliably nameable / accent threshold
BROWN_L = 0.50


def hue_name_lch(L: float, C: float, h: float) -> str:
    if C < GREY_C:
        return 'grey'
    h = h % 360
    if h >= 335 or h < 12:
        return 'pink'
    for ub, name in HUE_BINS:
        if h < ub:
            if name in ('orange', 'yellow') and L < BROWN_L:
                return 'brown'
            return name
    return 'pink'


@lru_cache(maxsize=None)
def hue_name(hx: str) -> str:
    return hue_name_lch(*oklch(hx))


def dhue(a: str, b: str) -> float:
    d = abs(oklch(a)[2] - oklch(b)[2]) % 360
    return min(d, 360 - d)


# ---------------------------------------------------------------- D checks


def d1(a: str, b: str, level: str = 'floor') -> bool:
    p = 0.8 if level == 'reliable' else 0.5
    return de_text(a, b, p) >= 1.0


def d1_tier(a: str, b: str) -> str:
    if de_text(a, b, 0.8) >= 1:
        return 'reliable'
    if de_text(a, b, 0.5) >= 1:
        return 'floor'
    return 'fail'


@lru_cache(maxsize=None)
def d2(a: str, b: str, level: str = 'floor', strict_name: bool = False) -> bool:
    """Categorically different: D1 and (hue-name differs or |dL_ok| >= 0.12).
    Hue name is 'grey' below C 0.04, so grey-vs-chromatic counts as a name difference.
    strict_name (draft-2 spec fix (a), used for distinct hue FAMILIES): the hue name must differ;
    a lightness difference alone does not make two colours different families."""
    if not d1(a, b, level):
        return False
    if hue_name(a) != hue_name(b):
        return True
    if strict_name:
        return False
    return abs(oklch(a)[0] - oklch(b)[0]) >= 0.12


def d2_margin(a: str, b: str, level: str = 'floor', strict_name: bool = False) -> float:
    """Signed margin for D2: de_text - 1 if categorical, else negative.
    Used as the assignment objective (larger = safer)."""
    p = 0.8 if level == 'reliable' else 0.5
    m = de_text(a, b, p) - 1.0
    if hue_name(a) == hue_name(b) and (strict_name or abs(oklch(a)[0] - oklch(b)[0]) < 0.12):
        return min(m, -0.01)
    return m


def d3(a: str, b: str) -> bool:
    return hue_name(a) == hue_name(b) and dhue(a, b) <= 25 and d1(a, b, 'floor')


def d4(hx: str, reliable: bool = False) -> bool:
    return oklch(hx)[1] >= (NAME_C if reliable else GREY_C)


# ---------------------------------------------------------------- L checks

L_TIERS = {  # (strict, default, floor) |Lc| thresholds, notes/03
    'L1': (75, 60, 45),
    'L2': (60, 45, 35),
    'L3': (45, 30, 20),
    'L4': (15, 15, 15),
}
TIER_ORDER = ['strict', 'default', 'floor', 'fail']


def lc_tier(value: float, check: str, bold: bool = False) -> str:
    s, d, f = L_TIERS[check]
    if bold and check == 'L2':  # "if the role is drawn bold, lower each tier by 10-15": use 10
        s, d, f = s - 10, d - 10, f - 10
    if value >= s:
        return 'strict'
    if value >= d:
        return 'default'
    if value >= f:
        return 'floor'
    return 'fail'


def worst(*tiers: str) -> str:
    return max(tiers, key=TIER_ORDER.index) if tiers else 'strict'


# ---------------------------------------------------------------- CVD

CVD_METHOD = {'protan': 'machado', 'deutan': 'machado', 'tritan': 'brettel'}


@lru_cache(maxsize=None)
def cvd(hx: str, kind: str) -> str:
    """Full-severity dichromat simulation. Machado 2009 for protan/deutan, Brettel 1997 for tritan.
    coloraide returns srgb-linear: convert + fit before use (notes/03 §4)."""
    if kind in (None, 'normal'):
        return hx
    return to_hex(Color(hx).filter(kind, 1.0, method=CVD_METHOD[kind]))


# ---------------------------------------------------------------- salience

HK_K = 0.2       # H-K-style chroma term (notes/03 §7: k 0.1-0.25, OKLab L units), ordering only
BOLD_LC = 15.0   # one weight step ~ +15 Lc (notes/03 §6)


def salience(hx: str, bg: str, bold: bool = False, chroma_k: float = HK_K) -> float:
    """Effective salience in Lc units: |Lc| + 15·bold + 100·k·C_ok.
    chroma_k=0.2 is the notes/03 H-K ordering term; a larger k models hue pop-out against
    an achromatic ground (see palette_scores.md for the k used)."""
    return alc(hx, bg) + (BOLD_LC if bold else 0.0) + 100.0 * chroma_k * oklch(hx)[1]


# Draft-2 salience model (spec fix (d)), used for S1 and C1 on every set:
#   sal = a·max(0, |Lc|−|Lc_fg|)/100 + b·C_ok/0.15 + c·bold − d·max(0, |Lc_fg|−|Lc|)/100
# Units: 1.0 = 100 Lc. Weights are chosen so the declared tier order
#   faded < dim < default < quiet < loud < strong < popout
# holds with margin >= S1_MARGIN (7.5 Lc) for the IDEAL palette (tier targets from landmark.yaml):
#   fg Lc 60 C 0 | faded Lc 30 C 0 | dim Lc 45 C 0 | quiet Lc 60 C .055 (mid of [.03,.08])
#   loud Lc 45 (its target) C .128 (corpus median accent C) | strong = loud + bold | popout Lc 45 C .178
# giving faded −.30d, dim −.15d, default 0, quiet .367b, loud .853b − .15d, strong +c, popout +.333b.
# a = d = 1 (luminance contrast is the primary salience cue, symmetric about fg); c = .15 (one weight
# step ~ +15 Lc, notes/03 §6). Binding constraint: loud − quiet = .487b − .15 >= .075  ->  b >= .462;
# b = 0.5 (C .15 ~ 50 Lc). The earlier SAL_K = 1.5 (C .15 ~ 22.5 Lc) cannot rank a loud accent at its
# Lc target above a quiet tint at fg lightness.
SAL_A, SAL_B, SAL_C, SAL_D = 1.0, 0.5, 0.15, 1.0
S1_MARGIN = 0.075


def salience_v2(hx: str, fg: str, bg: str, bold: bool = False) -> float:
    v, f = alc(hx, bg), alc(fg, bg)
    return (SAL_A * max(0.0, v - f) / 100 + SAL_B * oklch(hx)[1] / 0.15 + (SAL_C if bold else 0.0)
            - SAL_D * max(0.0, f - v) / 100)


# ---------------------------------------------------------------- derivation


def shift_l_to_lc(src: str, bg: str, target: float, max_fid: float | None = None):
    """Smallest OKLCH lightness shift (away from bg, gamut-fitted) so |Lc| >= target.
    If max_fid is given, the shift is limited to de_ok(result, src) <= max_fid.
    Returns (hex, |Lc|, fidelity)."""
    cur = alc(src, bg)
    if cur >= target:
        return src, cur, 0.0
    L, C, h = oklch(src)
    up = oklch(bg)[0] < 0.6  # dark bg -> lighten
    lo, hi = L, (1.0 if up else 0.0)
    best = None
    # check the end point first
    end = from_oklch(hi, C, h)
    if alc(end, bg) < target:
        cand = end
    else:
        a, b = lo, hi
        for _ in range(30):
            m = (a + b) / 2
            if alc(from_oklch(m, C, h), bg) >= target:
                b = m
            else:
                a = m
        cand = from_oklch(b, C, h)
    best = cand
    if max_fid is not None and de_ok(best, src) > max_fid:
        a, b = lo, (oklch(best)[0])
        for _ in range(30):
            m = (a + b) / 2
            if de_ok(from_oklch(m, C, h), src) <= max_fid:
                a = m
            else:
                b = m
        best = from_oklch(a, C, h)
        if de_ok(best, src) > max_fid:  # gamut fit moved it; fall back to source
            best = src
    return best, alc(best, bg), de_ok(best, src)


def mix(a: str, b: str, t: float) -> str:
    """OKLab mix: t=0 -> a, t=1 -> b."""
    return to_hex(Color(a).mix(b, t, space='oklab'))


def fade_to_lc(fg: str, bg: str, target: float):
    """mix(fg, bg, t) with t chosen so |Lc| ~= target (CS:L3/L4). Returns (hex, t)."""
    if alc(fg, bg) <= target:
        return fg, 0.0
    a, b = 0.0, 1.0
    for _ in range(30):
        m = (a + b) / 2
        if alc(mix(fg, bg, m), bg) >= target:
            a = m
        else:
            b = m
    return mix(fg, bg, a), a


def chroma_scale(src: str, factor: float, floor_c: float = 0.045) -> str:
    L, C, h = oklch(src)
    return from_oklch(L, max(min(C, floor_c), C * factor), h)


# ---------------------------------------------------------------- self-tests


def _selftest():
    ok = True

    def check(name, got, want, tol):
        nonlocal ok
        good = abs(got - want) <= tol
        ok &= good
        print(f"{'ok ' if good else 'BAD'} {name}: got {got:.3f} want {want} ±{tol}")

    # APCA reference values (notes/03 §3)
    check('apca #888/#fff', lc('#888888', '#ffffff'), 63.056, 0.001)
    check('apca #fff/#888', lc('#ffffff', '#888888'), -68.541, 0.001)
    check('apca #000/#aaa', lc('#000000', '#aaaaaa'), 58.146, 0.001)
    check('apca #aaa/#000', lc('#aaaaaa', '#000000'), -56.241, 0.001)
    # Szafir line thresholds (notes/03 §2b): single-axis dL* needed at 0.1 deg
    nL5, na5, nb5 = nd_line(0.5, 0.1)
    check('ND_L(50%,.1)', nL5, 9.8, 0.05)
    check('ND_a(50%,.1)', na5, 10.6, 0.05)
    check('ND_b(50%,.1)', nb5, 14.9, 0.05)
    nL8, na8, nb8 = nd_line(0.8, 0.1)
    check('ND_L(80%,.1)', nL8, 15.6, 0.05)
    check('ND_a(80%,.1)', na8, 16.9, 0.1)
    check('ND_b(80%,.1)', nb8, 23.9, 0.1)
    nL, na, nb = nd_line(0.5, 0.05)
    check('ND_L(50%,.05)', nL, 17.7, 0.1)
    check('ND_b(50%,.05)', nb, 20.4, 0.1)
    # de_text of a pure L* step equal to the threshold is 1
    g1, g2 = to_hex(Color('lab-d65', [50, 0, 0])), to_hex(Color('lab-d65', [65.6, 0, 0]))
    check('de_text 15.6 L* step', de_text(g1, g2, 0.8), 1.0, 0.04)
    # Tomorrow Night (notes/03 §8): fg -70.9, comment -44.4, red -35.5, yellow -73.7, blue -47.9
    bg = '#1d1f21'
    check('TN fg Lc', lc('#c5c8c6', bg), -70.9, 0.1)
    check('TN comment Lc', lc('#969896', bg), -44.4, 0.1)
    check('TN red Lc', lc('#cc6666', bg), -35.5, 0.1)
    check('TN yellow Lc', lc('#f0c674', bg), -73.7, 0.1)
    check('TN blue Lc', lc('#81a2be', bg), -47.9, 0.1)
    check('TN comment/blue deOK', de_ok('#969896', '#81a2be'), 0.059, 0.001)
    check('TN blue/purple deOK', de_ok('#81a2be', '#b294bb'), 0.073, 0.001)
    # deutan collapse of blue/purple: notes report 0.017 with Vienot; Machado is our default
    vb = to_hex(Color('#81a2be').filter('deutan', 1, method='vienot'))
    vp = to_hex(Color('#b294bb').filter('deutan', 1, method='vienot'))
    # notes/03 quotes 0.017 "(Vienot)"; with coloraide 8.13.1 Vienot gives 0.019 and Machado 0.017.
    check('TN blue/purple deOK deutan (vienot)', de_ok(vb, vp), 0.017, 0.003)
    check('TN blue/purple deOK deutan (machado)', de_ok(cvd('#81a2be', 'deutan'), cvd('#b294bb', 'deutan')), 0.017, 0.002)
    # scale conversion: median dE00/dEOK ~126 (IQR 103-169) for random near-threshold pairs (notes/03 §1)
    import random
    rng = random.Random(1)
    ratios = []
    while len(ratios) < 1500:
        a = '#%06x' % rng.randrange(1 << 24)
        L, C, h = oklch(a)
        b = from_oklch(L + rng.uniform(-.04, .04), C + rng.uniform(-.04, .04), h + rng.uniform(-10, 10))
        d = de_ok(a, b)
        if 0.01 <= d <= 0.06:
            ratios.append(de_00(a, b) / d)
    ratios.sort()
    check('median dE00/dEOK near threshold', ratios[len(ratios) // 2], 126, 15)
    # hue names
    names = {'#ff0000': 'red', '#cb4b16': 'orange', '#b58900': 'yellow', '#859900': 'green',
             '#2aa198': 'cyan', '#268bd2': 'blue', '#6c71c4': 'purple', '#d33682': 'pink',
             '#653700': 'brown', '#808080': 'grey', '#81a2be': 'blue', '#b294bb': 'purple'}
    for hx, want in names.items():
        got = hue_name(hx)
        good = got == want
        ok &= good
        print(f"{'ok ' if good else 'BAD'} hue_name {hx}: {got} (want {want})")
    # D2 / D3 behaviour
    for a, b, want in [('#81a2be', '#b294bb', True), ('#ff5555', '#ff6e6e', False)]:
        got = d2(a, b)
        ok &= got == want
        print(f"{'ok ' if got == want else 'BAD'} d2 {a} {b}: {got}")
    # derivation: shifting TN red to Lc 45 on its bg
    hx, v, fid = shift_l_to_lc('#cc6666', bg, 45)
    print(f"    derive TN red -> Lc45: {hx} |Lc|={v:.1f} fid={fid:.3f}")
    ok &= v >= 45
    hx, v, fid = shift_l_to_lc('#cc6666', bg, 45, max_fid=0.05)
    print(f"    derive TN red -> Lc45 fid<=.05: {hx} |Lc|={v:.1f} fid={fid:.3f}")
    ok &= fid <= 0.0501
    f, t = fade_to_lc('#c5c8c6', bg, 30)
    check('fade TN fg to Lc30', alc(f, bg), 30, 0.5)
    print('ALL OK' if ok else 'FAILURES')
    return ok


if __name__ == '__main__':
    sys.exit(0 if _selftest() else 1)
