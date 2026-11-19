#!/usr/bin/env python3
"""steamAF helper for the steamAF Plasma widget.

Usage:
  steamaf.py search <CURRENCY> <query...>
  steamaf.py detail <CURRENCY> <appId> <title...>
  steamaf.py hltb '[["<appId>", "<title>"], ...]'   -> {"hours": {"<appId>": <main story h>}}

Prints one JSON object: {"ok": true, ...} or {"ok": false, "error": "..."}.
Only the Python standard library is used.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

API = "https://steamaf.vercel.app"
UA = "steamaf-plasma-widget/0.1"

# code: (steam cc, ITAD country, fraction digits, symbol, thousands sep, decimal sep, symbol after)
CURRENCIES = {
    "USD": ("us", "US", 2, "$", ",", ".", False),
    "CAD": ("ca", "CA", 2, "CA$", ",", ".", False),
    "BRL": ("br", "BR", 2, "R$", ".", ",", False),
    "MXN": ("mx", "MX", 2, "Mex$", ",", ".", False),
    "ARS": ("ar", "AR", 2, "ARS$", ".", ",", False),
    "CLP": ("cl", "CL", 0, "CLP$", ".", ",", False),
    "COP": ("co", "CO", 0, "COL$", ".", ",", False),
    "PEN": ("pe", "PE", 2, "S/", ",", ".", False),
    "UYU": ("uy", "UY", 2, "$U", ".", ",", False),
    "CRC": ("cr", "CR", 0, "₡", ".", ",", False),
    "GBP": ("gb", "GB", 2, "£", ",", ".", False),
    "EUR": ("de", "DE", 2, "€", ".", ",", True),
    "PLN": ("pl", "PL", 2, "zł", " ", ",", True),
    "CHF": ("ch", "CH", 2, "CHF", "'", ".", False),
    "NOK": ("no", "NO", 2, "kr", " ", ",", True),
    "SEK": ("se", "SE", 2, "kr", " ", ",", True),
    "DKK": ("dk", "DK", 2, "kr.", ".", ",", True),
    "CZK": ("cz", "CZ", 2, "Kč", " ", ",", True),
    "HUF": ("hu", "HU", 0, "Ft", " ", ",", True),
    "RON": ("ro", "RO", 2, "lei", ".", ",", True),
    "TRY": ("tr", "TR", 2, "₺", ".", ",", False),
    "UAH": ("ua", "UA", 2, "₴", " ", ",", True),
    "ILS": ("il", "IL", 2, "₪", ",", ".", False),
    "AED": ("ae", "AE", 2, "AED", ",", ".", False),
    "SAR": ("sa", "SA", 2, "SR", ",", ".", False),
    "QAR": ("qa", "QA", 2, "QR", ",", ".", False),
    "KWD": ("kw", "KW", 2, "KD", ",", ".", False),
    "ZAR": ("za", "ZA", 2, "R", " ", ".", False),
    "KZT": ("kz", "KZ", 0, "₸", " ", ",", True),
    "INR": ("in", "IN", 2, "₹", ",", ".", False),
    "PKR": ("pk", "PK", 0, "Rs", ",", ".", False),
    "IDR": ("id", "ID", 0, "Rp", ".", ",", False),
    "MYR": ("my", "MY", 2, "RM", ",", ".", False),
    "PHP": ("ph", "PH", 2, "₱", ",", ".", False),
    "SGD": ("sg", "SG", 2, "S$", ",", ".", False),
    "THB": ("th", "TH", 2, "฿", ",", ".", False),
    "VND": ("vn", "VN", 0, "₫", ".", ",", True),
    "TWD": ("tw", "TW", 0, "NT$", ",", ".", False),
    "HKD": ("hk", "HK", 2, "HK$", ",", ".", False),
    "CNY": ("cn", "CN", 2, "¥", ",", ".", False),
    "JPY": ("jp", "JP", 0, "¥", ",", ".", False),
    "KRW": ("kr", "KR", 0, "₩", ",", ".", False),
    "AUD": ("au", "AU", 2, "A$", ",", ".", False),
    "NZD": ("nz", "NZ", 2, "NZ$", ",", ".", False),
}


CACHE_FILE = os.path.join(os.path.expanduser("~"), ".cache", "steamaf-widget", "hltb.json")
HLTB_TTL = 30 * 86400        # playtime barely changes (steamAF caches it 30 days too)
HLTB_MISS_TTL = 3 * 86400    # "no HLTB entry" answers are re-checked sooner


def get(path, params, timeout=20):
    url = f"{API}{path}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())


def money(value, cur):
    if value is None:
        return None
    _, _, digits, sym, thou, dec, after = CURRENCIES[cur]
    s = f"{float(value):,.{digits}f}"
    s = s.replace(",", "\0").replace(".", dec).replace("\0", thou)
    if digits and s.endswith(dec + "0" * digits):
        s = s[: -(digits + 1)]  # 29.00 -> 29, like Steam
    return f"{s} {sym}" if after else f"{sym} {s}" if len(sym) > 1 else f"{sym}{s}"


def sale_text(sale):
    if not sale or not sale.get("endsAt"):
        return None
    left = sale["endsAt"] / 1000 - time.time()
    if left <= 0:
        return None
    if left < 3600:
        when = f"{max(1, int(left // 60))}m"
    elif left < 86400:
        when = f"{int(left // 3600)}h"
    else:
        when = f"{int(left // 86400)}d"
    kind = (sale.get("kind") or "special").replace("weeklong", "week-long")
    return f"{kind.capitalize()} sale ends in {when}"


def state_of(st):
    """Mirror of steamAF's extensionWidgetState for the bits a widget needs."""
    if not st:
        return "loading"
    if st.get("current") is not None:
        return st.get("status") or "no-history"
    for key, name in (("comingSoon", "coming-soon"), ("isFree", "free"),
                      ("unavailable", "unavailable"), ("confirmedNoPrice", "no-price")):
        if st.get(key):
            return name
    return "loading"


