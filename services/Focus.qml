pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

// Focus sessions and countdown timers. A session holds popups (Do not disturb without touching the user's own
// setting) and ends with a digest of what came in. Both survive a shell restart through settings.
QtObject {
    id: root
    property real startedAt: 0
    property real endsAt: 0
    // Where Activity's record of this session already ends: a session resumed with Undo recorded its first part
    // when it ended, and only the rest is recorded when it ends again.
    property real recordedUntil: 0
    // The work order this session was started on (0 for none): its minutes are logged on it, and the capsule names it.
    property int orderId: 0
    property string orderText: ""
    property real now: Date.now()
    readonly property bool active: endsAt > 0
    readonly property int remainingSeconds: active ? Math.max(0, Math.ceil((endsAt - now) / 1000)) : 0
    readonly property real progress: active && endsAt > startedAt ? Math.max(0, Math.min(1, (endsAt - now) / (endsAt - startedAt))) : 0
    readonly property int lastMinutes: ShellState.setting("focusMinutes", 25)
    // {minutes, total, events, groups: [{appName, appIcon, count, latest}]} after a session that let something in; null otherwise.
    property var digest: null
    // [{id, label, endsAt, seconds}], soonest first.
    property var timers: []
    readonly property var nextTimer: timers.length ? timers[0] : null

    function minutesText(seconds) {
        const minutes = Math.ceil(seconds / 60);
        return minutes >= 60 ? Math.floor(minutes / 60) + "h " + String(minutes % 60).padStart(2, "0") + "m" : minutes + "m";
    }
    function clockText(seconds) {
        const s = Math.max(0, seconds);
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), rest = s % 60;
        return (h ? h + ":" + String(m).padStart(2, "0") : String(m)) + ":" + String(rest).padStart(2, "0");
    }

    function start(minutes, order, text) {
        const length = Math.max(1, Math.min(240, Math.round(Number(minutes) || lastMinutes)));
        now = Date.now();
        if (!active) {
            startedAt = now;
            recordedUntil = 0;
            digest = null;
            orderId = order || 0;
            orderText = order ? String(text || "") : "";
        }
        endsAt = now + length * 60000;
        if ([25, 50, 90].indexOf(length) >= 0)
            ShellState.setSetting("focusMinutes", length);
        persist();
    }
    // Scrolling the bar chip: never below one minute left.
    function extend(minutes) {
        if (!active)
            return;
        now = Date.now();
        endsAt = Math.min(now + 240 * 60000, Math.max(now + 60000, endsAt + minutes * 60000));
        persist();
    }
    function end(early) {
        if (!active)
            return;
        const started = startedAt, ends = endsAt, linked = orderId, linkedText = orderText;
        const finished = Math.min(Date.now(), ends);
        const from = Math.max(started, recordedUntil);
        let recorded = recordedUntil;
        startedAt = 0;
        endsAt = 0;
        recordedUntil = 0;
        orderId = 0;
        orderText = "";
        persist();
        if (ShellState.setting("activityTracking", "ask") === "on" && finished - from >= 60000) {
            Backend.request("activity.focus", {start: from, end: finished});
            recorded = finished;
        }
        const minutes = Math.max(1, Math.round((finished - started) / 60000));
        // Kept per day for the shift report; keyed by the start, so resuming an ended session replaces its end.
        if (finished - started >= 60000)
            Backend.request("day.quiet.log", linked ? {start: started, end: finished, orderId: linked} : {start: started, end: finished}, () => {});
        const missed = Services.notifications.filter(n => !n.transient && n.timestamp >= started);
        if (missed.length) {
            const groups = {};
            for (const n of missed) {
                // Newest first in Services.notifications, so the first record of a group is its latest.
                if (!groups[n.appName])
                    groups[n.appName] = {appName: n.appName, appIcon: n.appIcon || "", count: 0, latest: n.summary || n.body || ""};
                groups[n.appName].count++;
            }
            digest = {minutes: minutes, total: missed.length, events: missed.filter(n => n.event).length,
                      groups: Object.values(groups).sort((a, b) => b.count - a.count || a.appName.localeCompare(b.appName))};
        } else {
            digest = null;
            if (!early)
                ShellState.message(minutes + " min of focus · Nothing missed", "success");
        }
        if (early)
            ShellState.message("Focus ended", "info", {label: "Undo", run: () => root.resume(started, ends, recorded, linked, linkedText)});
        else
            chime();
    }
    function resume(started, ends, recorded, order, text) {
        if (active || ends <= Date.now())
            return;
        digest = null;
        startedAt = started;
        endsAt = ends;
        recordedUntil = recorded || 0;
        orderId = order || 0;
        orderText = text || "";
        now = Date.now();
        persist();
    }
    function persist() {
        const session = {started: startedAt, ends: endsAt};
        if (recordedUntil > startedAt)
            session.recorded = recordedUntil;
        if (orderId)
            Object.assign(session, {order: orderId, orderText: orderText});
        ShellState.setSetting("focusSession", active ? session : {});
    }

    property int timerSerial: 0
    function addTimer(seconds, label) {
        const length = Math.max(1, Math.min(24 * 3600, Math.round(Number(seconds) || 0)));
        now = Date.now();
        timers = timers.concat([{id: ++timerSerial, label: String(label || "").slice(0, 60), endsAt: now + length * 1000, seconds: length}])
            .sort((a, b) => a.endsAt - b.endsAt).slice(0, 10);
        saveTimers();
    }
    function cancelTimer(id) {
        timers = timers.filter(t => t.id !== id);
        saveTimers();
    }
    function saveTimers() {
        ShellState.setSetting("timers", timers.map(t => ({label: t.label, ends: t.endsAt, seconds: t.seconds})));
    }
    function timerDone(timer) {
        cancelTimer(timer.id);
        const name = timer.label ? timer.label : minutesText(timer.seconds) + " timer";
        chime();
        ShellState.message("Time's up · " + name, "success", {label: "+5 min", run: () => root.addTimer(300, timer.label)});
    }
    function chime() {
        ShellState.launch(["sh", "-c", 'f=/usr/share/sounds/freedesktop/stereo/complete.oga; [ -r "$f" ] && command -v pw-play >/dev/null && exec pw-play "$f"'], "", "shale-chime");
    }

    property Timer clock: Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.active || root.timers.length > 0
        onTriggered: {
            root.now = Date.now();
            if (root.active && root.now >= root.endsAt)
                root.end(false);
            for (const timer of root.timers.slice())
                if (root.now >= timer.endsAt)
                    root.timerDone(timer);
        }
    }
    // Settings arrive from the helper after start; pick up a session or timers that were running before a restart.
    property bool restored: false
    // The singleton may be created before or after the settings arrive.
    Component.onCompleted: restore()
    property Connections settingsLoaded: Connections {
        target: ShellState
        function onSettingsChanged() {
            root.restore();
        }
    }
    function restore() {
        if (root.restored || !Object.keys(ShellState.settings).length)
            return;
        root.restored = true;
        const session = ShellState.setting("focusSession", {});
        const current = Date.now();
        if (session && session.ends > current && session.started > 0 && !root.active) {
            root.startedAt = session.started;
            root.endsAt = session.ends;
            root.recordedUntil = session.recorded || 0;
            root.orderId = session.order || 0;
            root.orderText = session.orderText || "";
            root.now = current;
        } else if (session && session.ends)
            ShellState.setSetting("focusSession", {}); // ended while the shell was down
        const saved = ShellState.setting("timers", []);
        root.timers = saved.filter(t => t && t.ends > current - 60000).map(t => ({id: ++root.timerSerial, label: String(t.label || ""), endsAt: t.ends, seconds: t.seconds || 60}))
            .sort((a, b) => a.endsAt - b.endsAt);
    }

    property IpcHandler ipc: IpcHandler {
        target: "focus"
        // 0 starts a session of the last used length.
        function start(minutes: int): void {
            root.start(minutes > 0 ? minutes : root.lastMinutes);
        }
        function end(): void {
            root.end(true);
        }
        function toggle(): void {
            if (root.active)
                root.end(true);
            else
                root.start(root.lastMinutes);
        }
        function timer(seconds: int, label: string): void {
            if (seconds > 0)
                root.addTimer(seconds, label);
        }
        function status(): string {
            return JSON.stringify({active: root.active, remainingSeconds: root.remainingSeconds,
                                   digest: root.digest ? {total: root.digest.total, events: root.digest.events, apps: root.digest.groups.map(g => g.appName)} : null,
                                   timers: root.timers.map(t => ({label: t.label, remainingSeconds: Math.max(0, Math.ceil((t.endsAt - Date.now()) / 1000))}))});
        }
    }
}
