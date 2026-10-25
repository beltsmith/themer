"""Web server for the reader standard: the research documents as pages, plus the timed search
task (research/out/renders/tasks.html), whose reports are stored in S3.

    uv run uvicorn app:app --reload            # from server/; see README.md

Environment:
  THEMER_RESEARCH_DIR  research/ directory to serve (default: ../research next to this file)
  S3_BUCKET            bucket for task reports; unset → reports go to REPORTS_DIR (local dev)
  S3_PREFIX            key prefix (default "task-reports/")
  S3_ENDPOINT_URL      for S3-compatible stores (MinIO, R2); AWS region/credentials come from
                       the usual AWS_* variables or the instance role
  REPORTS_DIR          local fallback (default ./reports)
"""
import datetime
import html
import json
import os
import re
import uuid
from pathlib import Path

from markdown_it import MarkdownIt
from starlette.applications import Starlette
from starlette.exceptions import HTTPException
from starlette.requests import Request
from starlette.responses import FileResponse, HTMLResponse, JSONResponse, PlainTextResponse, RedirectResponse
from starlette.routing import Route

RESEARCH = Path(os.environ.get("THEMER_RESEARCH_DIR", Path(__file__).resolve().parent.parent / "research")).resolve()
TASKS = RESEARCH / "out" / "renders" / "tasks.html"
BUCKET = os.environ.get("S3_BUCKET")
PREFIX = os.environ.get("S3_PREFIX", "task-reports/")
REPORTS_DIR = Path(os.environ.get("REPORTS_DIR", "reports"))
MAX_BODY = 64 * 1024   # a 36-trial report is ~7 KB
# Never served: the fetched corpus (large, third-party), Python caches, dotfiles.
HIDDEN = {"data", "__pycache__"}
TEXT = {".yaml", ".csv", ".json", ".py", ".sh", ".txt"}

md = MarkdownIt("commonmark", {"html": False}).enable("table")

PAGE = """<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title} · reader</title>
<style>
body{{font-family:system-ui,sans-serif;max-width:52rem;margin:2rem auto;padding:0 1rem;line-height:1.5;color:#222}}
nav{{font-size:.9rem;margin-bottom:1.5rem}} nav a{{margin-right:1rem}}
code,pre{{font-family:'JetBrains Mono','DejaVu Sans Mono',monospace;font-size:.85em}}
pre{{background:#f4f4f4;padding:.6em;overflow:auto}}
table{{border-collapse:collapse;font-size:.9rem;display:block;overflow:auto}}
td,th{{border:1px solid #ccc;padding:.2em .5em;vertical-align:top}}
</style>
<nav><a href="/">Home</a><a href="/research/PATTERNS.md">Standard</a><a href="/research/">Research</a><a href="/task">Take the task</a></nav>
{body}"""

INDEX = """<h1>Reader: a standard for colouring source code</h1>
<p>Reader colours code for <b>reading at a glance</b>: label quietly, landmark loudly.</p>
<ul>
<li><a href="/research/PATTERNS.md">The standard</a> (normative, MUST/SHOULD)</li>
<li><a href="/research/patterns/reader.yaml">reader.yaml</a> and <a href="/research/patterns/roles.yaml">roles.yaml</a>, machine-readable</li>
<li><a href="/research/00-framework.md">Framework</a>: vocabulary, hypotheses, design revisions</li>
<li><a href="/research/notes/">Background notes</a> and <a href="/research/out/">results</a></li>
<li><a href="/research/out/renders/">Renders</a>: palettes × pattern sets</li>
</ul>
<h2>Take part</h2>
<p><a href="/task">The timed search task</a> (36 short trials, about 10 minutes) compares plain code with
the pattern sets. Results are stored anonymously for the research.</p>"""


def page(title, body):
    return HTMLResponse(PAGE.format(title=html.escape(title), body=body))


def resolve(path):
    """PATH under RESEARCH, or 404 (no escaping the directory, no hidden parts)."""
    p = (RESEARCH / path).resolve()
    parts = p.relative_to(RESEARCH).parts if p.is_relative_to(RESEARCH) else (".",)
    if HIDDEN & set(parts) or any(s.startswith(".") for s in parts) or not p.exists():
        raise HTTPException(404)
    return p


