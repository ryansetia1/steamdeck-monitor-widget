"""RLog island for the Deck Monitor card: Playing, Up next and finishes from RLog.

RLog (https://github.com/ryansetia1/rlog) serves a ready-made summary at /api/widget,
guarded by a personal token. The token is read from ~/.config/rlog/widget.env
(WIDGET_TOKEN=...), never from the widget config, so it stays out of the repo and
of Plasma's settings. The last good answer is kept on disk, so the island still shows
something offline or while the request is in flight.
"""
import json
import os
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

APP = os.environ.get('RLOG_URL', 'https://r-log.vercel.app')
URL = APP + '/api/widget'
MEDIA_URL = APP + '/api/igdb'   # public, CDN-cached: Steam trailers/screenshots, else IGDB's
ENV_PATH = os.path.expanduser('~/.config/rlog/widget.env')
CACHE_PATH = os.path.expanduser('~/.cache/deck-monitor/rlog.json')
FRESH_FOR = 10 * 60          # seconds before a cached summary is fetched again
RETRY_AFTER = 60             # after a failure, wait this long before trying again

_lock = threading.Lock()
_state = {'data': None, 'fetched_at': 0, 'error': '', 'tried_at': 0}


def _token():
    try:
        with open(ENV_PATH) as f:
            for line in f:
                k, _, v = line.strip().partition('=')
                if k == 'WIDGET_TOKEN' and v:
                    return v.strip().strip('"\'')
    except OSError:
        pass
    return ''


def _load_cache():
    try:
        with open(CACHE_PATH) as f:
            c = json.load(f)
        _state['data'] = c.get('data')
        _state['fetched_at'] = c.get('fetched_at', 0)
    except (OSError, ValueError):
        pass


def _save_cache():
    try:
        os.makedirs(os.path.dirname(CACHE_PATH), exist_ok=True)
        tmp = CACHE_PATH + '.tmp'
        with open(tmp, 'w') as f:
            json.dump({'data': _state['data'], 'fetched_at': _state['fetched_at']}, f)
        os.replace(tmp, CACHE_PATH)
    except OSError:
        pass


def _fetch(query):
    token = _token()
    if not token:
        raise RuntimeError('No RLog token: add WIDGET_TOKEN to ~/.config/rlog/widget.env')
    return _get(URL + '?' + urllib.parse.urlencode(query), {'Authorization': 'Bearer ' + token})


def _get(url, headers=None):
    req = urllib.request.Request(url, headers=dict(headers or {}, **{'User-Agent': 'deck-monitor'}))
    try:
        with urllib.request.urlopen(req, timeout=12) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        try:
            msg = json.load(e).get('error') or ''
        except Exception:
            msg = ''
        raise RuntimeError(msg or 'RLog answered HTTP %d' % e.code)
    except urllib.error.URLError:
        raise RuntimeError("Can't reach RLog (offline?)")


def summary(force=False):
    """{ok, data, fetched_at, stale, error}. Fetches when the copy is older than FRESH_FOR (or forced)."""
    with _lock:
        if _state['fetched_at'] == 0 and _state['data'] is None:
            _load_cache()
        now = time.time()
        old = now - _state['fetched_at'] > FRESH_FOR
        may_try = force or now - _state['tried_at'] > RETRY_AFTER
        if (old or force) and may_try:
            _state['tried_at'] = now
            try:
                _state['data'] = _fetch({'today': time.strftime('%Y-%m-%d')})
                _state['fetched_at'] = now
                _state['error'] = ''
                _save_cache()
            except Exception as e:
                _state['error'] = str(e)[:160]
        data = _state['data']
        return {
            'ok': data is not None,
            'data': data,
            'fetched_at': _state['fetched_at'],
            'stale': data is not None and time.time() - _state['fetched_at'] > FRESH_FOR,
            'error': _state['error'],
        }


_details = {}   # item id -> (fetched_at, detail)
_media = {}     # (igdb, steam) -> (fetched_at, items)


def detail(item_id):
    """{ok, data, error}: one game's page for the island (cached 10 min per game)."""
    if not item_id or len(item_id) > 64 or not all(c.isalnum() or c in '-_' for c in item_id):
        return {'ok': False, 'data': None, 'error': 'Invalid game'}
    hit = _details.get(item_id)
    if hit and time.time() - hit[0] < FRESH_FOR:
        return {'ok': True, 'data': hit[1], 'error': ''}
    try:
        d = _fetch({'item': item_id})
        _details[item_id] = (time.time(), d)
        return {'ok': True, 'data': d, 'error': ''}
    except Exception as e:
        if hit:   # offline: the last copy beats an error
            return {'ok': True, 'data': hit[1], 'error': str(e)[:160]}
        return {'ok': False, 'data': None, 'error': str(e)[:160]}


def media(igdb, steam):
    """{ok, media}: trailers then screenshots, shaped for MediaCarousel.qml ({type, name, thumb, src}).
    YouTube trailers (IGDB) are left out: the theater plays HLS streams, not YouTube."""
    igdb = igdb if igdb.isdigit() else ''
    steam = steam if steam.isdigit() else ''
    if not (igdb or steam):
        return {'ok': True, 'media': []}
    key = (igdb, steam)
    hit = _media.get(key)
    if hit and time.time() - hit[0] < 6 * 3600:
        return {'ok': True, 'media': hit[1]}
    try:
        raw = _get(MEDIA_URL + '?' + urllib.parse.urlencode({'op': 'media', 'id': igdb, 'steam': steam})).get('media') or []
    except Exception as e:
        return {'ok': False, 'media': hit[1] if hit else [], 'error': str(e)[:160]}
    items, shots = [], 0
    for m in raw:
        if m.get('kind') == 'video':
            items.append({'type': 'video', 'name': 'Trailer', 'thumb': m.get('thumb', ''), 'src': m.get('full', '')})
        elif m.get('kind') == 'shot':
            shots += 1
            items.append({'type': 'image', 'name': 'Screenshot %d' % shots, 'thumb': m.get('thumb', ''), 'src': m.get('full', '')})
    _media[key] = (time.time(), items)
    return {'ok': True, 'media': items}


if __name__ == '__main__':
    import sys
    print(json.dumps(summary(force='--force' in sys.argv), indent=1)[:2000])