def search(cur, query):
    cc, country = CURRENCIES[cur][0], CURRENCIES[cur][1]
    hits = [h for h in get("/api/search", {"q": query, "cc": cc}).get("results", [])
            if h.get("steamAppID")]
    statuses = {}
    if hits:
        try:
            snap = get("/api/status/snapshot", {
                "appIds": ",".join(h["steamAppID"] for h in hits), "cc": cc, "country": country})
            statuses = snap.get("statuses", {})
            # The snapshot is steamAF's cache, stale rows included (a sale that ended still reads
            # "-70% No rush"). Revalidate the ids it flags, the way steamAF's own pages do; if that
            # is slow or throttled, keep the cached badges.
            stale = [aid for aid, m in (snap.get("meta") or {}).items() if m.get("needsRefresh")]
            if stale:
                try:
                    fresh = get("/api/status", {"appIds": ",".join(stale), "cc": cc, "country": country}, timeout=8)
                    statuses.update({k: v for k, v in fresh.items() if isinstance(v, dict) and state_of(v) != "loading"})
                except Exception:
                    pass
        except Exception:
            pass  # list still works without verdict badges
    out = []
    for h in hits:
        aid = h["steamAppID"]
        st = statuses.get(aid) or {}
        sp = h.get("price") or {}
        current = st.get("current", sp.get("current"))
        disc = st.get("discountPercent") if st.get("current") is not None else sp.get("discountPercent")
        out.append({
            "id": aid,
            "name": h.get("external", "?"),
            "thumb": h.get("thumb") or "",
            "price": money(current, cur) if current is not None else ("Free" if st.get("isFree") else ""),
            "discount": disc or 0,
            "state": state_of(st) if st else "",
        })
    return {"results": out}


