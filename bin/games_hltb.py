#!/usr/bin/env python3
"""HowLongToBeat search helper for the HLTB Search plasmoid.

Usage: hltb.py <query>
Prints JSON: {"ok": true, "results": [...]} or {"ok": false, "error": "..."}
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

BASE = "https://howlongtobeat.com"
UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/130.0 Safari/537.36")
CACHE_DIR = os.path.join(os.path.expanduser("~"), ".cache", "hltb-widget")
TOKEN_FILE = os.path.join(CACHE_DIR, "token.json")
TOKEN_TTL = 30 * 60


def _req(url, data=None, headers=None):
    h = {"User-Agent": UA, "Referer": BASE + "/", "Origin": BASE}
    if headers:
        h.update(headers)
    body = json.dumps(data).encode() if data is not None else None
    if body is not None:
        h["Content-Type"] = "application/json"
    r = urllib.request.Request(url, data=body, headers=h,
                               method="POST" if body else "GET")
    with urllib.request.urlopen(r, timeout=12) as resp:
        return json.loads(resp.read().decode())


def get_token(force=False):
    if not force:
        try:
            with open(TOKEN_FILE) as f:
                c = json.load(f)
            if time.time() - c["ts"] < TOKEN_TTL and c.get("token"):
                return c["token"]
        except Exception:
            pass
    tok = _req(f"{BASE}/api/search/site/init?t={int(time.time() * 1000)}")["token"]
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        with open(TOKEN_FILE, "w") as f:
            json.dump({"token": tok, "ts": time.time()}, f)
    except Exception:
        pass
    return tok


def payload(query):
    inc = lambda: {"mode": "include", "values": []}  # noqa: E731
    return {
        "searchType": "games",
        "searchTerms": query.strip().split(),
        "searchPage": 1,
        "size": 20,
        "searchOptions": {
            "games": {
                "userId": 0,
                "platform": inc(),
                "sortCategory": "popular",
                "rangeCategory": "main",
                "rangeTime": {"min": None, "max": None},
                "gameplay": {"perspective": inc(), "flow": inc(), "genre": inc()},
                "year": inc(),
                "modifier": "",
            },
            "users": {"sortCategory": "postcount"},
            "lists": {"sortCategory": "follows"},
            "filter": "",
            "sort": 0,
            "randomizer": 0,
        },
        "useCache": True,
    }


def hours(sec):
    try:
        sec = float(sec or 0)
    except (TypeError, ValueError):
        return 0
    return round(sec / 3600 * 2) / 2  # nearest half hour, like HLTB


def search(query):
    data = payload(query)
    try:
        res = _req(f"{BASE}/api/search/site", data, {"x-auth-token": get_token()})
    except urllib.error.HTTPError as e:
        if e.code != 403:
            raise
        res = _req(f"{BASE}/api/search/site", data, {"x-auth-token": get_token(True)})
    out = []
    for g in res.get("data", []):
        img = g.get("game_image") or ""
        out.append({
            "id": g.get("game_id"),
            "name": g.get("game_name", "?"),
            "year": g.get("release_world") or "",
            "image": f"{BASE}/games/{img}" if img else "",
            "main": hours(g.get("comp_main")),
            "plus": hours(g.get("comp_plus")),
            "full": hours(g.get("comp_100")),
        })
    return out


def main():
    q = " ".join(sys.argv[1:]).strip()
    if not q:
        print(json.dumps({"ok": True, "results": []}))
        return
    try:
        print(json.dumps({"ok": True, "results": search(q)}))
    except urllib.error.HTTPError as e:
        msg = "Too many searches, wait a minute" if e.code == 429 else f"HTTP {e.code}"
        print(json.dumps({"ok": False, "error": msg}))
    except Exception as e:  # network down, API changed, etc.
        print(json.dumps({"ok": False, "error": str(e)[:120]}))


if __name__ == "__main__":
    main()
