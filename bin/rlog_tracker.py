"""What's running on the Deck, for the RLog island (RLog docs/PLAN.md "Deck Monitor integration", D2/D3).

- Detects the running game: Steam games by the `AppId=` Steam puts on the game's reaper
  process; emulator games by an emulator process whose arguments name a ROM (EmuDeck's
  `roms/<system>/...` folders give the platform; RPCS3/Vita3K/shadPS4 titles come from PARAM.SFO).
- Matches it to a game in the RLog library (Steam app id, else normalised title + platform).
  Anything unsure stays unmatched, which the island treats like any palate cleanser.
- Logs sessions on this Deck only (~/.local/share/deck-monitor/rlog-sessions.json).
- D3: sends the total emulator minutes per matched game to RLog (Steam games are already
  counted by Steam's own playtime).
- Prompts: "Finished?" for a Playing game past HLTB main x your pace, "Move to Playing?" for
  a longer non-Playing game you've played half of since its status last changed. Each is a
  quiet chip in the island, snoozable or muted per game (~/.config/deck-monitor/rlog-prompts.json).
"""
import json
import os
import re
import threading
import time
import unicodedata

import rlog_island

DATA_DIR = os.path.expanduser('~/.local/share/deck-monitor')
SESSIONS_PATH = os.path.join(DATA_DIR, 'rlog-sessions.json')
PROMPTS_PATH = os.path.expanduser('~/.config/deck-monitor/rlog-prompts.json')
ALIASES_PATH = os.path.expanduser('~/.config/rlog/aliases.json')   # {"rom or game title": "<RLog item id>"}

TICK = 20                 # seconds between process scans
GONE_AFTER = 60           # a game missing this long ends its session
MIN_SESSION_MIN = 1       # shorter sessions are dropped
CATALOG_EVERY = 30 * 60
PUSH_EVERY = 10 * 60
REAL_STEAM_APP = 100_000_000   # non-Steam shortcuts get huge generated app ids

# EmuDeck roms/<system> folder -> RLog platform name
SYSTEMS = {
    'psx': 'PS1', 'ps2': 'PS2', 'ps3': 'PS3', 'psp': 'PSP', 'psvita': 'PS Vita', 'ps4': 'PS4',
    'gc': 'GameCube', 'gamecube': 'GameCube', 'wii': 'Wii', 'wiiu': 'Wii U', 'switch': 'Switch',
    'n64': 'N64', 'snes': 'SNES', 'sfc': 'SNES', 'snesna': 'SNES', 'sneshd': 'SNES',
    'nes': 'NES', 'famicom': 'NES', 'fds': 'NES', 'gb': 'Game Boy', 'gbc': 'GBC', 'gba': 'GBA',
    'nds': 'DS', '3ds': '3DS', 'n3ds': '3DS', 'virtualboy': 'Virtual Boy',
    'genesis': 'Mega Drive', 'genesiswide': 'Mega Drive', 'megadrive': 'Mega Drive', 'megadrivejp': 'Mega Drive',
    'mastersystem': 'Master System', 'gamegear': 'Game Gear', 'segacd': 'Sega CD', 'megacd': 'Sega CD',
    'megacdjp': 'Sega CD', 'saturn': 'Saturn', 'saturnjp': 'Saturn', 'dreamcast': 'Dreamcast',
    'xbox': 'Xbox', 'xbox360': 'Xbox 360', 'arcade': 'Arcade', 'mame': 'Arcade', 'fbneo': 'Arcade',
    'fba': 'Arcade', 'cps': 'Arcade', 'cps1': 'Arcade', 'cps2': 'Arcade', 'cps3': 'Arcade',
    'naomi': 'Arcade', 'atomiswave': 'Arcade', 'neogeo': 'Neo Geo', 'neogeocd': 'Neo Geo',
    'pcengine': 'PC Engine', 'pcenginecd': 'PC Engine', 'tg16': 'PC Engine', 'tg-cd': 'PC Engine',
    'atari2600': 'Atari 2600',
}
# RLog platform name -> IGDB abbreviations an item's `platforms` may use
IGDB_NAMES = {
    'PS1': {'PS1', 'PS'}, 'PS Vita': {'Vita'}, 'GameCube': {'NGC'}, 'Wii U': {'WiiU'},
    'Game Boy': {'GB'}, 'DS': {'NDS'}, 'Mega Drive': {'Genesis/MegaDrive', 'Genesis', 'MegaDrive'},
    'Master System': {'SMS'}, 'Sega CD': {'SegaCD'}, 'Dreamcast': {'DC'}, 'Xbox': {'XBOX'},
    'Xbox 360': {'X360'}, 'PC Engine': {'TG16'}, 'Neo Geo': {'NEOGEOAES', 'NEOGEOMVS'},
    'Atari 2600': {'Atari2600'}, 'Virtual Boy': {'VB'},
}
EMULATORS = ('rpcs3', 'pcsx2', 'duckstation', 'dolphin', 'retroarch', 'ppsspp', 'cemu', 'xemu',
             'vita3k', 'shadps4', 'ryujinx', 'azahar', 'citra', 'lime3ds', 'melonds', 'mgba',
             'flycast', 'yuzu', 'eden', 'citron', 'sudachi', 'primehack', 'mame', 'xenia', 'mesen',
             'snes9x', 'bsnes', 'mupen64', 'rmg', 'redream', 'scummvm', 'dosbox', 'model2')
