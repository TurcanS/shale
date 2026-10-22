pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "paths.js" as Paths

QtObject {
    id: root
    property string panel: ""
    property string screenName: ""
    property string detail: ""
    property var settings: ({})
    property string toast: ""
    // info | success | error; errors stay longer and use the danger color.
    property string toastKind: "info"
    // Optional {label, run} pair rendered as a toast button.
    property var toastAction: null
    property string osdLabel: ""
    property real osdValue: 0
    property string osdGlyph: "volume"
    property bool osdMuted: false
    property bool osdVisible: false
    // Bumps on every OSD update so the icon can react even when the value is unchanged.
    property int osdSerial: 0
    // Follows Settings → 24-hour clock everywhere a time of day is shown.
    readonly property string timeFormat: setting("clock24h", true) ? "HH:mm" : "h:mm AP"
    // 0 is Sunday. Settings → General may choose instead of the locale.
    readonly property int firstDayOfWeek: ({monday: 1, sunday: 0, saturday: 6})[setting("weekStart", "locale")] ?? Qt.locale().firstDayOfWeek % 7
    // Where the bar ends (its height plus its gap from the screen edge); panels and popups open below it.
    readonly property int barBottom: setting("barStyle", "floating") === "edge" ? 32 : 37
    property bool lidAwake: false
    property bool lidBusy: false
    function toggleLidAwake() {
        if (lidBusy) return;
        lidBusy = true;
        Backend.request("display.lid.toggle", {}, (r, e) => {
            lidBusy = false;
            if (e) message(e.message, "error");
            else lidAwake = r.enabled;
        });
    }
    property bool grayscale: false
    property bool grayscaleBusy: false
    function toggleGrayscale() {
        if (grayscaleBusy) return;
        grayscaleBusy = true;
        Backend.request("display.grayscale.toggle", {}, (r, e) => {
            grayscaleBusy = false;
            if (e) message(e.message, "error");
            else grayscale = r.enabled;
        });
    }
    property bool presentation: false
    property bool locked: false
    // "shell" while the built-in lock screen is up, "external" for hyprlock. Only a successful
    // password check unlocks the shell's own lock screen; IPC can lock it but never unlock it.
    property string lockOwner: ""
    // True once the compositor confirms every output is covered by the lock screen.
    property bool lockSecure: false
    // The shell's lock screen takes over once the desktop has folded away (LockTransition), a moment after
    // `locked`; until then lockStatus reports it locked but not yet secure, as it would while the compositor confirms.
    property bool lockEngaged: false
    readonly property int lockLead: setting("reducedMotion", false) ? 0 : powerSaver || setting("batterySaving", false) ? 420 : 680
    property Timer lockEngage: Timer {
        interval: root.lockLead
        onTriggered: root.lockEngaged = root.locked && root.lockOwner === "shell"
    }
    onLockedChanged: {
        if (!locked) {
            lockEngage.stop();
            lockEngaged = false;
        }
        if (Backend.ready)
            Backend.request("session.lockedHint", {locked: locked});
    }
    function lockShell() {
        // hyprlock only when chosen and known to be installed; otherwise the screen would stay unlocked.
        if (setting("lockScreen", "builtin") === "hyprlock" && Backend.has("hyprlock", false))
            return false;
        if (locked)
            return lockOwner === "shell";
        close();
        osdVisible = false;
        lockOwner = "shell";
        locked = true;
        if (lockLead > 0)
            lockEngage.restart();
        else
            lockEngaged = true;
        return true;
    }
    // Called by the lock screen after PAM accepts the password.
    function unlockShell() {
        if (lockOwner !== "shell")
            return;
        lockOwner = "";
        locked = false;
    }
    property var recording: ({
            active: false
        })
    property var wifi: ({
            networks: [],
            powered: false,
            state: "Unavailable"
        })
    // False without NetworkManager or a Wi-Fi device; Wi-Fi controls are hidden then.
    readonly property bool wifiAvailable: wifi.available !== false
    property var profiles: ({
            profiles: [],
            active: ""
        })
    // Power saver also trims the shell and compositor; see applyPowerMode().
    readonly property bool powerSaver: profiles.active === "power-saver"
    readonly property string powerModeKey: profiles.active && Object.keys(settings).length ? profiles.active + "/" + setting("saverRefresh", true) : ""
    onPowerModeKeyChanged: powerModeApply.restart()
    property Timer powerModeApply: Timer {
        interval: 250
        onTriggered: root.applyPowerMode()
    }
    function applyPowerMode() {
        if (!root.powerModeKey)
            return;
        Backend.request("power.compositor", {
            saver: root.powerSaver,
            refresh: root.setting("saverRefresh", true)
        }, (r, e) => {
            if (e)
                root.message(e.message, "error");
        });
    }
    property real brightness: -1
    readonly property var panels: ["launcher", "clipboard", "control", "notifications", "calendar", "overview", "capture", "settings", "power", "wallpaper", "activity", "system"]
    // The Day hub, the quick-add row or the Logbook, on the focused output: "toggle", "peek" or "logbook".
    signal dayRequested(string output, string mode)
    // Opens the Logbook on a view ("today", "ahead", "site", "tag", "filter", "report", ...) or on one order's sheet.
    signal logbookRequested(string output, string view, var argument, int orderId)
    signal activitySnapshotRequested()
    property var wallpaperChange: ({})
    property bool wallpaperBusy: false
    property bool wallpaperDownloading: false
    signal wallpaperSaved(var entry)
    property string wallpaperError: ""
    signal wallpaperFinished(bool success)
    // Monitor name -> wallpaper path currently shown by hyprpaper.
    property var activeWallpapers: ({})
    function refreshActiveWallpapers() {
        Backend.request("wallpaper.active", {}, (r, e) => {
            if (!e)
                activeWallpapers = r.active || {};
        });
    }
    function applyWallpaper(entry, oldPath, output) {
        if (wallpaperBusy || wallpaperDownloading || !entry) return;
        if (entry.remote) {
            wallpaperDownloading = true;
            wallpaperError = "";
            const monitor = output || screenName || targetScreen();
            const provider = entry.provider === "wallpaperscom" ? "wallpaperscom" : "wallhaven";
            Backend.request(provider + ".download", {id: entry.id, url: entry.downloadUrl || "", name: entry.name}, (saved, error) => {
                wallpaperDownloading = false;
                if (error) { wallpaperError = error.message; return; }
                wallpaperSaved(saved);
                applyWallpaper(Object.assign({}, saved, {remote: false}), oldPath, monitor);
            });
            return;
        }
        wallpaperBusy = true;
        wallpaperError = "";
        wallpaperChange = {path: entry.path, monitor: output || screenName || targetScreen(), oldPath: oldPath || ""};
        wallpaperFallback.restart();
    }
    function commitWallpaper() {
        if (!wallpaperBusy || !wallpaperFallback.running) return;
        wallpaperFallback.stop();
        Backend.request("wallpaper.apply", {path: wallpaperChange.path, monitor: wallpaperChange.monitor}, (r, e) => {
            wallpaperBusy = false;
            wallpaperError = e ? e.message : "";
            if (!e) {
                const active = Object.assign({}, activeWallpapers);
                active[r.monitor || wallpaperChange.monitor] = r.path || wallpaperChange.path;
                activeWallpapers = active;
            }
            wallpaperFinished(!e);
            if (!e) message("Wallpaper applied", "success");
        });
    }
    property Timer wallpaperFallback: Timer {
        interval: 650
        onTriggered: {
            // A missing/unreadable old image must not prevent applying a new one.
            start();
            root.commitWallpaper();
        }
    }
    property Timer wallpaperRestore: Timer {
        property int attempts: 0
        interval: 1500
        // Outputs that failed are retried; the others already show their wallpaper and are skipped.
        onTriggered: Backend.request("wallpaper.restore", {}, (r, e) => {
            if ((e || Object.keys(r.failed || {}).length) && ++attempts < 3) restart();
            else root.refreshActiveWallpapers();
        })
    }
    function setting(key, fallback) {
        return settings[key] === undefined ? fallback : settings[key];
    }
    function setSetting(key, value) {
        const next = Object.assign({}, settings);
        next[key] = value;
        settings = next;
        save.restart();
    }
    // Settings back to their defaults; a pending save goes first so it can't bring old values back.
    function resetSettings(keys, done) {
        if (save.running) {
            save.stop();
            save.triggered();
        }
        Backend.request("settings.reset", {keys: keys}, (r, e) => {
            if (e) {
                message(e.message, "error");
                return;
            }
            settings = r;
            settingsSaved();
            if (done)
                done();
        });
    }
    // Opens Settings on a page, by its name ("Control center") or as typed after `shale settings` (control-center).
    function openSettings(page) {
        open("settings");
        detail = page || "";
    }
    function targetScreen() {
        if (Hyprland.focusedMonitor)
            return Hyprland.focusedMonitor.name;
        const screens = Quickshell.screens;
        return screens.length ? screens[0].name : "";
    }
    function open(name, screen) {
        if (locked || panels.indexOf(name) < 0)
            return;
        detail = "";
        screenName = screen || targetScreen();
        panel = name;
    }
    function toggle(name, screen) {
        const target = screen || targetScreen();
        if (panel === name && screenName === target)
            close();
        else
            open(name, target);
    }
    function close() {
        panel = "";
    }
    function message(text, kind, action) {
        toastKind = kind || "info";
        toastAction = action && action.label && action.run ? action : null;
        toast = text;
        messageTimer.interval = toastKind === "error" || toastAction ? 9000 : 6000;
        messageTimer.restart();
    }
    function fileName(path) {
        return String(path || "").split("/").pop();
    }
    // Every app the shell starts gets its own scope in app.slice, so restarting or crashing the shell never takes
    // it down, and its output goes to the journal under its own name instead of `shale logs`.
    function launch(command, workingDirectory, appId) {
        if (!command || !command.length)
            return;
        const id = String(appId || command[0]).split("/").pop() || "app";
        // systemd unit name escaping: every byte outside [A-Za-z0-9_.] becomes \xNN.
        const escaped = encodeURIComponent(id).replace(/%([0-9A-F]{2})|[^A-Za-z0-9_.]/g,
            (match, hex) => "\\x" + (hex ? hex.toLowerCase() : match.charCodeAt(0).toString(16).padStart(2, "0")));
        // Unique across shell restarts too: a clash would make systemd-run refuse, and the app would silently not start.
        const unit = "app-shale-" + escaped + "-" + Date.now().toString(36) + "-" + Math.floor(Math.random() * 0x7fffffff).toString(36);
        Quickshell.execDetached({
            command: ["systemd-run", "--user", "--scope", "--quiet", "--collect", "--slice=app.slice", "--unit=" + unit, "--",
                      "systemd-cat", "--identifier=" + id, "--"].concat(command),
            environment: childEnvironment,
            workingDirectory: workingDirectory || ""
        });
    }
    // A scope runs as this shell's child and inherits its environment, including the GPU driver choice that
    // `shale run` made for the shell alone (SHALE_CHILD_UNSET); apps get the session's own again.
    readonly property var childEnvironment: {
        const drop = {SHALE_CHILD_UNSET: null};
        for (const name of (Quickshell.env("SHALE_CHILD_UNSET") || "").split(" "))
            if (name)
                drop[name] = null;
        return drop;
    }
    function openUrl(url) {
        if (url)
            launch(["xdg-open", String(url)], "", "xdg-open");
    }
    function openPath(path) {
        if (path)
            openUrl("file://" + String(path).split("/").map(encodeURIComponent).join("/"));
    }
    // A negative value hides the level bar (used for countdowns).
    function osd(label, value, glyph, muted) {
        if (locked)
            return;
        // The control center already shows these levels; a second readout is noise.
        if (panel === "control" && screenName === targetScreen() && (detail === "" || (detail === "audio" && glyph !== "sun")))
            return;
        osdLabel = label;
        osdValue = value;
        osdGlyph = glyph || "volume";
        osdMuted = !!muted;
        osdVisible = true;
        osdSerial++;
        osdTimer.restart();
    }
    function refreshWifi() {
        Backend.request("wifi.list", {}, (r, e) => {
            if (!e)
                wifi = r;
        });
        refreshVpn();
    }
    // NetworkManager's VPN and WireGuard profiles: [{path, name, kind, state: off | connecting | on | disconnecting}].
    property var vpn: ({available: false, connections: []})
    readonly property var activeVpn: (vpn.connections || []).find(connection => connection.state === "on") || null
    function refreshVpn() {
        Backend.request("vpn.list", {}, (r, e) => {
            if (!e)
                vpn = r;
        });
    }
    function refreshProfiles() {
        Backend.request("power.profiles", {}, (r, e) => {
            if (!e)
                profiles = r;
        });
    }
    // {layouts: [{code, variant}], index, name} of the main keyboard; the bar shows it only with two or more layouts.
    property var keyboard: ({layouts: [], index: 0, name: ""})
    function refreshKeyboard() {
        Backend.request("keyboard.get", {}, (r, e) => {
            if (!e)
                root.keyboard = r;
        });
    }
    function nextKeyboardLayout() {
        run("keyboard.next", {}, r => root.keyboard = r);
    }
    // One layout switch reports once per keyboard; read the result once.
    property Timer keyboardRefresh: Timer {
        interval: 150
        onTriggered: root.refreshKeyboard()
    }
    function refreshRecording() {
        Backend.request("capture.record.status", {}, (r, e) => {
            if (!e)
                recording = r;
        });
    }
    function run(method, params, success) {
        Backend.request(method, params || {}, (r, e) => {
            if (!e) {
                if (success)
                    success(r);
            } else if (e.code !== "cancelled" && e.code !== "stopped")
                message(e.message || "Operation failed", "error");
        });
    }
    function screenshot(mode, copy) {
        close();
        const delay = setting("captureDelay", 0);
        delayed.method = "capture.screenshot";
        delayed.params = {
            mode: mode,
            copy: copy,
            delay: delay
        };
        delayed.restart();
        if (delay > 0) {
            countdown.remaining = delay;
            countdown.restart();
            countdown.show();
        }
    }
    function recordingResult(r) {
        if (r.saved)
            message("Recording saved · " + fileName(r.path), "success", {label: "Open", run: () => openPath(r.path)});
        else
            message("Recording stopped. Check the output file.", "error");
    }
    property Timer countdown: Timer {
        property int remaining: 0
        interval: 1000
        repeat: true
        function show() {
            root.osdLabel = "Screenshot in " + remaining;
            root.osdValue = -1;
            root.osdGlyph = "camera";
            root.osdMuted = false;
            root.osdVisible = true;
            root.osdSerial++;
            root.osdTimer.stop();
        }
        onTriggered: {
            if (--remaining > 0) {
                show();
            } else {
                stop();
                // Hide before capture so the countdown never appears in the image.
                root.osdVisible = false;
            }
        }
    }
    function record(mode, audio) {
        close();
        delayed.method = "capture.record.start";
        delayed.params = {
            mode: mode,
            audio: audio
        };
        delayed.restart();
    }
    // Session actions outlive the panel that asked for them, so a refusal can still be reported. Each runs
    // as its own user unit: the lock watcher must survive this shell to hand a crashed lock to hyprlock.
    property Process sessionProcess: Process {
        property string action: ""
        readonly property string script: Paths.localPath(Qt.resolvedUrl("../scripts/session-action"))
        command: ["systemd-run", "--user", "--quiet", "--collect", "--wait", "--", script, action]
        onExited: code => {
            if (code !== 0)
                root.message(({
                        lock: "Could not lock the screen.",
                        logout: "Could not log out.",
                        reboot: "Could not restart. Another user or app may be preventing it.",
                        shutdown: "Could not shut down. Another user or app may be preventing it.",
                        suspend: "Could not suspend. The screen could not be locked first, or the system refused."
                    })[action] || "Could not " + action + ".", "error");
        }
    }
    function sessionAction(name) {
        if (sessionProcess.running) {
            Quickshell.execDetached(["systemd-run", "--user", "--quiet", "--collect", "--", sessionProcess.script, name]);
        } else {
            sessionProcess.action = name;
            sessionProcess.running = true;
        }
    }
    function action(name) {
        if (name === "lock" || name === "suspend") {
            close();
            sessionAction(name);
        } else if (name === "screenshot" || name === "screenshot-region")
            screenshot("region", true);
        else if (name === "screenshot-output")
            screenshot("output", false);
        else if (name === "stop-recording")
            run("capture.record.stop", {}, r => {
                refreshRecording();
                recordingResult(r);
            });
        else if (name === "color") {
            close();
            delayed.method = "color.pick";
            delayed.params = {};
            delayed.restart();
        } else if (name === "locked") {
            if (lockOwner === "shell")
                return;
            lockOwner = "external";
            locked = true;
            close();
            osdVisible = false;
        } else if (name === "unlocked") {
            // An external locker finishing must never drop the shell's own lock screen.
            if (lockOwner !== "shell") {
                lockOwner = "";
                locked = false;
            }
        }
        else if (panels.indexOf(name) >= 0)
            toggle(name);
    }
    property Timer delayed: Timer {
        property string method: ""
        property var params: ({})
        interval: Theme.leave + 180
        onTriggered: root.run(method, params, r => {
            if (method === "capture.record.start")
                root.refreshRecording();
            else if (r && r.color)
                root.message("Color copied · " + r.color, "success");
            else if (r && r.path) {
                const path = r.path;
                root.message((r.copied ? "Screenshot copied and saved · " : "Screenshot saved · ") + root.fileName(path), "success", {label: "Open", run: () => root.openPath(path)});
            } else
                root.message("Done", "success");
        })
    }
    property Timer messageTimer: Timer {
        interval: 6000
        onTriggered: {
            root.toast = "";
            root.toastAction = null;
        }
    }
    property Timer osdTimer: Timer {
        interval: 1600
        onTriggered: root.osdVisible = false
    }
    // The helper has the settings; for example, it records activity only once tracking is saved as on.
    signal settingsSaved()
    // The helper picks the terminal for `>` commands from the settings, so it is asked again after a change.
    property string terminalChoice: "auto"
    onSettingsSaved: if (setting("terminal", "auto") !== terminalChoice) {
        terminalChoice = setting("terminal", "auto");
        Backend.refreshCapabilities();
    }
    property Timer save: Timer {
        interval: 350
        onTriggered: Backend.request("settings.set", {
            settings: root.settings
        }, (r, e) => {
            if (!e)
                root.settingsSaved();
        })
    }
    property bool helperDown: false
    property Timer helperStable: Timer {
        interval: 10000
        onTriggered: root.helperDown = false
    }
    property Connections helper: Connections {
        target: Backend
        function onReadyChanged() {
            if (!Backend.ready) {
                helperStable.stop();
                // One notice per outage, not one per restart attempt of a helper that keeps failing.
                if (!root.helperDown)
                    root.message("Desktop helper stopped; restarting", "error");
                root.helperDown = true;
                return;
            }
            helperStable.restart();
            Backend.request("settings.get", {}, (r, e) => {
                if (!e)
                    root.settings = r.settings || r;
            });
            // Changes made while the helper was down never reached logind. At the shell's own start an
            // unlocked state is left alone: hyprlock may be covering for a shell that died locked.
            if (root.locked || root.helperDown)
                Backend.request("session.lockedHint", {locked: root.locked});
            // The lid inhibitor belongs to the helper process, so a restarted helper starts without one.
            Backend.request("display.lid.get", {}, (r, e) => root.lidAwake = !e && r.enabled);
            root.refreshRecording();
            root.refreshWifi();
            root.refreshProfiles();
            root.refreshKeyboard();
            root.refreshActiveWallpapers();
            wallpaperRestore.attempts = 0;
            wallpaperRestore.restart();
        }
        function onEventReceived(name, data) {
            if (name === "power.profile")
                root.profiles = Object.assign({}, root.profiles, {
                    active: data.active
                });
            if (name === "brightness") {
                root.brightness = data.available ? data.value : -1;
                if (data.available && !data.initial)
                    root.osd("Brightness", data.value, "sun");
            }
        }
    }
    Component.onCompleted: if (Backend.ready) {
        Backend.request("settings.get", {}, (r, e) => {
            if (!e)
                root.settings = r.settings || r;
        });
        root.refreshRecording();
        root.refreshWifi();
        root.refreshProfiles();
        root.refreshKeyboard();
        root.refreshActiveWallpapers();
    }
    // A Hyprland config reload restores blur, shadows and refresh rate; reapply power saver over it.
    property Connections hyprlandReload: Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded" && root.powerSaver)
                root.powerModeApply.restart();
            // A reload may change the layouts.
            if (event.name === "activelayout" || event.name === "configreloaded")
                root.keyboardRefresh.restart();
        }
    }
    // Keeps the bar's Wi-Fi state honest without the full-rate polling of the Wi-Fi page.
    property Timer wifiStatusPoll: Timer {
        // Slower while Wi-Fi is unavailable, so a NetworkManager that starts later is still noticed.
        interval: root.wifiAvailable ? 60000 : 300000
        running: Backend.ready && !root.locked && !(root.panel === "control" && root.detail === "wifi")
        repeat: true
        onTriggered: root.refreshWifi()
    }
    // Elapsed recording time for the bar; ticks only while recording.
    property int recordingSeconds: 0
    property Timer recordingClock: Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: !!root.recording.active
        onTriggered: root.recordingSeconds = root.recording.started ? Math.max(0, Math.floor(Date.now() / 1000 - root.recording.started)) : 0
    }
    property Timer recordingPoll: Timer {
        interval: 2000
        running: root.recording.active
        repeat: true
        onTriggered: root.refreshRecording()
    }
    property Connections screens: Connections {
        target: Quickshell
        function onScreensChanged() {
            if (root.panel && !Quickshell.screens.some(s => s.name === root.screenName))
                root.close();
            // A connected output starts without its saved wallpaper; the timer lets the outputs settle.
            if (Backend.ready) {
                root.wallpaperRestore.attempts = 0;
                root.wallpaperRestore.restart();
            }
        }
    }
    property IpcHandler ipc: IpcHandler {
        target: "shell"
        function status(): string {
            return JSON.stringify({
                panel: root.panel,
                helperReady: Backend.ready,
                lastError: Backend.lastError,
                recording: root.recording.active
            });
        }
        function toggle(panel: string): void {
            root.toggle(panel);
        }
        function close(): void {
            root.close();
        }
        function action(name: string): void {
            root.action(name);
        }
        // Starts the built-in lock screen. Returns this process id, or "" when hyprlock is preferred.
        function lock(): string {
            return root.lockShell() ? String(Quickshell.processId) : "";
        }
        function lockStatus(): string {
            return JSON.stringify({locked: root.locked, owner: root.lockOwner, secure: root.lockSecure, pid: String(Quickshell.processId)});
        }
        // Gives up a lock the compositor never confirmed (for example when another locker is active).
        function abortLock(): void {
            if (root.lockOwner === "shell" && !root.lockSecure) {
                root.lockOwner = "";
                root.locked = false;
            }
        }
        function dnd(state: string): void {
            const on = state === "toggle" ? !root.setting("dnd", false) : state === "on";
            root.setSetting("dnd", on);
            root.osd(on ? "Do not disturb on" : "Do not disturb off", -1, on ? "bell-off" : "bell");
        }
        function day(mode: string): void {
            if (["toggle", "peek", "logbook"].indexOf(mode) >= 0)
                root.dayRequested(root.targetScreen(), mode);
        }
        function settingsPage(name: string): void {
            root.openSettings(name);
        }
        function page(name: string): void {
            if (["wifi", "bluetooth", "audio", "power", "media", "tray", "update"].indexOf(name) < 0)
                return;
            root.open("control");
            root.detail = name;
        }
    }
}
