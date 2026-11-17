# Agent notes: steamdeck-monitor-widget

KDE Plasma 6 desktop widget (`org.ryan.deckmonitor`) for the Steam Deck, fed by a small Python
daemon (`bin/deck-monitor-daemon.py`, `127.0.0.1:19842`, systemd user service `deck-monitor`).
The floating card also has a built-in **game search row**: steamAF (left) + HowLongToBeat (right).

## ⚠️ Keep the game search in sync with the standalone widgets

The game search is deliberately duplicated: this repo is the all-in-one version, and two
standalone widgets exist as modular options:

- steamAF: https://github.com/ryansetia1/steamdeck-steamaf-widget
- HowLongToBeat: https://github.com/ryansetia1/steamdeck-hltb-widget

**Any change to the steamAF or HowLongToBeat search, here or in a standalone widget, must be
applied to the other side as well. Commit and push every affected repo so all three stay in sync.**

| This repo | Counterpart | Rule |
|---|---|---|
| `bin/games_hltb.py` | hltb widget `plasmoid/contents/code/hltb.py` | byte-identical |
| `bin/games_steamaf.py` | steamaf widget `plasmoid/contents/code/steamaf.py` | byte-identical |
| `plasmoid/contents/ui/VerdictBadge.qml` | steamaf widget `plasmoid/contents/ui/VerdictBadge.qml` | byte-identical |
| `plasmoid/contents/icons/steamaf.png` | steamaf widget `plasmoid/contents/icons/steamaf.png` | byte-identical |
| `plasmoid/contents/ui/MediaCarousel.qml`, `MediaTheater.qml` | steamaf widget, same paths | byte-identical |
| `plasmoid/contents/ui/GamesSection.qml` | each widget's `plasmoid/contents/ui/main.qml` (island, result rows, steamAF detail) | adapted, port changes by hand |
| config group `Games` (`gamesCurrency`, `gamesMainStory`, `gamesIslandStyle`, `gamesIslandOpacity`, `showGames`) | widget configs (`currency`, `showMainStory`, `islandStyle`, `islandOpacity`) | same meaning, different keys |

