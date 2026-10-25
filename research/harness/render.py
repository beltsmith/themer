"""Render corpus snippets under mapped themes, for human review (00-framework.md §5).

    uv run --with tree-sitter --with tree-sitter-language-pack --with pandas --with pyyaml \
        --with coloraide --with numpy --with scipy python harness/render.py

Writes out/renders/:
  grid_<lang>.html   palettes (rows) × pattern set/mode (columns) for one snippet per language,
                     plus a "plain" column (default ink only) as the no-colour baseline.
  tasks.html         self-contained timed search tasks (find definitions / exits / literals)
                     across sets (plain / landmark C / reader C / label C; Latin square over 4 snippets per
                     language). Served by server/app.py, results POST to /api/reports (stored in S3);
                     opened from disk, they download as JSON. Each report carries the trial set's hash.
  palettes.json      which palettes were sampled and why.

Snippets are chosen automatically (the 32-line window per language with the most distinct
roles, requiring at least one definition, exit, string and comment), not hand-picked.
Palettes: the four in PALETTE_IDS (creator assignments, mode C). `--sample` restores the old stratified
random sample (seeded; variant × capacity tercile) with the old A/B columns.
"""
import hashlib
import html
import json
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import mapper  # noqa: E402
import role_tokens  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "out" / "renders"
LANGS = ["python", "typescript", "rust", "go", "c"]
WINDOW = 32
# C = creator assignment (harness/assignments.yaml). Third element: draft 3.2 options. "options" = the creator's binding slot
# (assignments.yaml `binding:`) + faded commented-out code.
COLUMNS = [("plain", None, None), ("landmark", "C", None), ("reader", "C", None), ("reader", "C", "options")]
TASK_CONDS = [("plain", None), ("landmark", "C"), ("reader", "C"), ("label", "C")]   # 4 conditions -> 4 snippets per language (Latin square)
OLD_COLUMNS = [("plain", None), ("landmark", "A"), ("landmark", "B"), ("hybrid", "A"), ("label", "B"), ("landmark_v1", "A")]
PALETTE_IDS = ["base16/gruvbox-dark-medium", "base16/monokai", "base16/kanagawa", "base16/zenburn"]
SEED = 7
REQUIRED = {"function.def", "keyword.exit", "string", "comment"}


def analyse_file(lang, path):
    _, _, rows, _ = role_tokens.analyse((lang, 0, path))
    cols = role_tokens.COLS
    return path.read_bytes(), [dict(zip(cols, r)) for r in rows]


ROLE_ALIAS = {"comment.code": "comment"}   # sets without a comment.code style draw it as a comment


def theme_for(p, s, m, opt=None):
    """Theme for one column. opt "options" = the draft 3.2 optional cues (creator binding slot + faded commented-out code)."""
    if s == "plain":
        return None
    options = None
    if opt == "options":
        options = {"binding": mapper.load_binding_slot(s, p["id"]) or "auto", "fade_commented_code": True}
    return mapper.map_palette(p, s, m, options=options)


def effective_role(r):
    role = r["role"]
    if role == "variable.def" and r["scope"] == "local":
        return "variable.use"   # sets style top-level bindings only
    if role == "constant.def" and r["scope"] == "local":
        return "constant.use"
    return role


def pick_snippets(lang, n=3):
    """Best window per file; return the top-n windows from distinct files."""
    manifest = json.loads((ROOT / "data" / "corpus_manifest.json").read_text())
    files = manifest["langs"][lang]["files"]
    rng = random.Random(SEED)
    found = []
    for f in rng.sample(files, min(60, len(files))):
        path = role_tokens.CORPUS / f["repo"] / f["path"]
        try:
            src, rows = analyse_file(lang, path)
        except Exception:
            continue
        nlines = src.count(b"\n") + 1
        by_line = {}
        for r in rows:
            by_line.setdefault(r["l0"], set()).add(effective_role(r))
            if lang == "rust" and r["text"] == "?" and r["role"] == "keyword.exit":
                by_line[r["l0"]].add("rust?")      # prefer windows that show the 3.2 `?` exit
        best = None
        for start in range(0, max(1, nlines - WINDOW), 4):
            roles = set().union(*(by_line.get(l, set()) for l in range(start, start + WINDOW)))
            if not REQUIRED <= roles:
                continue
            if best is None or len(roles) > best[0]:
                best = (len(roles), path, start, src, rows)
        if best:
            found.append(best)
    found.sort(key=lambda b: -b[0])
    if len(found) < n:
        raise SystemExit(f"only {len(found)} snippets for {lang}")
    return [b[1:] for b in found[:n]]