def listing(p, rel):
    items = sorted((c for c in p.iterdir() if c.name not in HIDDEN and not c.name.startswith(".")),
                   key=lambda c: (c.is_file(), c.name))
    lis = "".join(f'<li><a href="{html.escape(c.name)}{"/" if c.is_dir() else ""}">'
                  f'{html.escape(c.name)}{"/" if c.is_dir() else ""}</a></li>' for c in items)
    return page(rel or "research", f"<h1>{html.escape('research/' + rel)}</h1><ul>{lis}</ul>")


async def index(request):
    return page("Reader", INDEX)


async def research(request):
    rel = request.path_params["path"].rstrip("/")
    p = resolve(rel)
    if p.is_dir():
        if not request.url.path.endswith("/"):
            return RedirectResponse(request.url.path + "/", 308)
        return listing(p, rel)
    if p.suffix == ".md":
        text = p.read_text()
        m = re.search(r"^# (.+)$", text, re.M)
        return page(m.group(1) if m else p.name, md.render(text))
    if p.suffix in TEXT:
        return PlainTextResponse(p.read_text())
    return FileResponse(p)


async def task(request):
    return FileResponse(TASKS, media_type="text/html")


RESULT = {"lang": str, "task": str, "snippet": int, "set": str, "mode": (str, type(None)), "palette": str,
          "n_targets": int, "hits": int, "false_alarms": int, "ms": int}


def validate(report):
    """The report if it has the shape tasks.html sends, else ValueError."""
    if not isinstance(report, dict) or not isinstance(report.get("results"), list):
        raise ValueError("expected an object with a results list")
    if not isinstance(report.get("trials_version"), str) or not re.fullmatch(r"[0-9a-f]{12}", report["trials_version"]):
        raise ValueError("bad trials_version")
    if not 1 <= len(report["results"]) <= 200:
        raise ValueError("bad number of results")
    for r in report["results"]:
        if not isinstance(r, dict) or set(r) != set(RESULT) or not all(
                isinstance(r[k], t) and not (t is int and isinstance(r[k], bool)) for k, t in RESULT.items()):
            raise ValueError("bad result entry")
    note = report.get("note")
    if note is not None and (not isinstance(note, str) or len(note) > 2000):
        raise ValueError("bad note")
    return {k: report.get(k) for k in ("trials_version", "started", "finished", "results", "client", "note")}


_s3 = None


def store(key, data):
    global _s3
    if not BUCKET:
        out = REPORTS_DIR / key
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(data)
        return
    if _s3 is None:
        import boto3
        _s3 = boto3.client("s3", endpoint_url=os.environ.get("S3_ENDPOINT_URL") or None)
    _s3.put_object(Bucket=BUCKET, Key=key, Body=data, ContentType="application/json")


async def reports(request: Request):
    body = await request.body()
    if len(body) > MAX_BODY:
        return PlainTextResponse("report too large", 413)
    try:
        report = validate(json.loads(body))
    except (ValueError, json.JSONDecodeError) as e:
        return PlainTextResponse(str(e), 400)
    now = datetime.datetime.now(datetime.UTC)
    rid = f"{now:%Y%m%dT%H%M%SZ}-{uuid.uuid4().hex[:8]}"
    report["id"] = rid
    report["received"] = now.isoformat(timespec="seconds")
    report["user_agent"] = request.headers.get("user-agent", "")[:300]
    key = f"{PREFIX}{report['trials_version']}/{rid}.json"
    store(key, json.dumps(report, indent=1).encode())
    return JSONResponse({"id": rid}, 201)


async def healthz(request):
    return PlainTextResponse("ok")


app = Starlette(routes=[
    Route("/", index),
    Route("/task", task),
    Route("/research", lambda r: RedirectResponse("/research/", 308)),
    Route("/research/{path:path}", research),
    Route("/api/reports", reports, methods=["POST"]),
    Route("/healthz", healthz),
])