Check the identical files with `diff -q` before committing. Every pixel size in `GamesSection.qml`
goes through `gs.px(n)` (scaled by Deck Monitor's font size setting: `fs = compactWidth / 320`), and
`VerdictBadge.qml` has an `fs` property (default 1). Wrap sizes the same way when porting widget
changes in, and keep `fs` working when changing `VerdictBadge.qml`. In `GamesSection.qml`, state is
prefixed (`af*` for steamAF, `hl*` for HLTB) under the root id `gs`. Data comes from the daemon
over `XMLHttpRequest`; the standalone widgets run their helper through the Plasma5Support
`executable` engine instead.

## How the game search works

- Daemon endpoints (`GET`, JSON, same shapes as the standalone helpers' output):
  `/games/hltb?q=`, `/games/steamaf/search?q=&currency=`,
  `/games/steamaf/detail?appId=&currency=&title=`, `/games/steamaf/hours?pairs=<json [[id,title]]>`.
  The daemon imports `games_hltb` / `games_steamaf` from its own folder and keeps working if they
  are missing.
- steamAF API origin: `https://steamaf.vercel.app` (public endpoints, no keys). HowLongToBeat has
  no official API: `hltb.py` gets a token from `/api/search/site/init`, then POSTs `/api/search/site`.
  HLTB rotates these paths now and then. When it breaks, look for `/api/` in the site's
  `/_next/static/chunks/*.js`, then fix both helpers (and steamAF's own `lib/hltbCache.ts` in the
  private steamAF repo if its HLTB row breaks too).
- Results show in a floating "island": a `PlasmaCore.Dialog` with `type: Tooltip` (never takes
  keyboard focus, still clickable/scrollable), flags `WindowStaysOnTopHint | WindowDoesNotAcceptFocus`,
  `NoBackground`, positioned by hand via `mapToGlobal` under the card. Don't use `visualParent`
  auto-placement; it flipped the island above the widget. The island is open while the focused
  search field has content and closes when the field loses focus.

## RLog row (Playing / Up next)

`RlogSection.qml` sits above the game search: one row naming the Playing game on top, and an island
(same Dialog pattern and background setting as the search island) with that game large, the other
Playing games as a carousel (tap = swap the top card, stored in config `rlogPinned`) and the queue's
top three. Read-only: taps open RLog (`https://r-log.vercel.app/#/home?m=game&game=<entry id>`).
The top card follows play: a running Playing game takes over, and so does one played while the widget
wasn't looking (Game Mode): the tracker's `now.last_played` `{item_id, at}` wins when `at` is newer than
`rlogPinnedAt` (set on every pin). Palate cleansers never take over. The franchise list on the detail
page scrolls on its own (7 rows); the detail page is capped above the taskbar (`availableScreenRect`).
The island toggles from the row, closes on Esc/✕, when focus leaves, or when the search island opens.

- Daemon: `GET /rlog` (`?refresh=1` forces) → `bin/rlog_island.py`, which fetches RLog's
  `/api/widget` with `WIDGET_TOKEN` from `~/.config/rlog/widget.env` (never put the token in the repo or
  Plasma config), caches 10 min in memory and `~/.cache/deck-monitor/rlog.json` for offline.
- The summary is shaped in the RLog repo (`src/widget.ts`); change fields there, not here.
- Product rules (palate cleansers stay silent, once-only snoozable chips) are in RLog's
  `docs/PLAN.md` "Deck Monitor integration"; D2 (running-game detection) builds on this.
- Config: `showRlog`, `rlogPinned` (group `RLog`). `gamesRowHeight` in `main.qml` counts both rows.
- Detail page (top card / Up next / franchise member tap): `GET /rlog/detail?item=<item id>` (RLog
  `/api/widget?item=`) and `GET /rlog/media?igdb=&steam=` (RLog's public `/api/igdb?op=media`, shaped
  for `MediaCarousel.qml`; YouTube trailers are dropped). ‹ / Esc goes back through `trail`; the
  detail scrolls when taller than the screen (`maxDetailH`). Theater = the shared `MediaTheater.qml`.

### What's running (RLog D2/D3)

`bin/rlog_tracker.py` runs in a daemon thread (scan `/proc` every 20 s):
- Detects Steam games (`AppId=` on the reaper, real app ids only; non-Steam shortcuts get huge ids and
  are ignored) and emulator games (an emulator process whose argument is an existing ROM path; EmuDeck
  `roms/<system>/` gives the platform via `SYSTEMS`; RPCS3/Vita3K/shadPS4 titles from PARAM.SFO).
  A shell command that merely mentions a ROM is not a game (the argument must be one existing path).
- Matches to RLog's `/api/widget?catalog=1` (cached 30 min, `~/.cache/deck-monitor/rlog-catalog.json`):
  Steam app id, else `normalize()`d title + platform (`IGDB_NAMES` maps RLog names to IGDB's). Unsure =
  no match = palate cleanser. Manual fixes: `~/.config/rlog/aliases.json` `{"rom title": "<item id>"}`.
- Sessions (≥1 min, suspend-safe via monotonic time) in `~/.local/share/deck-monitor/rlog-sessions.json`.
  Emulator minutes of matched games are totalled and POSTed to RLog every 10 min (`rlog_island._post`).
- Prompts (`now_state()`, part of `GET /rlog` as `now`): `finished` for Playing games past HLTB main ×
  pace; `playing` for non-Playing, non-completed games with main ≥ 5 h and Deck time since `status_at` ≥ 50%
  of main × pace. `POST /rlog/prompt {item_id, kind, action: snooze|never, days: 3|7|30}` →
  `~/.config/deck-monitor/rlog-prompts.json`. The island shows each as a chip, never a popup.
- Tests: `python3 -m unittest discover tests` (they build a temporary ROM tree). When testing live with a
  fake emulator process, delete `rlog-sessions.json` afterwards so fake minutes never reach RLog.

### Play button (rlog_launch.py)

The banner row (screenshot behind via `/rlog/media`, cover, title, year, ▶) and
the detail header have a ▶ that `POST /rlog/play {item_id}`. `bin/rlog_launch.py` launches like ES-DE:
- Steam games: `xdg-open steam://rungameid/<appid>` when installed (appmanifest exists).
- ROMs: indexes ES-DE's ROMDirectory (read from `~/ES-DE/settings/es_settings.xml` as text: the file has
  no root element), only folders that are ES-DE systems (EmuDeck's alias folders like `gamecube` are
  skipped), best file per game (.m3u > .cue > .chd …, never "(Track n)"). The command: the system's
  `<command>` from ES-DE's bundled es_systems.xml (extracted once from the AppImage into
  `~/.cache/deck-monitor/es-de/`) overridden by `~/ES-DE/custom_systems`, the label picked in
  `gamelists/<system>/gamelist.xml` (`<altemulator>` per game, `<alternativeEmulator>` per system; read as
  text too), `%EMULATOR_x%`/`%CORE_x%` via find rules (custom first: EmuDeck launchers). Games whose command
  doesn't resolve aren't in `playable`.
- PS3 games installed in RPCS3 (`storage/rpcs3/dev_hdd0/game/*/PARAM.SFO`): RPCS3 `--no-gui` EBOOT.BIN.
- `Kirigami.ShadowedImage` doesn't render under `QT_QPA_PLATFORM=offscreen`; check the banner on the desktop.

## Service tiles

Clicking a service tile (compact card in `main.qml`, rows in `DashboardView.qml` via the
`serviceClicked(key, ok)` signal) calls `root.openService()`, which runs
`plasmoid/contents/code/open-service.sh <key> <0|1>` detached (`setsid -f`) through the Plasma5Support
`executable` engine. Change what a click does in that script.

Hovering the Dropbox tile/row shows `DropboxUsage.qml`: `services.dropbox_used` (bytes, daemon
walks the Dropbox folder from `~/.dropbox/info.json`, cached 5 min) against config `dropboxQuotaGB`.

## Game media (cover, trailers, screenshots)

`steamaf.py detail` also returns `media` (Steam store `appdetails`: trailers as HLS `hls_h264`
streams, screenshots). `MediaCarousel.qml` shows the cover first with ‹ › chevrons; clicking opens
`MediaTheater.qml`, a full-screen Tooltip-type `PlasmaCore.Dialog` (QtMultimedia + FFmpeg plays the
HLS trailer). It never takes focus, so the search field forwards ←/→/Esc to it (`SearchField`
`arrowsTaken` / `arrow()`). It closes when the island closes or the detail is left.

## Install / test

- `./install.sh` copies the daemon, helpers and plasmoid. It runs `systemctl --user enable --now`,
  which does **not** restart a running daemon: after daemon/helper changes run
  `systemctl --user restart deck-monitor.service`. Reload QML with
  `systemctl --user restart plasma-plasmashell`.
- Check a QML file outside Plasma (errors are hidden unless forced to stderr):
  `QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 qml6 test.qml` with a small `Window`
  wrapper. `i18n is not defined` there is expected.
- Desktop widget size/position can't be changed through `evaluateScript` `geometry` on Plasma 6.7.
  Stop plasmashell and edit `ItemGeometries-*` in `~/.config/plasma-org.kde.plasma.desktop-appletsrc`.
- QML gotcha: `escape` is not a valid signal name (JS global). Use e.g. `escapePressed`.
