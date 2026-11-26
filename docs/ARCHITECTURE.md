# How Shale is put together

Shale is a Quickshell (QML) desktop shell for Hyprland. The QML draws everything and keeps the session's state; a
Python helper does the work QML can't (D-Bus, files, network, system tools). This page maps the code so you can find
where something lives and add to it without breaking what is there.

```
shell.qml ── per screen ──┬─ Bar ─────────── BarContent (items from core/barItems.js)
                          ├─ PanelHost ───── PanelContent (the case) ── one page: Launcher, ControlCenter, …
                          ├─ Widgets ─────── desktop cards (core/parts.js), only while Settings → Desktop has them on
                          ├─ Toasts ──────── notification popups and the OSD
                          ├─ WallpaperTransition, StayAwake
shell.qml ── once ────────┴─ LockScreen, ActivityTracker, WallpaperAccent

core/ShellState.qml ── settings, which panel is open, IPC ──┐
core/Backend.qml ───── JSON lines over stdin/stdout ────────┴── helpers/backend.py (+ helpers/*.py)
services/*.qml ─────── Quickshell services wrapped for the views (audio, network, Bluetooth, battery, player, …)
```

## Folders

| Folder | What lives there | Change it when |
|---|---|---|
| `shell.qml` | The root: one `Variants` per screen with the bar, panel host, widgets, toasts | adding a new kind of window |
| `core/` | Singletons (`ShellState`, `Backend`, `Theme`) and plain JS libraries (registries, search, icons, colour) | rarely; the registries often |
| `services/` | Singletons over Quickshell services: `Services` (audio, network, Bluetooth, battery, workspaces), `Focus`, `NowPlaying`, `Note`, `Updates`, `Weather` (one forecast for the bar, lock screen, Sky card and Find), `ActivityTracker`, `WallpaperAccent` | a view needs data no service exposes yet |
| `components/` | Shared controls in the Rack style: `Button`, `Switch`, `Segmented`, `ListRow`, `SettingRow`, `QuickTile`, `Card`, `Group`, `EdgeFade`, … | a control is used by two or more views |
| `features/` | Views: the bar, every panel and its parts, the lock screen, toasts, widgets | most changes |
| `helpers/` | The Python helper (`backend.py`) and its modules, one per area (`weather.py`, `sysmon.py`, `activity.py`, …) | a view needs the system to do something |
| `scripts/` | The `shale` command, install and session scripts, icon and emoji builders | |
| `assets/` | Bundled fonts (with their licences), icons, emoji data, shaders | |

## Panels

`ShellState.panel` names the open panel ("" when none) and `ShellState.detail` a page inside it (Control's `wifi`,
`audio`, …). `open(name)`, `toggle(name)` and `close()` change them; the bar, keyboard shortcuts and IPC all go
through these.

`PanelHost` (one per screen) shows the panel on the screen it was opened on, scales it by the Panel size setting and
runs the rise-and-fade entrance. `PanelContent` draws the case and header and loads the page file named in its
`source` map. A page tells the case what it needs through plain properties: `title`, `panelWidth`, `panelHeight`
(a binding, so a page can follow its content), `showHeader`, `headerNote`, `headerCount`, `headerChip`,
`headerTools`, `canGoBack` / `back()`. Pages are unloaded when the panel closes, so state that must outlive a panel
belongs in `ShellState` or a service.

Big panels are split into files named after the panel: `ControlCenter.qml` holds Control's state and requests and
its home view; `ControlWifi.qml`, `ControlBluetooth.qml`, `ControlSound.qml` and `ControlPower.qml` are its detail views and get the
page as `control`; `ControlStrip.qml`, `ControlModuleHeader.qml` and the other `Control*.qml` files are its parts.

## The helper

`core/Backend.qml` starts `python3 helpers/backend.py` and talks to it in JSON lines:

- request: `{"id": 7, "method": "wifi.list", "params": {}}` → reply `{"id": 7, "ok": true, "result": …}` or
  `{"id": 7, "ok": false, "error": {"code", "message"}}`;
- events from the helper: `{"event": "bluetooth", "data": …}`, delivered as `Backend.eventReceived(name, data)`.

