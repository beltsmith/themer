"""Normalise base16/base24 (tinted-theming) and ANSI16 (iTerm2-Color-Schemes,
windowsterminal JSON) palettes into data/palettes.jsonl.

Run:  uv run --with pyyaml python harness/load_palettes.py   (from research/)
"""
import json
import re
import sys
from collections import Counter
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
HEX = re.compile(r"^#?([0-9a-fA-F]{6})$")


def norm_hex(v):
    m = HEX.match(str(v).strip())
    return f"#{m.group(1).lower()}" if m else None


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def oklab_L(hexstr):
    r, g, b = (srgb_to_linear(int(hexstr[i:i + 2], 16) / 255) for i in (1, 3, 5))
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l_, m_, s_ = (x ** (1 / 3) for x in (l, m, s))
    return 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_


def variant_from_bg(bg):
    return "dark" if oklab_L(bg) < 0.6 else "light"


def load_tinted():
    out = []
    lic = "tinted-theming/schemes (MIT for the collection; individual scheme authors credited in 'author')"
    for family in ("base16", "base24"):
        for p in sorted((DATA / "schemes" / family).glob("*.y*ml")):
            try:
                d = yaml.safe_load(p.read_text())
            except Exception as e:  # noqa: BLE001
                print(f"skip {p}: {e}", file=sys.stderr)
                continue
            pal = d.get("palette") or {}
            colours = {k: norm_hex(v) for k, v in pal.items() if norm_hex(v)}
            if "base00" not in colours or "base05" not in colours:
                print(f"skip {p}: missing base00/base05", file=sys.stderr)
                continue
            bg, fg = colours["base00"], colours["base05"]
            declared = d.get("variant")
            computed = variant_from_bg(bg)
            out.append({
                "id": f"{family}/{p.stem}",
                "source": "tinted-theming/schemes",
                "family": family,
                "name": d.get("name", p.stem),
                "variant": declared if declared in ("dark", "light") else computed,
                "variant_declared": declared in ("dark", "light"),
                "variant_computed": computed,
                "bg": bg,
                "fg": fg,
                "bg_L": round(oklab_L(bg), 4),
                "colours": colours,
                "author": d.get("author", ""),
                "licence_note": lic,
            })
    return out


ANSI_KEYS = ["black", "red", "green", "yellow", "blue", "purple", "cyan", "white",
             "brightBlack", "brightRed", "brightGreen", "brightYellow", "brightBlue",
             "brightPurple", "brightCyan", "brightWhite"]


def load_iterm():
    out = []
    lic = "mbadolato/iTerm2-Color-Schemes (MIT for repo; schemes from various authors, see repo credits)"
    for p in sorted((DATA / "iterm2" / "windowsterminal").glob("*.json")):
        try:
            d = json.loads(p.read_text())
        except Exception as e:  # noqa: BLE001
            print(f"skip {p}: {e}", file=sys.stderr)
            continue
        colours = {k: norm_hex(d.get(k, "")) for k in ANSI_KEYS}
        if not all(colours.values()):
            print(f"skip {p}: incomplete ANSI16", file=sys.stderr)
            continue
        bg, fg = norm_hex(d.get("background", "")), norm_hex(d.get("foreground", ""))
        if not bg or not fg:
            continue
        for extra in ("cursorColor", "selectionBackground"):
            if norm_hex(d.get(extra, "")):
                colours[extra] = norm_hex(d[extra])
        computed = variant_from_bg(bg)
        out.append({
            "id": f"ansi16/{p.stem}",
            "source": "mbadolato/iTerm2-Color-Schemes",
            "family": "ansi16",
            "name": d.get("name", p.stem),
            "variant": computed,
            "variant_declared": False,
            "variant_computed": computed,
            "bg": bg,
            "fg": fg,
            "bg_L": round(oklab_L(bg), 4),
            "colours": colours,
            "author": "",
            "licence_note": lic,
        })
    return out


def main():
    rows = load_tinted() + load_iterm()
    dst = DATA / "palettes.jsonl"
    with dst.open("w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
    c = Counter((r["family"], r["variant"]) for r in rows)
    print(f"wrote {len(rows)} palettes -> {dst}")
    for fam in ("base16", "base24", "ansi16"):
        print(f"  {fam:7s} total={c[(fam,'dark')]+c[(fam,'light')]:4d} dark={c[(fam,'dark')]:4d} light={c[(fam,'light')]:4d}")
    mism = [r["id"] for r in rows if r["variant_declared"] and r["variant"] != r["variant_computed"]]
    print(f"  declared-vs-computed variant mismatches: {len(mism)} {mism[:10]}")


if __name__ == "__main__":
    main()