def snippet_spans(src, rows, start):
    """Yield (text, role) covering lines [start, start+WINDOW), whitespace as role None."""
    lines = src.split(b"\n")
    lo = sum(len(l) + 1 for l in lines[:start])
    hi = sum(len(l) + 1 for l in lines[:start + WINDOW])
    pos = lo
    for r in sorted((r for r in rows if lo <= r["s"] < hi), key=lambda r: r["s"]):
        if r["s"] > pos:
            yield src[pos:r["s"]].decode("utf-8", "replace"), None
        e = min(r["e"], hi)
        yield src[r["s"]:e].decode("utf-8", "replace"), effective_role(r)
        pos = e
    if pos < hi:
        yield src[pos:hi].decode("utf-8", "replace").rstrip("\n"), None


def style_of(theme, role):
    if theme is None or role is None:
        return ""
    st = theme["roles"].get(role) or theme["roles"].get(ROLE_ALIAS.get(role)) or theme["roles"].get("default")
    css = [f"color:{st['fg'] or theme['fg']}"]
    if st.get("bold"):
        css.append("font-weight:bold")
    if st.get("italic"):
        css.append("font-style:italic")
    if st.get("strike"):
        css.append("text-decoration:line-through")
    return ";".join(css)


def code_html(spans, theme, palette):
    bg = palette["bg"]
    fg = palette["fg"]
    out = []
    for i, (text, role) in enumerate(spans):
        t = html.escape(text)
        if role is None:
            out.append(t)
        else:
            st = style_of(theme, role) or f"color:{fg}"
            out.append(f'<span data-i="{i}" data-role="{role}" style="{st}">{t}</span>')
    return f'<pre class="code" style="background:{bg};color:{fg}">{"".join(out)}</pre>'


def fixed_palettes():
    pals = {p["id"]: p for p in mapper.load_palettes()}
    picked = []
    for pid in PALETTE_IDS:
        p = pals[pid]
        th = mapper.map_palette(p, "landmark", "C")
        picked.append({"id": pid, "variant": p["variant"], "capacity": th["capacity"], "tercile": "creator"})
    return picked, pals


