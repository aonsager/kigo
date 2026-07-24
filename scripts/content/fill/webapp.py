#!/usr/bin/env python3
"""webapp.py — the local review web API for the kigo-2026 fill workflow.

Pure request handlers over store.py (unit-testable without a socket) plus a thin
http.server adapter (wired by `fill.py review`). The single per-day review
surface: edit readings/prose, approve the day. Stdlib only.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import store  # noqa: E402

_PROSE_FIELDS = ("reading_ja", "reading_en", "translation_en",
                 "description_ja", "description_en")


def day_summary(day):
    return {
        "date": day["date"], "kanji": day["kanji"], "approved": day["approved"],
        "reading_ja": day["reading_ja"], "season": day["season"],
        "subseason": day["subseason"],
        "has_prose": bool(day["translation_en"] and day["description_ja"]
                          and day["description_en"]),
    }


def handle_list_days(conn, date_from=None, date_to=None, status=None):
    return [day_summary(day) for day in store.list_days(conn, date_from, date_to, status)]


def handle_get_day(conn, date):
    return store.get_day(conn, date)


def handle_patch_day(conn, date, body):
    if store.get_day(conn, date) is None:
        raise ValueError(f"unknown date {date}")
    known = set(_PROSE_FIELDS) | {"approved"}
    bad = set(body) - known
    if bad:
        raise ValueError(f"unknown fields: {sorted(bad)}")
    prose = {k: body[k] for k in _PROSE_FIELDS if k in body}
    if prose:
        store.set_day_fields(conn, date, **prose)
    if "approved" in body:
        store.set_approved(conn, date, bool(body["approved"]))
    return handle_get_day(conn, date)


import http.server  # noqa: E402
import urllib.parse  # noqa: E402


def make_server(conn, web_dir, host="127.0.0.1", port=8000):
    web_dir = Path(web_dir)

    class Handler(http.server.BaseHTTPRequestHandler):
        def _send(self, code, body, ctype="application/json"):
            payload = json.dumps(body).encode("utf-8") if ctype == "application/json" else body
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def _static(self, name):
            path = (web_dir / name).resolve()
            if web_dir.resolve() not in path.parents or not path.is_file():
                return self._send(404, {"error": "not found"})
            ctype = {"html": "text/html", "js": "application/javascript",
                     "css": "text/css"}.get(path.suffix.lstrip("."), "text/plain")
            self._send(200, path.read_bytes(), ctype + "; charset=utf-8")

        def do_GET(self):
            parsed = urllib.parse.urlparse(self.path)
            parts = [p for p in parsed.path.split("/") if p]
            if not parts:
                return self._static("index.html")
            if parts[0] in ("app.js", "style.css", "index.html"):
                return self._static(parts[0])
            if parts[:1] == ["api"] and parts[1:2] == ["days"]:
                if len(parts) == 2:
                    q = urllib.parse.parse_qs(parsed.query)
                    return self._send(200, handle_list_days(
                        conn, q.get("from", [None])[0], q.get("to", [None])[0],
                        q.get("status", [None])[0]))
                day = handle_get_day(conn, parts[2])
                return self._send(404 if day is None else 200,
                                  {"error": "unknown date"} if day is None else day)
            return self._send(404, {"error": "not found"})

        def do_PATCH(self):
            parsed = urllib.parse.urlparse(self.path)
            parts = [p for p in parsed.path.split("/") if p]
            if parts[:2] != ["api", "days"] or len(parts) != 3:
                return self._send(404, {"error": "not found"})
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length) or b"{}")
            try:
                return self._send(200, handle_patch_day(conn, parts[2], body))
            except ValueError as e:
                return self._send(400, {"error": str(e)})

        def log_message(self, *a):  # keep the console quiet
            pass

    return http.server.HTTPServer((host, port), Handler)
