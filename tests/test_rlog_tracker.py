"""RLog tracker (bin/rlog_tracker.py): run with `python3 -m unittest discover tests`."""
import os
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'bin'))
import rlog_island  # noqa: E402
import rlog_tracker as t  # noqa: E402

ROMS = os.path.join(tempfile.mkdtemp(), 'Emulation', 'roms')


def rom(rel):
    """An empty ROM file in a temporary EmuDeck-style tree (detection needs the file to exist)."""
    path = ROMS + rel
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'a').close()
    return path


def game(item_id, title, status='owned', platform=None, platforms=(), steam=None, main=None, played=None, status_at=0):
    return {'item_id': item_id, 'entry_id': 'e-' + item_id, 'title': title, 'status': status, 'status_at': status_at,
            'platform': platform, 'platforms': list(platforms), 'steam_appid': steam, 'main_h': main,
            'played_h': played, 'link': 'https://r-log.vercel.app/#/home?m=game&game=e-' + item_id}


CATALOG = [
    game('re0', 'Resident Evil Zero', 'on_hold', 'GameCube', ['NGC', 'Wii'], main=11.2),
    game('re2ps1', 'Resident Evil 2', 'completed', 'PS1', ['PS1', 'N64', 'PC']),
    game('re2rm', 'Resident Evil 2', 'owned', 'Steam', ['PC', 'PS4'], steam=883710),
    game('gta3', 'Grand Theft Auto III', 'playing', 'PS2', ['PS2', 'PC'], main=13.7, played=None),
    game('acb', "Assassin's Creed Brotherhood", 'playing', 'Steam', ['PC'], steam=48190, main=15.3, played=45.8),
    game('sotn', 'Castlevania: Symphony of the Night', 'on_hold', 'PS1', ['PS1'], main=10),
    game('zelda', 'The Legend of Zelda: A Link to the Past', 'completed', 'SNES', ['SNES'], main=15),
    game('ms', 'Metal Slug 3', 'owned', None, ['Arcade'], main=1),
]


class Titles(unittest.TestCase):
    def test_rom_titles(self):
        self.assertEqual(t.rom_title('/x/01. The Legend of Zelda - A Link to the Past (USA).sfc'), 'The Legend of Zelda - A Link to the Past')
        self.assertEqual(t.rom_title("/x/Legend of Zelda, The - Link's Awakening (USA, Europe) (Rev 2).zip"), "The Legend of Zelda - Link's Awakening")
        self.assertEqual(t.rom_title('/x/FINAL FANTASY VIII Remastered [01008B900DC0A000][v0].nsp'), 'FINAL FANTASY VIII Remastered')
        self.assertEqual(t.rom_title('/x/Resident Evil Zero (USA) (Disc 1).rvz'), 'Resident Evil Zero')

    def test_normalize(self):
        self.assertEqual(t.normalize('Pokémon: Red Version™'), 'pokemon red version')
        self.assertEqual(t.normalize('Castlevania II - Simon\'s Quest'), t.normalize("Castlevania 2: Simon's Quest"))
        self.assertEqual(t.normalize('Resident Evil Zero'), t.normalize('Resident Evil 0'))
        self.assertEqual(t.normalize('The Legend of Zelda'), 'legend of zelda')


class Detection(unittest.TestCase):
    def test_steam_game_and_shortcut(self):
        dets = t.detect([
            ['/home/deck/.local/share/Steam/ubuntu12_32/reaper', 'SteamLaunch', 'AppId=48190', '--', 'proton', 'waitforexitandrun', 'ACB.exe'],
            ['/home/deck/.local/share/Steam/ubuntu12_32/reaper', 'SteamLaunch', 'AppId=3105467862', '--', '/usr/bin/flatpak', 'run', 'org.DolphinEmu.dolphin-emu',
             '-b', '-e', rom('/gc/Resident Evil Zero (USA) (Disc 1).rvz')],
            ['/usr/bin/bwrap', '--args', '40', 'dolphin-emu', '-b', '-e', rom('/gc/Resident Evil Zero (USA) (Disc 1).rvz')],
        ])
        keys = sorted(d['key'] for d in dets)
        self.assertEqual(keys, ['emu:GameCube:resident evil 0', 'steam:48190'], 'shortcut app id ignored; the emulator counted once')
        emu = [d for d in dets if d['kind'] == 'emu'][0]
        self.assertEqual((emu['title'], emu['platform']), ('Resident Evil Zero', 'GameCube'))

    def test_shell_script_mentioning_a_rom(self):
        path = rom('/ps2/Grand Theft Auto III (USA).chd')
        self.assertEqual(t.detect([['/bin/bash', '-c', 'nohup retroarch "%s" > /tmp/x-cwd' % path]]), [])

    def test_not_an_emulator(self):
        self.assertEqual(t.detect([['/usr/bin/rsync', '-a', rom('/gc/Resident Evil Zero (USA) (Disc 1).rvz'), '/backup']]), [])
        self.assertEqual(t.detect([['/home/deck/Applications/ES-DE.AppImage']]), [])