def sample_palettes():
    pals = mapper.load_palettes()
    rng = random.Random(SEED)
    rng.shuffle(pals)
    caps = []
    for p in pals[:300]:
        th = mapper.map_palette(p, "landmark", "A")
        caps.append((th["capacity"], p))
    picked = []
    for variant in ("dark", "light"):
        group = sorted((c for c in caps if c[1]["variant"] == variant), key=lambda c: c[0])
        n = len(group)
        for k, label in enumerate(("low", "mid", "high")):
            tercile = group[k * n // 3:(k + 1) * n // 3]
            if tercile:
                cap, p = rng.choice(tercile)
                picked.append({"id": p["id"], "variant": variant, "capacity": cap, "tercile": label})
    return picked, {p["id"]: p for _, p in caps}


PAGE = """<!doctype html><meta charset="utf-8"><title>{title}</title>
<style>
body{{font-family:sans-serif;background:#888;margin:1em}}
.code{{font-family:'JetBrains Mono','DejaVu Sans Mono',monospace;font-size:10px;line-height:1.4;
padding:.4em .5em;margin:0;white-space:pre;overflow:hidden}}
table{{border-collapse:separate;border-spacing:3px}} td{{vertical-align:top}}
th{{font-size:12px;text-align:left}} .meta{{font-size:11px;color:#111}}
</style><h2>{title}</h2>{body}"""


def cell_meta(th):
    """Kept/dropped families plus, for draft-2 themes, the quiet / dim / popout outcome."""
    if th.get("mode") == "C":
        c = th["conformance"]
        out = "assigned: " + ", ".join(f"{f}={v['slot']}" for f, v in th["families"].items())
        if th["set"] == "label":
            return out + (f"<br>string: {th['string_override']['slot']}" if th.get("string_override") else "")
        if th["set"] == "reader":
            rec = th.get("recessive") or {}
            q = ", ".join(f"{f} {'C %.2f' % v['C'] if v['ok'] else 'failed'}" for f, v in th["quiet"].items())
            out += (f"<br><b>level {th['level']}</b> (normal vision: {th['level_normal']}); kept: {', '.join(th['families_kept'])}"
                    f"<br>{'conforms' if c['conforms'] else 'fails: ' + '; '.join(c['failures'])}"
                    f"<br>recessive: {'C %.2f, ΔLc %+.0f' % (rec['C'], rec['dlc_fg']) if rec.get('ok') else 'failed → default'}"
                    f"{' (outshines exits)' if rec.get('outshines_loud') else ''}<br>quiet: {q or '–'}")
            o = th.get("options") or {}
            if o.get("binding") or o.get("fade_commented_code"):
                b = th.get("binding") or {}
                out += ("<br><b>options</b>: "
                        + (f"parameter tint {b.get('slot')} {b.get('hex')} (hue gap {b.get('hue_gap')}°, "
                           f"{'D1-reliable vs all' if b.get('d1_reliable_all') else 'FAILS D1'})" if b.get("ok") else
                           ("parameter tint failed → default" if o.get("binding") else ""))
                        + ("; commented-out code faded" if o.get("fade_commented_code") else ""))
            return out
        out += "<br><b>" + ("conforms" if c["conforms"] else "fails: " + "; ".join(c["failures"])) + "</b>"
        out += f"<br>strings {th.get('strings_quiet')}, dim Lc {th['tiers']['dim_lc']}"
        return out
    out = f"kept: {', '.join(th['families_kept']) or '–'}<br>dropped: {', '.join(th['families_dropped']) or '–'}"
    if th.get("version") == 2:
        q = "; ".join(f"{f} {'C %.3f' % v['C'] if v['ok'] else 'failed → ' + v['fallback']}" for f, v in th["quiet"].items())
        b = th.get("quiet_borrow")
        q += f"; strings {th.get('strings_quiet')}" + (f" (borrowed from {b['from']}, C {b['C']})" if b and th.get('strings_quiet') == 'borrowed' else "")
        out += (f"<br>quiet: {q or '–'}<br>dim Lc {th['tiers']['dim_lc']}, faded Lc {th['tiers']['faded_lc']}"
                f"<br>popout: {th['popout']['hue_name'] if th['popout'] else 'fg bold'}")
    return out


def write_grid(lang, spans, palettes, pal_by_id, path_note, columns=COLUMNS):
    rows = []
    columns = [(c + (None,))[:3] for c in columns]
    head = "".join(f"<th>{s}{' ' + m if m else ''}{' + options (binding tint, faded code)' if o else ''}</th>" for s, m, o in columns)
    for info in palettes:
        p = pal_by_id[info["id"]]
        cells = []
        for s, m, o in columns:
            th = theme_for(p, s, m, o)
            meta = "" if th is None else cell_meta(th)
            cells.append(f"<td>{code_html(spans, th, p)}<div class=meta>{meta}</div></td>")
        rows.append(f"<tr><th>{html.escape(info['id'])}<br><span class=meta>{info['variant']}, "
                    f"{'capacity %d (%s)' % (info['capacity'], info['tercile']) if info['tercile'] != 'creator' else 'creator assignment'}</span></th>{''.join(cells)}</tr>")
    body = f"<p class=meta>{html.escape(path_note)}</p><table><tr><th></th>{head}</tr>{''.join(rows)}</table>"
    (OUT / f"grid_{lang}.html").write_text(PAGE.format(title=f"{lang}: palettes × pattern sets", body=body))


TASKS = {
    "definitions": ({"function.def", "type.def", "macro.def", "constant.def", "variable.def"},
                    "Click every name being DEFINED (functions, types, constants, top-level variables)."),
    "exits": ({"keyword.exit"}, "Click every place control LEAVES (return, raise/throw, break, continue, yield)."),
    "literals": ({"string", "number", "boolean", "constant.builtin"},
                 "Click every LITERAL value (strings, numbers, booleans, nil/null/None)."),
}


TASK_LANGS = ["python", "typescript", "rust"]


def write_tasks(snippets, palettes, pal_by_id, conds=None):
    """Latin square: each (lang, task) shows each condition once, each on a different snippet,
    so position memory from one condition doesn't speed up another."""
    rng = random.Random(SEED + 1)
    trials = []
    conds = conds or TASK_CONDS
    for lang in TASK_LANGS:
        for ti, (task, (targets, prompt)) in enumerate(TASKS.items()):
            for ci, (s, m) in enumerate(conds):
                snip = (ci + ti) % len(snippets[lang])
                spans = snippets[lang][snip]
                info = rng.choice(palettes)
                p = pal_by_id[info["id"]]
                th = None if s == "plain" else mapper.map_palette(p, s, m)
                n_t = sum(1 for _, r in spans if r in targets)
                if n_t == 0:
                    continue
                trials.append({"lang": lang, "task": task, "snippet": snip, "set": s, "mode": m, "palette": info["id"],
                               "prompt": prompt, "targets": sorted(targets), "n_targets": n_t,
                               "html": code_html(spans, th, p)})
    rng.shuffle(trials)
    trials_json = json.dumps(trials)
    version = hashlib.sha256(trials_json.encode()).hexdigest()[:12]
    body = """
<p>For each trial: read the instruction, press <b>Start</b>, click every matching token, then press
<b>Done</b>. Speed and accuracy both count; don't hunt for perfection. Clicking a token again un-marks it.
<span id=save-note>At the end, press <b>Submit results</b> to send them to the research server.</span></p>
<div id=ui><p id=prompt></p><button id=start>Start</button> <button id=done disabled>Done</button>
<span id=prog></span><div id=stage></div></div>
<script>
const T = %s, VERSION = %s;
// Opened from disk (file://) there is no server: results download as JSON instead.
const SERVED = location.protocol.startsWith('http');
let k = 0, t0 = 0, picked = new Set(), results = [];
const $ = s => document.querySelector(s), started = new Date().toISOString();
if (!SERVED) $('#save-note').innerHTML =
  'At the end, press <b>Download results</b> and save the JSON into <code>research/out/</code>.';
function download(){ const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([JSON.stringify(results,null,1)],{type:'application/json'}));
  a.download = 'task_results.json'; a.click(); }
async function submit(){ const st = $('#status'); $('#submit').disabled = true; st.textContent = 'Sending…';
  const report = {trials_version: VERSION, started, finished: new Date().toISOString(), results,
    client: {viewport: [innerWidth, innerHeight], dpr: devicePixelRatio, colour_depth: screen.colorDepth,
             colour_gamut: matchMedia('(color-gamut: p3)').matches ? 'p3' : 'srgb',
             tz: Intl.DateTimeFormat().resolvedOptions().timeZone},
    note: $('#note').value.trim() || null};
  try { const r = await fetch(new URL('/api/reports', location), {method: 'POST',
          headers: {'Content-Type': 'application/json'}, body: JSON.stringify(report)});
    if (!r.ok) throw new Error(`${r.status} ${await r.text()}`);
    st.textContent = `Thank you, results saved (${(await r.json()).id}).`;
  } catch (e) { st.textContent = `Sending failed (${e.message}); please download the results instead.`;
    $('#submit').disabled = false; } }
function show(){
  if (k >= T.length){ $('#ui').innerHTML = SERVED
      ? '<p>All done.</p><p><label>Anything to add (optional; e.g. display, colour vision, how it felt):<br>'
        + '<textarea id=note rows=3 cols=60 maxlength=2000></textarea></label></p>'
        + '<button id=submit>Submit results</button> <button id=dl>Download results</button> <span id=status></span>'
      : '<p>All done.</p><button id=dl>Download results</button>';
    $('#dl').onclick = download; if (SERVED) $('#submit').onclick = submit; return; }
  $('#prompt').textContent = T[k].prompt; $('#stage').innerHTML = '';
  $('#prog').textContent = `trial ${k+1}/${T.length}`; $('#start').disabled = false; $('#done').disabled = true;
}
$('#start').onclick = () => { const tr = T[k]; $('#stage').innerHTML = tr.html; picked = new Set();
  $('#stage').querySelectorAll('span[data-role]').forEach(s => s.onclick = () => {
    const i = s.dataset.i; if (picked.has(i)) { picked.delete(i); s.style.outline=''; }
    else { picked.add(i); s.style.outline='2px solid #f0f'; } });
  t0 = performance.now(); $('#start').disabled = true; $('#done').disabled = false; };
$('#done').onclick = () => { const tr = T[k], ms = performance.now() - t0;
  let hit = 0, fa = 0; picked.forEach(i => { const r = $('#stage').querySelector(`span[data-i="${i}"]`).dataset.role;
    tr.targets.includes(r) ? hit++ : fa++; });
  results.push({lang: tr.lang, task: tr.task, snippet: tr.snippet, set: tr.set, mode: tr.mode, palette: tr.palette,
    n_targets: tr.n_targets, hits: hit, false_alarms: fa, ms: Math.round(ms)});
  k++; show(); };
show();
</script>""" % (trials_json, json.dumps(version))
    (OUT / "tasks.html").write_text(PAGE.format(title=f"Search tasks ({len(trials)} trials)", body=body))
    return len(trials)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    sample = "--sample" in sys.argv
    columns = OLD_COLUMNS if sample else COLUMNS
    palettes, pal_by_id = sample_palettes() if sample else fixed_palettes()
    (OUT / "palettes.json").write_text(json.dumps(palettes, indent=1))
    snippets = {}
    for lang in LANGS:
        picks = pick_snippets(lang, 4)
        snippets[lang] = [list(snippet_spans(src, rows, start)) for _, start, src, rows in picks]
        path, start, _, _ = picks[0]
        spans = snippets[lang][0]
        note = f"{path.relative_to(role_tokens.CORPUS)} lines {start + 1}-{start + WINDOW}"
        write_grid(lang, spans, palettes, pal_by_id, note, columns)
        print(lang, note)
    print("tasks:", write_tasks(snippets, palettes, pal_by_id, [("plain", None), ("landmark", "A"), ("label", "B")] if sample else None), "trials")
    print("palettes:", *(f"{p['id']} ({p['variant']}, cap {p['capacity']})" for p in palettes), sep="\n  ")


if __name__ == "__main__":
    main()
