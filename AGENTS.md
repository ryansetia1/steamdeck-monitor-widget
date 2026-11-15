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

## Service tiles

Clicking a service tile (compact card in `main.qml`, rows in `DashboardView.qml` via the
`serviceClicked(key, ok)` signal) calls `root.openService()`, which runs
`plasmoid/contents/code/open-service.sh <key> <0|1>` detached (`setsid -f`) through the Plasma5Support
`executable` engine. Change what a click does in that script.

Hovering the Dropbox tile/row shows `DropboxUsage.qml`: `services.dropbox_used` (bytes, daemon
walks the Dropbox folder from `~/.dropbox/info.json`, cached 5 min) against config `dropboxQuotaGB`.

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
