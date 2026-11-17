"""Play a game from the RLog island (RLog docs/PLAN.md "Deck Monitor integration").

- Steam games: steam://rungameid/<appid>, only when the game is installed.
- Emulator games: the ROM is found by indexing ES-DE's ROM folder and matching each ROM to the
  RLog library the same way the tracker matches running games. It is launched with exactly the
  command ES-DE would use: the system's command (bundled es_systems.xml, overridden by
  ~/ES-DE/custom_systems), the emulator you picked for that system or that game (gamelist.xml
  <alternativeEmulator> / <altemulator>), and %EMULATOR_x% / %CORE_x% resolved through the find
  rules (EmuDeck's custom rules point at its launcher scripts).
- PS3 games installed in RPCS3 (dev_hdd0/game/*) run through the RPCS3 emulator with --no-gui EBOOT.BIN.
"""
import glob
import os
import re
import shlex
import shutil
import subprocess
import tempfile
import threading
import time
import xml.etree.ElementTree as ET

import rlog_tracker as tracker

ESDE_HOME = os.path.expanduser('~/ES-DE')
ESDE_APPIMAGES = ['~/Applications/ES-DE*.AppImage']
CACHE_DIR = os.path.expanduser('~/.cache/deck-monitor/es-de')
EXT_RANK = {'.m3u': 0, '.cue': 1, '.gdi': 1, '.chd': 2, '.iso': 3, '.rvz': 3}   # lower = preferred; .bin last

_lock = threading.Lock()
_index = {'roms': {}, 'at': 0, 'catalog_at': -1}


# ── ES-DE configuration ─────────────────────────────────────────────────────