ROM_EXT = re.compile(r'\.(chd|iso|cso|rvz|gcz|wbfs|wua|wux|rpx|nsp|xci|3ds|cia|cci|nds|gba|gbc|gb|sfc|smc|nes|'
                     r'fds|z64|n64|v64|md|gen|smd|sms|gg|32x|cue|bin|img|pbp|zip|7z|elf|xex|pkg|lnk|m3u|cdi|gdi)$', re.I)
SYSTEM_DIR = re.compile(r'/roms/([^/]+)/')

_lock = threading.Lock()
_catalog = {'games': [], 'pace': None, 'at': 0}
_state = {'sessions': [], 'totals': {}, 'sent': {}}
_prompts = {}
_live = {}      # key -> {det, start, last_seen, min}
_last_push = 0.0
_push_error = ''


# ── Titles ──────────────────────────────────────────────────────────────────

ROMAN = {'ii': '2', 'iii': '3', 'iv': '4', 'v': '5', 'vi': '6', 'vii': '7', 'viii': '8', 'ix': '9', 'x': '10'}


def normalize(title):
    """'Pokémon: Red Version™' -> 'pokemon red version'; roman numerals and 'zero' read as digits."""
    t = re.sub(r'[\u2122\u00ae\u00a9]', '', title or '')      # ™ ® © (NFKD would spell ™ as "TM")
    t = unicodedata.normalize('NFKD', t)
    t = ''.join(c for c in t if not unicodedata.combining(c)).lower()
    t = t.replace('&', ' and ')
    t = re.sub(r'[^a-z0-9]+', ' ', t).split()
    t = [ROMAN.get(w, '0' if w == 'zero' else w) for w in t]
    if t and t[0] == 'the':
        t = t[1:]
    return ' '.join(t)


def rom_title(path):
    """'01. Legend of Zelda, The - A Link to the Past (USA) (Rev 1).sfc' -> 'The Legend of Zelda - A Link to the Past'."""
    name = os.path.basename(path.rstrip('/'))
    name = ROM_EXT.sub('', name)
    name = re.sub(r'^\d{1,3}\.\s*', '', name)               # "01. " list numbers
    name = re.sub(r'\s*[\(\[][^\)\]]*[\)\]]', '', name)     # (USA) (Disc 1) [0100...][v0]
    name = name.strip(' -_')
    m = re.match(r'^(.*?), (The|A|An)( - .*)?$', name)      # No-Intro "Title, The - Sub"
    if m:
        name = '%s %s%s' % (m.group(2), m.group(1), m.group(3) or '')
    return name


def sfo_title(path):
    """TITLE from a PlayStation PARAM.SFO next to (or above) a booted EBOOT/game folder."""
    d = path if os.path.isdir(path) else os.path.dirname(path)
    for _ in range(4):
        for cand in (os.path.join(d, 'PARAM.SFO'), os.path.join(d, 'PS3_GAME', 'PARAM.SFO'), os.path.join(d, 'sce_sys', 'param.sfo')):
            if os.path.isfile(cand):
                try:
                    return _read_sfo(cand).get('TITLE')
                except Exception:
                    return None
        d = os.path.dirname(d)
    return None


