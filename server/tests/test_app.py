import json

import boto3
import pytest
from moto import mock_aws
from starlette.testclient import TestClient

import app

REPORT = {"trials_version": "0123456789ab", "started": "2026-10-25T10:00:00Z", "finished": "2026-10-25T10:09:00Z",
          "client": {"viewport": [1280, 800]}, "note": None,
          "results": [{"lang": "rust", "task": "exits", "snippet": 1, "set": "reader", "mode": "C",
                       "palette": "base16/zenburn", "n_targets": 3, "hits": 3, "false_alarms": 0, "ms": 5000}]}


@pytest.fixture
def client():
    return TestClient(app.app)


def test_pages(client):
    assert "Reader" in client.get("/").text
    r = client.get("/research/PATTERNS.md")
    assert r.status_code == 200 and "<h1>Reader: a standard" in r.text and "<table>" in r.text
    assert client.get("/research/patterns/reader.yaml").headers["content-type"].startswith("text/plain")
    assert "PATTERNS.md" in client.get("/research/").text
    assert client.get("/research/out", follow_redirects=False).status_code == 308
    assert "const T =" in client.get("/task").text


@pytest.mark.parametrize("path", ["/research/data/", "/research/../themer.el", "/research/%2e%2e/themer.el",
                                  "/research/harness/.gitignore", "/research/nope.md"])
def test_hidden(client, path):
    assert client.get(path).status_code == 404


def test_report_local(client, tmp_path, monkeypatch):
    monkeypatch.setattr(app, "BUCKET", None)
    monkeypatch.setattr(app, "REPORTS_DIR", tmp_path)
    r = client.post("/api/reports", json=REPORT)
    assert r.status_code == 201
    saved = json.loads((tmp_path / "task-reports" / "0123456789ab" / f"{r.json()['id']}.json").read_text())
    assert saved["results"] == REPORT["results"] and saved["user_agent"]


@pytest.mark.parametrize("bad", [
    {}, {**REPORT, "trials_version": "../x"}, {**REPORT, "results": []},
    {**REPORT, "results": [{**REPORT["results"][0], "extra": 1}]},
    {**REPORT, "results": [{**REPORT["results"][0], "hits": True}]},
    {**REPORT, "note": "x" * 3000}])
def test_report_rejected(client, bad):
    assert client.post("/api/reports", json=bad).status_code == 400


def test_report_too_large(client):
    assert client.post("/api/reports", content=b" " * (app.MAX_BODY + 1)).status_code == 413


def test_report_s3(client, monkeypatch):
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    for k in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"):
        monkeypatch.setenv(k, "testing")
    with mock_aws():
        boto3.client("s3").create_bucket(Bucket="reports")
        monkeypatch.setattr(app, "BUCKET", "reports")
        monkeypatch.setattr(app, "_s3", None)
        rid = client.post("/api/reports", json=REPORT).json()["id"]
        obj = boto3.client("s3").get_object(Bucket="reports", Key=f"task-reports/0123456789ab/{rid}.json")
        assert json.loads(obj["Body"].read())["id"] == rid
