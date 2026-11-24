"""Play button (bin/rlog_launch.py) against a fake ES-DE setup: `python3 -m unittest discover tests`."""
import os
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'bin'))
import rlog_launch as L  # noqa: E402
import rlog_tracker as t  # noqa: E402


def write(path, text=''):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(text)
    return path


class Launch(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.mkdtemp()
        self.roms = os.path.join(tmp, 'Emulation', 'roms')
        L.ESDE_HOME = os.path.join(tmp, 'ES-DE')
        bundled = os.path.join(tmp, 'bundled')
        self.retro = write(os.path.join(tmp, 'bin', 'retroarch'))
        self.pcsx2 = write(os.path.join(tmp, 'Applications', 'pcsx2-Qt.AppImage'))
        self.dolphin = write(os.path.join(tmp, 'launchers', 'dolphin-emu.sh'))
        cores = os.path.join(tmp, 'cores')
        os.makedirs(cores)
        write(os.path.join(bundled, 'es_systems.xml'), '''<systemList>
  <system><name>ps2</name>
    <command label="PCEE2">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/pcee2_libretro.so %ROM%</command>
    <command label="PCSX2 (Standalone)">%EMULATOR_PCSX2% -batch %ROM%</command></system>
  <system><name>gc</name>
    <command label="Dolphin">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/dolphin_libretro.so %ROM%</command>
    <command label="Dolphin (Standalone)">%INJECT%=%BASENAME%.esprefix %EMULATOR_DOLPHIN% -b -e %ROM%</command></system>
  <system><name>gb</name>
    <command label="Gambatte">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/gambatte_libretro.so %ROM%</command></system>
  <system><name>nds</name>
    <command label="melonDS (Standalone)">%EMULATOR_MELONDS% -f %ROM%</command></system>
</systemList>''')
        write(os.path.join(bundled, 'es_find_rules.xml'), '''<ruleList>
  <emulator name="RETROARCH"><rule type="staticpath"><entry>%s</entry></rule></emulator>
  <emulator name="PCSX2"><rule type="staticpath"><entry>%s</entry></rule></emulator>
  <emulator name="MELONDS"><rule type="staticpath"><entry>/nowhere/melonDS.AppImage</entry></rule></emulator>
  <core name="RETROARCH"><rule type="corepath"><entry>%s</entry></rule></core>
</ruleList>''' % (self.retro, os.path.join(tmp, 'Applications', 'pcsx2-*.AppImage'), cores))
        # EmuDeck-style custom rule: Dolphin goes through its launcher script
        write(os.path.join(L.ESDE_HOME, 'custom_systems', 'es_find_rules.xml'),
              '<ruleList><emulator name="DOLPHIN"><rule type="staticpath"><entry>%s</entry></rule></emulator></ruleList>' % self.dolphin)
        write(os.path.join(L.ESDE_HOME, 'settings', 'es_settings.xml'),
              '<?xml version="1.0"?>\n<string name="ROMDirectory" value="%s" />\n<bool name="X" value="true" />\n' % self.roms)
        write(os.path.join(L.ESDE_HOME, 'gamelists', 'ps2', 'gamelist.xml'),
              '<?xml version="1.0"?>\n<alternativeEmulator>\n\t<label>PCSX2 (Standalone)</label>\n</alternativeEmulator>\n<gameList>\n</gameList>\n')
        write(os.path.join(L.ESDE_HOME, 'gamelists', 'gc', 'gamelist.xml'),
              '<?xml version="1.0"?>\n<gameList>\n<game><path>./Resident Evil Zero (USA) (Disc 1).rvz</path>'
              '<altemulator>Dolphin (Standalone)</altemulator></game>\n</gameList>\n')
        L._bundled = lambda: bundled
        L._cfg_cache.update(at=0, cfg=None)
        self.gta = write(os.path.join(self.roms, 'ps2', 'Grand Theft Auto III (USA).chd'))
        self.re0 = write(os.path.join(self.roms, 'gc', 'Resident Evil Zero (USA) (Disc 1).rvz'))
        write(os.path.join(self.roms, 'gamecube', 'Resident Evil Zero (USA) (Disc 1).rvz'))   # EmuDeck alias folder
        self.zelda = write(os.path.join(self.roms, 'gb', "Legend of Zelda, The - Link's Awakening (USA, Europe).zip"))
        write(os.path.join(self.roms, 'nds', 'Mario Kart DS (USA).nds'))
        t._catalog.update(at=time.time(), pace=None, games=[
            {'item_id': 'gta3', 'title': 'Grand Theft Auto III', 'platform': 'PS2', 'platforms': ['PS2'], 'steam_appid': None},
            {'item_id': 're0', 'title': 'Resident Evil Zero', 'platform': 'GameCube', 'platforms': ['NGC'], 'steam_appid': None},
            {'item_id': 'la', 'title': "The Legend of Zelda: Link's Awakening", 'platform': None, 'platforms': ['GB'], 'steam_appid': None},
            {'item_id': 'mkds', 'title': 'Mario Kart DS', 'platform': 'DS', 'platforms': ['NDS'], 'steam_appid': None},
        ])
        L.refresh(force=True)

    def test_system_pick_and_find_rules(self):
        self.assertEqual(L.command_for('gta3'), ([self.pcsx2, '-batch', self.gta], None), "ES-DE's picked emulator, found by glob")

    def test_per_game_pick_custom_rule_and_es_systems_only(self):
        self.assertEqual(L.command_for('re0'), ([self.dolphin, '-b', '-e', self.re0], None),
                         'per-game altemulator; %INJECT% dropped; the "gamecube" alias folder ignored')

    def test_core_path_and_quotes(self):
        argv, _ = L.command_for('la')
        self.assertEqual(argv, [self.retro, '-L', os.path.dirname(self.retro).replace('bin', 'cores') + '/gambatte_libretro.so', self.zelda])

    def test_unresolvable_emulator_is_not_playable(self):
        self.assertNotIn('mkds', L.playable())
        self.assertEqual(sorted(L.playable()), ['gta3', 'la', 're0'])
        self.assertIsNone(L.command_for('nope')[0])

    def test_launch_env_inherits_systemd_display_vars(self):
        orig_check_output = L.subprocess.check_output
        orig_environ = L.os.environ.copy()
        try:
            L.os.environ.pop('DISPLAY', None)
            L.os.environ.pop('XAUTHORITY', None)
            L.subprocess.check_output = lambda *a, **kw: (
                'DISPLAY=:0\nXAUTHORITY=/run/user/1000/xauth_test\nQT_QPA_PLATFORM=xcb\n'
            )
            env = L._launch_env()
            self.assertEqual(env.get('DISPLAY'), ':0')
            self.assertEqual(env.get('XAUTHORITY'), '/run/user/1000/xauth_test')
            self.assertEqual(env.get('QT_QPA_PLATFORM'), 'xcb')
        finally:
            L.subprocess.check_output = orig_check_output
            L.os.environ.clear()
            L.os.environ.update(orig_environ)


if __name__ == '__main__':
    unittest.main()