def _read_sfo(path):
    import struct
    with open(path, 'rb') as f:
        data = f.read(64 * 1024)
    if data[:4] != b'\x00PSF':
        return {}
    key_tab, data_tab, n = struct.unpack_from('<III', data, 8)
    out = {}
    for i in range(n):
        k_off, fmt, length, _max, d_off = struct.unpack_from('<HHIII', data, 20 + i * 16)
        key = data[key_tab + k_off:data.index(b'\x00', key_tab + k_off)].decode('utf-8', 'replace')
        raw = data[data_tab + d_off:data_tab + d_off + length]
        if fmt in (0x0204, 0x0004):
            out[key] = raw.rstrip(b'\x00').decode('utf-8', 'replace')
    return out


_steam_names = {}


def steam_name(appid):
    """A Steam game's name from its appmanifest, for games not in RLog."""
    if appid in _steam_names:
        return _steam_names[appid]
    name = None
    roots = [os.path.expanduser('~/.local/share/Steam/steamapps')]
    try:
        with open(roots[0] + '/libraryfolders.vdf') as f:
            roots += [p + '/steamapps' for p in re.findall(r'"path"\s+"([^"]+)"', f.read())]
    except OSError:
        pass
    for r in roots:
        try:
            with open('%s/appmanifest_%d.acf' % (r, appid)) as f:
                m = re.search(r'"name"\s+"([^"]+)"', f.read())
                if m:
                    name = m.group(1)
                    break
        except OSError:
            continue
    _steam_names[appid] = name
    return name


# ── Detection ───────────────────────────────────────────────────────────────

def _cmdlines():
    for pid in os.listdir('/proc'):
        if not pid.isdigit():
            continue
        try:
            with open('/proc/%s/cmdline' % pid, 'rb') as f:
                raw = f.read()
        except OSError:
            continue
        if raw:
            yield [a.decode('utf-8', 'replace') for a in raw.split(b'\x00') if a]


def detect(cmdlines=None):
    """Games running now: [{key, kind, title, platform, steam_appid}] (one per game)."""
    found = {}
    for args in (cmdlines if cmdlines is not None else _cmdlines()):
        joined = ' '.join(args)
        m = re.search(r'\bAppId=(\d+)', joined)
        if m and ('SteamLaunch' in joined or 'reaper' in args[0]):
            appid = int(m.group(1))
            if 0 < appid < REAL_STEAM_APP:
                found['steam:%d' % appid] = {'key': 'steam:%d' % appid, 'kind': 'steam', 'steam_appid': appid,
                                             'title': steam_name(appid) or 'Steam app %d' % appid, 'platform': 'Steam'}
            continue
        low = joined.lower()
        if not any(e in low for e in EMULATORS):
            continue
        for a in reversed(args[1:]):
            # A ROM argument is one path (not a shell script that mentions one) to a file or game folder.
            if not a.startswith('/') or '\n' in a or not os.path.exists(a):
                continue
            sm = SYSTEM_DIR.search(a)
            is_rom = bool(sm) or bool(ROM_EXT.search(a)) or a.endswith('EBOOT.BIN') or a.endswith('eboot.bin')
            if not is_rom:
                continue
            system = sm.group(1).lower() if sm else ''
            platform = SYSTEMS.get(system)
            title = None
            if 'rpcs3' in low or 'vita3k' in low or 'shadps4' in low or a.lower().endswith('eboot.bin'):
                title = sfo_title(a)
                platform = platform or ('PS3' if 'rpcs3' in low else 'PS Vita' if 'vita3k' in low else 'PS4' if 'shadps4' in low else None)
            title = title or rom_title(a)
            if not title:
                continue
            key = 'emu:%s:%s' % (platform or system or '?', normalize(title))
            found[key] = {'key': key, 'kind': 'emu', 'steam_appid': None, 'title': title, 'platform': platform}
            break
    return list(found.values())


# ── Matching ────────────────────────────────────────────────────────────────

def _platform_ok(game, platform):
    names = {platform} | IGDB_NAMES.get(platform, set())
    known = ([game['platform']] if game.get('platform') else []) + list(game.get('platforms') or [])
    return not known or any(p in names for p in known)


def _aliases():
    try:
        with open(ALIASES_PATH) as f:
            return {normalize(k): v for k, v in json.load(f).items()}
    except (OSError, ValueError):
        return {}