def _bundled():
    """ES-DE's own es_systems.xml / es_find_rules.xml, extracted once from the AppImage (redone when it changes)."""
    imgs = sorted(p for g in ESDE_APPIMAGES for p in glob.glob(os.path.expanduser(g)))
    if not imgs:
        return None
    img = imgs[0]
    stamp = os.path.join(CACHE_DIR, 'stamp')
    sig = '%s %d' % (img, os.path.getmtime(img))
    try:
        with open(stamp) as f:
            if f.read() == sig:
                return CACHE_DIR
    except OSError:
        pass
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run([img, '--appimage-extract', 'usr/share/es-de/resources/systems/linux/*'], cwd=tmp,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
        src = os.path.join(tmp, 'squashfs-root', 'usr', 'share', 'es-de', 'resources', 'systems', 'linux')
        if not os.path.isfile(os.path.join(src, 'es_systems.xml')):
            return None
        os.makedirs(CACHE_DIR, exist_ok=True)
        for name in ('es_systems.xml', 'es_find_rules.xml'):
            shutil.copy(os.path.join(src, name), os.path.join(CACHE_DIR, name))
    with open(stamp, 'w') as f:
        f.write(sig)
    return CACHE_DIR


def _xml(path):
    try:
        return ET.parse(path).getroot()
    except (OSError, ET.ParseError):
        return None


def rom_root():
    # es_settings.xml has no root element (not parseable as one XML document): read the line.
    try:
        with open(os.path.join(ESDE_HOME, 'settings', 'es_settings.xml')) as f:
            m = re.search(r'name="ROMDirectory"\s+value="([^"]+)"', f.read())
        if m:
            return os.path.expanduser(m.group(1))
    except OSError:
        pass
    return os.path.expanduser('~/ROMs')


def systems(bundled_dir):
    """System name -> [(label, command)], custom_systems replacing bundled ones."""
    out = {}
    for path in (os.path.join(bundled_dir, 'es_systems.xml') if bundled_dir else None,
                 os.path.join(ESDE_HOME, 'custom_systems', 'es_systems.xml')):
        root = _xml(path) if path else None
        if root is None:
            continue
        for s in root.findall('system'):
            cmds = [(c.get('label') or '', (c.text or '').strip()) for c in s.findall('command')]
            if s.findtext('name') and cmds:
                out[s.findtext('name')] = cmds
    return out


def find_rules(bundled_dir):
    """('emulator'|'core', NAME) -> [rule entries in order], custom rules first."""
    rules = {}
    for path in (os.path.join(ESDE_HOME, 'custom_systems', 'es_find_rules.xml'),
                 os.path.join(bundled_dir, 'es_find_rules.xml') if bundled_dir else None):
        root = _xml(path) if path else None
        if root is None:
            continue
        for kind in ('emulator', 'core'):
            for e in root.findall(kind):
                lst = rules.setdefault((kind, e.get('name')), [])
                for r in e.findall('rule'):
                    lst += [(r.get('type'), (x.text or '').strip()) for x in r.findall('entry')]
    return rules


def resolve(rules, kind, name):
    for typ, entry in rules.get((kind, name), []):
        if typ == 'systempath' and kind == 'emulator':
            found = shutil.which(entry) or shutil.which(entry, path=os.path.expanduser('~/.local/share/flatpak/exports/bin') + ':/var/lib/flatpak/exports/bin')
            if found:
                return found
        elif typ in ('staticpath', 'corepath'):
            for p in sorted(glob.glob(os.path.expanduser(entry))):
                if os.path.exists(p):
                    return p
    return None


def chosen_label(system, rom_path):
    """The emulator picked for this game (<altemulator>) or this system (<alternativeEmulator>), if any."""
    # gamelist.xml has two top-level elements (<alternativeEmulator> and <gameList>): read it as text.
    try:
        with open(os.path.join(ESDE_HOME, 'gamelists', system, 'gamelist.xml'), encoding='utf-8') as f:
            text = f.read()
    except OSError:
        return None
    import html
    name = os.path.basename(rom_path)
    for g in re.findall(r'<game>(.*?)</game>', text, re.S):
        p = re.search(r'<path>(.*?)</path>', g, re.S)
        a = re.search(r'<altemulator>(.*?)</altemulator>', g, re.S)
        if p and a and os.path.basename(html.unescape(p.group(1)).rstrip('/')) == name:
            return html.unescape(a.group(1)).strip()
    m = re.search(r'<alternativeEmulator>\s*<label>(.*?)</label>', text, re.S)
    return html.unescape(m.group(1)).strip() if m else None


_cfg_cache = {'at': 0, 'cfg': None}


def _cfg():
    """(bundled dir, systems, find rules), parsed at most once a minute."""
    if _cfg_cache['cfg'] is None or time.time() - _cfg_cache['at'] > 60:
        b = _bundled()
        _cfg_cache.update(cfg=(b, systems(b), find_rules(b)), at=time.time())
    return _cfg_cache['cfg']


def es_command(system, rom_path, cfg=None):
    """(argv, cwd) the way ES-DE would launch this ROM, or (None, reason)."""
    bundled_dir, all_systems, rules = cfg or _cfg()
    cmds = all_systems.get(system)
    if not cmds:
        return None, 'ES-DE has no "%s" system' % system
    label = chosen_label(system, rom_path)
    text = next((c for l, c in cmds if l == label), cmds[0][1])
    cwd = None
    words = []
    emu_path = None
    for tok in text.split():
        if tok.startswith('%INJECT%=') or tok in ('%ENABLESHORTCUTS%', '%HIDEWINDOW%', '%ESCAPESPECIALS%', '%RUNINBACKGROUND%'):
            continue
        if tok.startswith('%STARTDIR%='):
            cwd = tok.split('=', 1)[1]
            continue
        words.append(tok)
    text = ' '.join(words)
    for m in set(re.findall(r'%EMULATOR_([A-Z0-9_-]+)%', text)):
        if m == 'OS-SHELL':
            path = '/bin/sh'
        else:
            path = resolve(rules, 'emulator', m)
        if not path:
            return None, 'Emulator %s not found' % m
        emu_path = emu_path or path
        text = text.replace('%%EMULATOR_%s%%' % m, shlex.quote(path))
    for m in set(re.findall(r'%CORE_([A-Z0-9_-]+)%', text)):
        path = resolve(rules, 'core', m)
        if not path:
            return None, 'Core folder for %s not found' % m
        text = text.replace('%%CORE_%s%%' % m, shlex.quote(path))
    stem = os.path.splitext(os.path.basename(rom_path))[0]
    subs = {'%ROM%': shlex.quote(rom_path), '%ROMRAW%': shlex.quote(rom_path), '%BASENAME%': shlex.quote(stem),
            '%FILENAME%': shlex.quote(os.path.basename(rom_path)), '%GAMEDIR%': shlex.quote(os.path.dirname(rom_path)),
            '%ROMPATH%': shlex.quote(rom_root()), '%ESPATH%': shlex.quote(ESDE_HOME)}
    for k, v in subs.items():
        text = text.replace(k, v)
    if cwd:
        cwd = cwd.replace('%EMUDIR%', os.path.dirname(emu_path or '/')).replace('%GAMEDIR%', os.path.dirname(rom_path))
        cwd = os.path.expanduser(cwd.strip('"'))
    if '%' in re.sub(r'%\d', '', text):
        leftover = re.findall(r'%[A-Z_-]+%', text)
        if leftover:
            return None, 'Unsupported ES-DE variable %s' % leftover[0]
    return shlex.split(text), (cwd if cwd and os.path.isdir(cwd) else None)


# ── ROM index: RLog game -> ROM file ────────────────────────────────────────

def _rank(path):
    name = os.path.basename(path).lower()
    if '(track ' in name:
        return 99
    ext = os.path.splitext(name)[1]
    return EXT_RANK.get(ext, 50 if ext == '.bin' else 5)


def build_index(games, root=None):
    """item_id -> {'path', 'system'} for every library game with a ROM (best file per game)."""
    root = root or rom_root()
    by_norm = {}
    for g in games:
        by_norm.setdefault(tracker.normalize(g['title']), []).append(g)
    found = {}
    try:
        systems_dirs = sorted(os.listdir(root))
    except OSError:
        return {}
    known = _cfg()[1]   # only folders ES-DE knows as systems (EmuDeck also keeps aliases like "gamecube")
    for system in systems_dirs:
        platform = tracker.SYSTEMS.get(system.lower())
        sdir = os.path.join(root, system)
        if not platform or system not in known or not os.path.isdir(sdir):
            continue
        for name in os.listdir(sdir):
            if name.startswith('.') or name == 'media' or name.endswith(('.txt', '.xml', '.pkg', '.PUP', '.sav')):
                continue
            path = os.path.join(sdir, name)
            title = tracker.rom_title(path)
            hits = [g for g in by_norm.get(tracker.normalize(title), []) if tracker._platform_ok(g, platform)]
            if len(hits) != 1:
                continue
            g = hits[0]
            cur = found.get(g['item_id'])
            if cur is None or _rank(path) < _rank(cur['path']):
                found[g['item_id']] = {'path': path, 'system': system}
    # PS3 games installed in RPCS3
    for sfo in glob.glob(os.path.join(os.path.dirname(root), 'storage', 'rpcs3', 'dev_hdd0', 'game', '*', 'PARAM.SFO')):
        try:
            p = tracker._read_sfo(sfo)
        except Exception:
            continue
        eboot = os.path.join(os.path.dirname(sfo), 'USRDIR', 'EBOOT.BIN')
        if p.get('CATEGORY') not in ('HG', 'DG') or not p.get('TITLE') or not os.path.isfile(eboot):
            continue
        hits = [g for g in by_norm.get(tracker.normalize(p['TITLE']), []) if tracker._platform_ok(g, 'PS3')]
        if len(hits) == 1 and hits[0]['item_id'] not in found:
            found[hits[0]['item_id']] = {'path': eboot, 'system': 'ps3-installed'}
    return found


def refresh(force=False):
    """Rebuild the ROM index when the catalog changed (or every 30 min)."""
    games, at = tracker._catalog['games'], tracker._catalog['at']
    if not force and _index['catalog_at'] == at and time.time() - _index['at'] < 30 * 60:
        return
    roms = build_index(games) if games else {}
    # Keep only games whose ES-DE command resolves (e.g. not when the picked emulator isn't installed).
    roms = {i: r for i, r in roms.items() if _rom_command(r)[0]}
    with _lock:
        _index.update(roms=roms, at=time.time(), catalog_at=at)


def playable():
    """Item ids that Play can start: installed Steam games and games with a ROM."""
    with _lock:
        ids = set(_index['roms'])
    for g in tracker._catalog['games']:
        if g.get('steam_appid') and tracker.steam_name(g['steam_appid']):
            ids.add(g['item_id'])
    return sorted(ids)


def command_for(item_id):
    """(argv, cwd) or (None, reason)."""
    g = next((g for g in tracker._catalog['games'] if g['item_id'] == item_id), None)
    if g is None:
        return None, 'That game is not in your RLog library'
    if g.get('steam_appid') and tracker.steam_name(g['steam_appid']):
        return ['xdg-open', 'steam://rungameid/%d' % g['steam_appid']], None
    with _lock:
        rom = _index['roms'].get(item_id)
    if not rom:
        return None, 'No ROM or installed copy found for this game'
    return _rom_command(rom)


def _rom_command(rom):
    if rom['system'] == 'ps3-installed':
        rpcs3 = resolve(_cfg()[2], 'emulator', 'RPCS3')
        if not rpcs3:
            return None, 'RPCS3 not found'
        return [rpcs3, '--no-gui', rom['path']], None
    return es_command(rom['system'], rom['path'])


def play(item_id):
    """Start the game, detached from the daemon. {ok, error}."""
    argv, cwd = command_for(item_id)
    if not argv:
        return {'ok': False, 'error': cwd}
    try:
        subprocess.Popen(argv, cwd=cwd, start_new_session=True, stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return {'ok': True, 'error': ''}
    except OSError as e:
        return {'ok': False, 'error': str(e)[:160]}


def loop():
    while True:
        try:
            _bundled()
            refresh()
        except Exception:
            pass
        time.sleep(60)