class Matching(unittest.TestCase):
    def emu(self, path):
        return t.detect([['/usr/bin/retroarch', '-L', 'core.so', path]])[0]

    def test_platform_picks_between_same_titles(self):
        self.assertEqual(t.match(self.emu(rom('/psx/Resident Evil 2 (USA).chd')), CATALOG, {})['item_id'], 're2ps1')
        self.assertEqual(t.match(self.emu(rom('/n64/Resident Evil 2 (USA) (Rev 1).z64')), CATALOG, {})['item_id'], 're2ps1')
        self.assertIsNone(t.match(self.emu(rom('/gb/Resident Evil 2 (USA).zip')), CATALOG, {}), 'no Game Boy release: unsure')

    def test_titles_and_steam(self):
        self.assertEqual(t.match(self.emu(rom('/psx/Castlevania - Symphony of the Night (USA).chd')), CATALOG, {})['item_id'], 'sotn')
        self.assertEqual(t.match({'steam_appid': 48190, 'title': 'x'}, CATALOG, {})['item_id'], 'acb')
        self.assertIsNone(t.match(self.emu(rom('/arcade/mslug3.zip')), CATALOG, {}), 'MAME short names never match')

    def test_alias(self):
        det = self.emu(rom('/nes/Super Mario Bros. + 77. Duck Hunt (USA).nes'))
        self.assertIsNone(t.match(det, CATALOG, {}))
        self.assertEqual(t.match(det, CATALOG, {t.normalize(det['title']): 'zelda'})['item_id'], 'zelda')


class Sessions(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        t.SESSIONS_PATH = os.path.join(self.tmp, 's.json')
        t.PROMPTS_PATH = os.path.join(self.tmp, 'p.json')
        t.CATALOG_CACHE = os.path.join(self.tmp, 'c.json')
        t._catalog.update(games=CATALOG, pace={'ratio': 1.7, 'samples': 13}, at=time.time())
        t._state.update(sessions=[], totals={}, sent={})
        t._live.clear()
        t._prompts.clear()
        self.posted = []
        rlog_island._post = lambda body: self.posted.append(body)
        rlog_island.invalidate = lambda: None
        t._last_push = time.time() + 10_000   # no pushes unless a test asks

    def play(self, args, minutes, start=1_000_000.0):
        now, mono = start, 0.0
        for _ in range(int(minutes * 60 / t.TICK) + 1):
            t.tick(now=now, mono=mono, cmdlines=[args])
            now += t.TICK
            mono += t.TICK
        return now, mono

    def test_emulator_session_totals_and_push(self):
        args = ['dolphin-emu', '-e', rom('/ps2/Grand Theft Auto III (USA).chd')]
        now, mono = self.play(args, 30)
        state = t.now_state(now)
        self.assertEqual(state['running']['item_id'], 'gta3')
        self.assertEqual(state['running']['minutes'], 30)
        t.tick(now=now + 120, mono=mono + 120, cmdlines=[])   # gone for 2 minutes: session ends
        self.assertEqual(len(t._state['sessions']), 1)
        self.assertEqual(t._state['totals']['gta3']['min'], 30)
        t._maybe_push(now, force=True)
        self.assertEqual(self.posted[0]['plays'][0]['item_id'], 'gta3')
        self.assertEqual(self.posted[0]['plays'][0]['minutes'], 30)
        t._maybe_push(now, force=True)
        self.assertEqual(len(self.posted), 1, 'unchanged totals are not sent again')

    def test_suspend_does_not_count(self):
        args = ['pcsx2-qt', rom('/ps2/Grand Theft Auto III (USA).chd')]
        t.tick(now=0.0, mono=0.0, cmdlines=[args])
        t.tick(now=20.0, mono=20.0, cmdlines=[args])
        t.tick(now=7200.0, mono=40.0, cmdlines=[args])   # 2 h asleep: monotonic barely moved
        self.assertLess(t.now_state(7200)['running']['minutes'], 2)

    def test_palate_cleanser_and_unmatched_are_silent(self):
        now, _ = self.play(['retroarch', rom('/arcade/mslug3.zip')], 40)
        s = t.now_state(now)
        self.assertIsNone(s['running']['item_id'])
        self.assertEqual([p for p in s['prompts'] if p['kind'] == 'playing'], [])

    def test_finished_prompt_uses_pace_and_snoozes(self):
        s = t.now_state()
        fin = [p for p in s['prompts'] if p['kind'] == 'finished']
        self.assertEqual([p['item_id'] for p in fin], ['acb'], 'ACB 45.8 h > 15.3 × 1.7; GTA III has no hours yet')
        self.assertEqual(fin[0]['target_h'], 26.0)
        self.assertTrue(t.answer('acb', 'finished', 'snooze', 7))
        self.assertEqual([p for p in t.now_state()['prompts'] if p['kind'] == 'finished'], [])
        self.assertFalse(t.answer('acb', 'finished', 'snooze', 5), 'only 3, 7 or 30 days')

    def test_move_to_playing_counts_time_since_status_change(self):
        # SotN (main 10 h × 1.7 = 17 h): 8.5 h needed since its status changed.
        old = {'title': 'x', 'platform': 'PS1', 'kind': 'emu', 'item_id': 'sotn', 'start': 0, 'end': 1, 'min': 600}
        t._state['sessions'].append(old)
        t._catalog['games'] = [dict(g, status_at=1000) if g['item_id'] == 'sotn' else g for g in CATALOG]
        self.assertEqual([p for p in t.now_state()['prompts'] if p['kind'] == 'playing'], [], 'time before the status change')
        t._state['sessions'].append(dict(old, start=2000, min=520))
        p = [p for p in t.now_state()['prompts'] if p['kind'] == 'playing']
        self.assertEqual([x['item_id'] for x in p], ['sotn'])
        self.assertTrue(t.answer('sotn', 'playing', 'never'))
        self.assertEqual([p for p in t.now_state()['prompts'] if p['kind'] == 'playing'], [])

    def test_short_games_never_ask_to_move(self):
        t._state['sessions'].append({'title': 'x', 'platform': 'Arcade', 'kind': 'emu', 'item_id': 'ms', 'start': 1, 'end': 2, 'min': 600})
        self.assertEqual([p for p in t.now_state()['prompts'] if p['kind'] == 'playing'], [], 'HLTB under 5 h')


if __name__ == '__main__':
    unittest.main()