def detail(cur, app_id, title):
    def verdict():
        v = get("/api/extension/v1/verdict", {"appId": app_id, "currency": cur})
        if v.get("needsRefresh") or state_of(v) == "loading":
            try:
                fresh = get("/api/extension/v1/verdict",
                            {"appId": app_id, "currency": cur, "refresh": "1"}, timeout=30)
                if state_of(fresh) != "loading":
                    v = fresh
            except Exception:
                pass  # keep the cached snapshot
        return v

    def hltb():
        try:
            d = get("/api/hltb", {"appId": app_id, "title": title}, timeout=25).get("data") or {}
        except Exception:
            return None
        h = half_hours
        return {"main": h(d.get("main")), "plus": h(d.get("mainPlus")), "full": h(d.get("complete"))} if d else None

    def header():
        try:
            cc, country = CURRENCIES[cur][0], CURRENCIES[cur][1]
            s = get("/api/status/snapshot", {"appIds": app_id, "cc": cc, "country": country})
            return (s.get("statuses", {}).get(app_id) or {}).get("headerImage")
        except Exception:
            return None

    def media():
        # Trailers (HLS streams) + screenshots from the Steam store; shown after the cover.
        try:
            url = ("https://store.steampowered.com/api/appdetails?" +
                   urllib.parse.urlencode({"appids": app_id, "filters": "movies,screenshots", "l": "english"}))
            req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=15) as resp:
                data = (json.loads(resp.read().decode()).get(str(app_id)) or {}).get("data") or {}
        except Exception:
            return []
        out = []
        for m in (data.get("movies") or [])[:6]:
            src = m.get("hls_h264") or (m.get("mp4") or {}).get("max") or (m.get("webm") or {}).get("max")
            if src:
                out.append({"type": "video", "name": m.get("name") or "Trailer",
                            "thumb": m.get("thumbnail") or "", "src": src})
        for sc in (data.get("screenshots") or [])[:20]:
            if sc.get("path_full"):
                out.append({"type": "image", "name": "Screenshot",
                            "thumb": sc.get("path_thumbnail") or sc["path_full"], "src": sc["path_full"]})
        return out

    with ThreadPoolExecutor(4) as ex:
        fv, fh, fi, fm = ex.submit(verdict), ex.submit(hltb), ex.submit(header), ex.submit(media)
        v, hl, img, med = fv.result(), fh.result(), fi.result(), fm.result()

    return {
        "id": app_id,
        "state": state_of(v),
        "image": img or f"https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/{app_id}/header.jpg",
        "current": money(v.get("current"), cur),
        "original": money(v.get("original"), cur),
        "lowest": money(v.get("lowest"), cur),
        "typical": money(v.get("typicalSalePrice"), cur),
        "discount": v.get("discountPercent") or 0,
        "sale": sale_text(v.get("sale")),
        "hltb": hl,
        "media": med,
    }


def half_hours(x):
    return round(float(x) * 2) / 2 if x else 0


def main_hours(pairs):
    """Main-story hours for many games at once. Uses a small local cache so repeated searches
    don't hit steamAF's /api/hltb (it is rate limited per IP) for games already looked up."""
    try:
        with open(CACHE_FILE) as f:
            cache = json.load(f)
    except Exception:
        cache = {}
    now = time.time()
    out, todo = {}, []
    for app_id, title in pairs:
        c = cache.get(app_id)
        if c and now - c["t"] < (HLTB_TTL if c["h"] else HLTB_MISS_TTL):
            out[app_id] = c["h"]
        else:
            todo.append((app_id, title))

    def one(pair):
        app_id, title = pair
        try:
            r = get("/api/hltb", {"appId": app_id, "title": title}, timeout=25)
        except Exception:
            return app_id, None  # rate limited / upstream down: try again next search
        if r.get("pending"):
            return app_id, None
        return app_id, half_hours((r.get("data") or {}).get("main"))

    if todo:
        with ThreadPoolExecutor(4) as ex:
            for app_id, h in ex.map(one, todo):
                if h is None:
                    continue
                out[app_id] = h
                cache[app_id] = {"h": h, "t": now}
        try:
            os.makedirs(os.path.dirname(CACHE_FILE), exist_ok=True)
            with open(CACHE_FILE, "w") as f:
                json.dump(cache, f)
        except Exception:
            pass
    return {"hours": out}


def main():
    args = sys.argv[1:]
    if len(args) == 2 and args[0] == "hltb":
        try:
            pairs = [(str(i), str(t)) for i, t in json.loads(args[1])][:20]
            print(json.dumps({"ok": True, **main_hours(pairs)}))
        except Exception as e:
            print(json.dumps({"ok": False, "error": str(e)[:120]}))
        return
    if len(args) < 3 or args[0] not in ("search", "detail"):
        print(json.dumps({"ok": False, "error": "usage: search|detail|hltb ..."}))
        return
    cmd, cur = args[0], args[1].upper()
    if cur not in CURRENCIES:
        cur = "USD"
    try:
        if cmd == "search":
            res = search(cur, " ".join(args[2:]).strip())
        else:
            res = detail(cur, args[2], " ".join(args[3:]).strip())
        print(json.dumps({"ok": True, "currency": cur, **res}))
    except urllib.error.HTTPError as e:
        msg = "Too many requests, wait a minute" if e.code == 429 else f"steamAF error (HTTP {e.code})"
        print(json.dumps({"ok": False, "error": msg}))
    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e)[:120]}))


if __name__ == "__main__":
    main()
