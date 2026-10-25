"""Tests for generate.py (reader theme generator).
    uv run --with coloraide --with pyyaml --with numpy --with scipy python harness/test_generate.py [--fast]
--fast skips the end-to-end generations (~20 s each).
"""
import contextlib
import io
import os
import re
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import colour as K  # noqa: E402
import generate as G  # noqa: E402

BG, FG = '#1c1d21', '#dddfe4'
SPEC = """Background  #1c1d21
Foreground  #DDDFE4

; a comment
Syntax      red
Callable    blue
Type?       yellow
Value       purple
Meta?       green
"""


def exits(fn, *args):
    try:
        fn(*args)
    except SystemExit:
        return True
    return False


def test_parse():
    with tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False) as fh:
        fh.write(SPEC)
    try:
        spec, opt = G.parse_specs([fh.name])
    finally:
        os.unlink(fh.name)
    assert spec == {'bg': BG, 'fg': FG, 'syntax': 'red', 'callable': 'blue', 'type': 'yellow',
                    'value': 'purple', 'meta': 'green'}, spec
    assert opt == {'type', 'meta'}, opt
    spec, opt = G.parse_specs(['bg=1c1d21', 'fg=#dddfe4', 'syntax=#A626A4', 'callable=Blue', 'value=green',
                               'binding=none'])
    assert spec['bg'] == BG and spec['syntax'] == '#a626a4' and spec['callable'] == 'blue', spec
    assert spec['binding'] == 'none' and opt == set()
    assert exits(G.parse_specs, ['bg=#000000', 'fg=#ffffff', 'syntax=red', 'callable=blue'])     # value missing
    assert exits(G.parse_specs, ['bg=red', 'fg=#ffffff', 'syntax=red', 'callable=blue', 'value=green'])
    assert exits(G.parse_specs, ['syntax?=red'])                     # only type/meta may be optional
    assert exits(G.parse_specs, ['colour=red'])                      # unknown key
    assert exits(G.parse_specs, ['type=teal'])                       # unknown hue name


def test_hues():
    for n in G.NAMES:
        hs = G.hues(n)
        assert len(hs) >= 2, (n, hs)
        for h in hs:
            assert K.hue_name_lch(0.75, 0.12, h) == n, (n, h)
    assert any(h > 335 for h in G.hues('pink')) and any(h < 12 for h in G.hues('pink'))


def test_louds():
    hx = G.solve(250.0, 0.15, 60, BG)
    assert abs(K.alc(hx, BG) - 60) < 1, K.alc(hx, BG)
    assert G.solve(250.0, 0.15, 200, BG) is None                    # out of reach
    light = G.solve(250.0, 0.15, 60, '#fbf8f1')
    assert abs(K.alc(light, '#fbf8f1') - 60) < 1 and K.oklch(light)[0] < K.oklch('#fbf8f1')[0]   # darkened
    for n in G.NAMES:
        for h in G.hues(n)[::3]:
            for c in G.louds(n, h, FG, BG):
                assert K.hue_name(c) == n and K.oklch(c)[1] >= G.LOUD_MIN_C and K.alc(c, BG) >= 34.5, (n, h, c)
    assert G.louds('blue', 250.0, FG, BG), 'blue reaches the loud tier on a dark background'


def test_scores():
    ok, cvd, m = G.pair('#f8667b', '#95d6ff')
    assert ok and cvd == 0 and m > 1
    ok, _, _ = G.pair('#61afef', '#62b0f0')
    assert not ok                                                    # same hue name, indistinct
    good = {'syntax': '#f8667b', 'callable': '#95d6ff', 'value': '#978bf2'}
    bad = {'syntax': '#f8667b', 'callable': '#61afef', 'value': '#62b0f0'}
    assert G.loud_score(good, BG) > G.loud_score(bad, BG)
    cands = {'callable': G.louds('blue', 250.0, FG, BG), 'value': G.louds('purple', 300.0, FG, BG)}
    sel = G.fit(cands, BG)
    assert set(sel) == {'callable', 'value'} and all(sel[f] in cands[f] for f in sel)


def test_source():
    slots = [('bg', BG), ('fg', FG), ('syntax', '#f8667b'), ('value', '#978bf2'), ('binding', '#fb98a1'),
             ('popout', '#978bf2')]
    pal, names = G.palette_names(slots)
    assert [n for n, _ in pal] == ['bg', 'fg', 'red', 'purple', 'red-binding'], pal
    assert names['popout'] == 'purple'                               # a repeated colour reuses its entry
    src = G.el_source('t', 'Doc.', 'desc', 'full', ['meta'], slots)
    body = src[src.index('(themer-reader-deftheme'):src.index(';;; t-theme.el ends here')]
    assert body.count('(') == body.count(')'), body
    assert ':popout purple' in src and 'Dropped optional families: meta' in src


def run(args):
    out = io.StringIO()
    with tempfile.TemporaryDirectory() as d, contextlib.redirect_stdout(out):
        el = os.path.join(d, 'x-theme.el')
        G.main(args + ['--name', 'x', '--out', el, '-q'])
        src = open(el).read()
    return out.getvalue(), src


def test_end_to_end():
    out, src = run([f'bg={BG}', f'fg={FG}', 'syntax=red', 'callable=blue', 'type?=yellow', 'value=purple',
                    'meta?=green'])
    assert out.startswith('x: full+cvd'), out
    for f, n in [('syntax', 'red'), ('callable', 'blue'), ('type', 'yellow'), ('value', 'purple'), ('meta', 'green')]:
        hx = re.search(rf'^\s+\({n}\s+"(#[0-9a-f]{{6}})"\)', src, re.M).group(1)
        assert K.hue_name(hx) == n and f':{f} {n}' in src, (f, hx)
    assert ':popout' in src and ':binding' in src
    # A pinned hex is kept; an optional family that can't be distinct (meta blue beside callable blue) is dropped.
    out, src = run([f'bg={BG}', f'fg={FG}', 'syntax=#e06c75', 'callable=blue', 'value=purple', 'meta?=blue',
                    'binding=none'])
    assert '"#e06c75"' in src and ':meta' not in src and ':binding' not in src, src
    assert 'R1 by §4 (meta dropped)' in out, out


def main():
    tests = [test_parse, test_hues, test_louds, test_scores, test_source]
    if '--fast' not in sys.argv:
        tests.append(test_end_to_end)
    for t in tests:
        t()
        print('ok', t.__name__)
    print(f'OK ({len(tests)} tests)')


if __name__ == '__main__':
    main()