def match(det, games, aliases=None):
    """The RLog game for a detection, or None when there's no single sure answer."""
    if det.get('steam_appid'):
        hits = [g for g in games if g.get('steam_appid') == det['steam_appid']]
        return hits[0] if len(hits) == 1 else None
    norm = normalize(det['title'])
    alias = (aliases if aliases is not None else _aliases()).get(norm)
    if alias:
        hits = [g for g in games if g['item_id'] == alias]
        return hits[0] if hits else None
    hits = [g for g in games if normalize(g['title']) == norm]
    if det.get('platform'):
        hits = [g for g in hits if _platform_ok(g, det['platform'])]
    return hits[0] if len(hits) == 1 else None


# ── State on disk ───────────────────────────────────────────────────────────

def _load():
    try:
        with open(SESSIONS_PATH) as f:
            d = json.load(f)
        _state.update({k: d.get(k, v) for k, v in _state.items()})
    except (OSError, ValueError):
        pass
    try:
        with open(PROMPTS_PATH) as f:
            _prompts.update(json.load(f))
    except (OSError, ValueError):
        pass


def _write(path, data):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + '.tmp'
        with open(tmp, 'w') as f:
            json.dump(data, f)
        os.replace(tmp, path)
    except OSError:
        pass


def _save():
    _state['sessions'] = _state['sessions'][-1000:]
    _write(SESSIONS_PATH, _state)


# ── Catalog ─────────────────────────────────────────────────────────────────

CATALOG_CACHE = os.path.expanduser('~/.cache/deck-monitor/rlog-catalog.json')


def _refresh_catalog(force=False):
    if not force and time.time() - _catalog['at'] < CATALOG_EVERY:
        return
    try:
        c = rlog_island._fetch({'catalog': '1'})
        if not isinstance(c.get('games'), list):
            raise RuntimeError('RLog has no catalog yet')
        _catalog.update(games=c.get('games', []), pace=c.get('pace'), at=time.time())
        _write(CATALOG_CACHE, {'games': _catalog['games'], 'pace': _catalog['pace']})
    except Exception:
        _catalog['at'] = time.time() - CATALOG_EVERY + 120   # retry in two minutes
        if not _catalog['games']:
            try:
                with open(CATALOG_CACHE) as f:
                    c = json.load(f)
                _catalog.update(games=c.get('games', []), pace=c.get('pace'))
            except (OSError, ValueError):
                pass


# ── The loop ────────────────────────────────────────────────────────────────

def _end(key, now):
    s = _live.pop(key)
    minutes = int(round(s['min']))
    if minutes < MIN_SESSION_MIN:
        return
    d, g = s['det'], s.get('game')
    _state['sessions'].append({
        'title': d['title'], 'platform': d['platform'], 'kind': d['kind'], 'item_id': g['item_id'] if g else None,
        'start': int(s['start'] * 1000), 'end': int(s['last_seen'] * 1000), 'min': minutes,
    })
    # D3: emulator time for a matched game (Steam counts its own games)
    if g and d['kind'] == 'emu':
        t = _state['totals'].setdefault(g['item_id'], {'min': 0, 'last': 0})
        t['min'] += minutes
        t['last'] = int(s['last_seen'] * 1000)
    _save()


def tick(now=None, mono=None, cmdlines=None):
    now = now or time.time()
    mono = mono if mono is not None else time.monotonic()
    with _lock:
        _refresh_catalog()
        seen = set()
        for det in detect(cmdlines):
            k = det['key']
            seen.add(k)
            s = _live.get(k)
            if s is None:
                game = match(det, _catalog['games'])
                _live[k] = {'det': det, 'game': game, 'start': now, 'last_seen': now, 'mono': mono, 'min': 0.0}
                continue
            # Count wall time between scans, capped so a suspended Deck doesn't add hours.
            s['min'] += min(max(mono - s['mono'], 0), 3 * TICK) / 60.0
            s['mono'] = mono
            s['last_seen'] = now
            if s.get('game') is None and _catalog['games']:
                s['game'] = match(det, _catalog['games'])
        for k in [k for k, s in _live.items() if k not in seen and now - s['last_seen'] > GONE_AFTER]:
            _end(k, now)
        for k, s in _live.items():
            if k not in seen:
                s['mono'] = mono   # missing for a moment: don't count the gap
    _maybe_push(now)