`Backend.request(method, params, callback)` always calls back exactly once: with the result, with an error, with
`stopped` if the helper exits (it restarts after 5 s), or with a timeout after three minutes. The helper runs each
request as its own task, so replies can arrive in any order; a view that sends a request again before the last reply
keeps a counter and ignores late replies (see `requestGeneration` in `ControlCenter.qml`, `generation` in
`Wallpaper.qml`). Methods are dispatched in `Backend.dispatch` in `helpers/backend.py`, grouped by prefix
(`wifi.*`, `bluetooth.*`, `system.*`, `activity.*`, …).

## Settings

1. `helpers/backend.py` owns the file (`~/.config/shale/config.json`): `DEFAULTS` gives every key its default and
   type, `check_setting` validates a value. A new setting starts here.
2. `ShellState.setting(key, fallback)` reads; `ShellState.setSetting(key, value)` writes and saves 350 ms later
   (`settings.set`). Bindings on `setting(…)` update everywhere at once.
3. The Settings panel shows a row for it: `features/Settings.qml` holds the categories and places their pages, one
   `*Settings.qml` file each (`GeneralSettings.qml`, `PowerSettings.qml`, …). Rows are `SettingRow`, `ChoiceRow`,
   `SettingToggle`, `FolderField`, `OpenRow` or `ValueRow` inside a `Group`; give a row `settingKey` (the toggles
   and folder rows take it from `key`) and it gets a reset key while the setting differs from its default.
4. Find a setting finds any row with a `description` and a `label` or `text`, under the page whose `objectName` is
   its category name; nothing else to register.

## Registries

Lists the user can rearrange live in plain JS files, each mirrored by a list of IDs in `helpers/backend.py` that
checks saved values:

| File | What | Checked by |
|---|---|---|
| `core/barItems.js` | bar items, their default zone and order | `BAR_ITEMS` |
| `core/controlItems.js` | Control's tiles, sections and footer buttons | `CONTROL_*` |
| `core/parts.js` | desktop cards (file, width, matching bar item) and card layouts | `WIDGET_CARDS` |

## IPC

`quickshell ipc -p <checkout> call <target> <function>`; the `shale` command wraps the common ones.

| Target | Functions |
|---|---|
| `shell` | `status`, `toggle(panel)`, `close`, `action(name)`, `lock`, `lockStatus`, `abortLock`, `dnd(on/off/toggle)`, `settingsPage(name)`, `page(name)` |
| `focus` | `start`, `end`, `toggle`, `pause`, `timer(seconds, label)`, `status` |
| `bar-<output>`, `surface-<output>` | `status` (what the bar and the panel host on that screen show) |
| `wallpaper-picker` | `status`, `select(index)`, `apply` |

## Conventions

- Colours, radii, spacing, type sizes and durations come from `Theme`; every animation uses `Theme` durations, which
  are 0 with reduced motion and shorter when effects are trimmed.
- A view that combines several flags into one situation exposes it as one read-only `phase` (or `mode`) string with
  the states listed in a comment (`FocusView.phase`, `Activity.phase`, the Session menu's `mode`); bind to that, not
  to the flags.
- Comments explain why, in plain sentences. User-facing words: Control, Find, Pages, Widgets, Clock and sky, Player.

## Recipes

- **A panel:** a page file in `features/`, its name in `PanelContent`'s `source` map, a way to open it
  (`ShellState.toggle("name")` from a bar item, a shortcut in `helpers/shortcuts.json`, or Find's actions in
  `core/search.js`).
- **A desktop card:** a `WidgetsCard` file in `features/` (it may declare `now` and `live`; `Widgets.qml` sets
  them), an entry in `core/parts.js`, its ID in `WIDGET_CARDS`.
- **A bar item:** an entry in `core/barItems.js`, its ID in `BAR_ITEMS`, a `Bar<Name>.qml` file (a `BarKey`,
  `BarLiveChip` or `BarStatusPart` with `required property var bar`) and its `Component` in `BarContent.qml`.
- **A setting:** the default and check in `backend.py`, a row on its Settings page.
- **A helper method:** a branch in `Backend.dispatch` (or the module it belongs to); return plain JSON and raise
  `BackendError(code, message)` with a message the user can read.