def _maybe_push(now, force=False):
    global _last_push, _push_error
    if not force and now - _last_push < PUSH_EVERY:
        return
    _last_push = now
    with _lock:
        due = [{'item_id': i, 'minutes': t['min'], 'last_played': t['last']}
               for i, t in _state['totals'].items() if _state['sent'].get(i) != t['min']]
    if not due:
        return
    try:
        rlog_island._post({'plays': due[:200]})
        with _lock:
            for p in due[:200]:
                _state['sent'][p['item_id']] = p['minutes']
            _save()
        _push_error = ''
        rlog_island.invalidate()
    except Exception as e:
        _push_error = str(e)[:160]


def loop():
    with _lock:
        _load()
    while True:
        try:
            tick()
        except Exception:
            pass
        time.sleep(TICK)


# ── What the island asks ────────────────────────────────────────────────────

def _muted(item_id, kind, now):
    p = _prompts.get(item_id, {}).get(kind)
    return bool(p) and (p.get('never') or p.get('until', 0) > now * 1000)


def _local_minutes(item_id, since_ms=0):
    """Minutes logged on this Deck for a game (ended sessions after `since_ms`, plus the live one)."""
    total = sum(s['min'] for s in _state['sessions'] if s.get('item_id') == item_id and s['start'] >= since_ms)
    total += sum(s['min'] for s in _live.values() if s.get('game') and s['game']['item_id'] == item_id)
    return total


def now_state(now=None):
    """{running, prompts, push_error} for the island."""
    now = now or time.time()
    with _lock:
        pace = (_catalog.get('pace') or {}).get('ratio') or 1.0
        running = None
        if _live:
            s = max(_live.values(), key=lambda s: s['last_seen'] - s['start'])
            g, d = s.get('game'), s['det']
            running = {
                'title': g['title'] if g else d['title'], 'platform': d['platform'] or (g or {}).get('platform'),
                'kind': d['kind'], 'minutes': int(round(s['min'])), 'item_id': g['item_id'] if g else None,
                'entry_id': g['entry_id'] if g else None, 'status': g['status'] if g else None,
                'link': g['link'] if g else None,
            }
        prompts = []
        for g in _catalog['games']:
            main = g.get('main_h') or 0
            if not main:
                continue
            target = main * pace
            if g['status'] == 'playing' and not _muted(g['item_id'], 'finished', now):
                unsent = (_state['totals'].get(g['item_id'], {}).get('min', 0) - (_state['sent'].get(g['item_id']) or 0)) / 60.0
                played = (g.get('played_h') or 0) + max(unsent, 0) + (_local_minutes(g['item_id'], int(now * 1000)) / 60.0)
                if played > target:
                    prompts.append({'kind': 'finished', 'item_id': g['item_id'], 'entry_id': g['entry_id'], 'title': g['title'],
                                    'played_h': round(played, 1), 'main_h': main, 'pace': pace, 'target_h': round(target, 1),
                                    'link': g['link']})
            elif g['status'] not in ('playing', 'completed', 'dropped') and main >= 5 and not _muted(g['item_id'], 'playing', now):
                fresh = _local_minutes(g['item_id'], g.get('status_at') or 0) / 60.0
                if fresh >= 0.5 * target:
                    prompts.append({'kind': 'playing', 'item_id': g['item_id'], 'entry_id': g['entry_id'], 'title': g['title'],
                                    'played_h': round(fresh, 1), 'main_h': main, 'pace': pace, 'target_h': round(target, 1),
                                    'link': g['link']})
        return {'running': running, 'prompts': prompts, 'push_error': _push_error}


def answer(item_id, kind, action, days=0):
    """Snooze ('snooze', days) or mute ('never') one prompt for one game."""
    if kind not in ('finished', 'playing') or not item_id or len(item_id) > 64:
        return False
    with _lock:
        entry = _prompts.setdefault(item_id, {})
        if action == 'never':
            entry[kind] = {'never': True}
        elif action == 'snooze' and days in (3, 7, 30):
            entry[kind] = {'until': int((time.time() + days * 86400) * 1000)}
        else:
            return False
        _write(PROMPTS_PATH, _prompts)
    return True
