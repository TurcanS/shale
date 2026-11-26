import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../core"
import "../services"
import "../components" as C
import "../core/paths.js" as Paths
import "../core/search.js" as Search
import "../core/parts.js" as Parts
import "../core/format.js" as Format

// Find: one field for apps, open windows, actions, sums and conversions, timers, lines for the desktop note, and the
// prefixed searches (: emoji, / files, ? web, > commands). Results come in groups; chips narrow everything to one kind.
FocusScope {
    id: root
    readonly property string title: "Find"
    // The search field heads the panel.
    readonly property bool showHeader: false
    readonly property int panelWidth: 680
    readonly property int panelHeight: calculatorQuery && results.length === 0 ? (calculationError ? 218 : 188) : 480
    property alias query: search.text
    // All, or only apps, windows or actions; Ctrl+Tab steps through them.
    property string filter: "all"
    readonly property var filters: [{key: "all", text: "All"}, {key: "app", text: "Apps"}, {key: "window", text: "Windows"}, {key: "action", text: "Actions"}]
    function stepFilter(delta) {
        const index = filters.findIndex(f => f.key === filter);
        filter = filters[(index + delta + filters.length) % filters.length].key;
    }
    property string calculation: ""
    property bool calculationValid: false
    property bool calculating: false
    property bool copying: false
    property string calculationError: ""
    property string calculatedExpression: ""
    property int calculationGeneration: 0
    // A query that looked like a conversion but named no known unit ("7 days to die") searches apps instead.
    property string rejectedConversion: ""
    property string rejectedReason: ""
    // A leading character picks what the launcher searches: apps (default), : emoji, / files, ? the web, > a command.
    readonly property string mode: modeOf(query)
    readonly property string term: mode === "apps" ? query.trim() : query.slice(1).trim()
    readonly property bool unitQuery: isConversion(query) && rejectedConversion !== query
    readonly property bool calculatorQuery: isExpression(query) || unitQuery
    readonly property var engines: [
        {key: "duckduckgo", name: "DuckDuckGo", url: "https://duckduckgo.com/?q="},
        {key: "google", name: "Google", url: "https://www.google.com/search?q="},
        {key: "brave", name: "Brave", url: "https://search.brave.com/search?q="}
    ]
    readonly property var engine: engines.find(e => e.key === ShellState.setting("searchEngine", "duckduckgo")) || engines[0]
    readonly property var view: mode === "emoji" ? grid : list
    // Whole minutes, so the results are rebuilt once a minute during a focus session, not every second.
    readonly property int focusMinutesLeft: Math.ceil(Focus.remainingSeconds / 60)
    function modeOf(value) {
        const first = value.charAt(0);
        return first === ":" ? "emoji" : first === "/" ? "files" : first === "?" ? "web" : first === ">" ? "run" : "apps";
    }
    function isExpression(value) {
        const text = value.trim();
        if (modeOf(text) !== "apps")
            return false;
        return text.startsWith("=") || (/^[\d\s.eE+\-*/%()×÷−^]+$/.test(text) && /\d/.test(text) && /[+\-*/%()×÷−^]/.test(text));
    }
    function isConversion(value) {
        return modeOf(value) === "apps" && /^\s*-?(\d+([.,]\d+)?|[.,]\d+)\s*[^\d\s].*?\s+(to|in|as)\s+\S/i.test(value);
    }
    function expression(text) {
        return text.trim().replace(/^=\s*/, "").replace(/×/g, "*").replace(/÷/g, "/").replace(/−/g, "-").replace(/\^/g, "**");
    }
    function copyText(text, message) {
        Backend.request("clipboard.write", {text: text}, (result, error) => {
            if (error)
                ShellState.message(error.message, "error");
            else
                ShellState.message(message, "success");
        });
    }
    function copyCalculation() {
        if (copying || !calculationValid || calculatedExpression !== query)
            return;
        copying = true;
        const generation = calculationGeneration;
        Backend.request("clipboard.write", {text: calculation}, (result, error) => {
            if (!error)
                ShellState.message("Result copied", "success");
            if (!root)
                return;
            copying = false;
            if (error && generation === calculationGeneration)
                calculationError = error.message;
        });
    }
    // Folded once whenever the installed apps change, so typing only scores the term.
    readonly property var apps: DesktopEntries.applications.values.filter(e => !e.noDisplay).map(e => ({
        entry: e, text: Search.prepare({name: e.name, genericName: e.genericName, comment: e.comment, keywords: e.keywords,
                                        id: e.id, startupClass: e.startupClass, command: e.command})
    }))
    // Grouped: each group's first row carries its title in `header`. A search orders the groups by their best match,
    // so Enter still takes the best result; the empty query suggests a few apps, a window and an action, then lists
    // every app.
    readonly property var appResults: {
        if (mode !== "apps" || calculatorQuery) return [];
        const pinned = ShellState.setting("pinnedApps", []);
        const usage = ShellState.setting("appUsage", {});
        const folded = Search.fold(term).trim();
        // An open window edges out launching its app again, even a frequently used one.
        const boost = i => i.kind === "window" ? 400 : i.kind !== "app" ? 0 : (pinned.indexOf(i.key) >= 0 ? (term ? 100 : 100000) : 0) + Search.usageBoost(usage[i.key]);
        const order = (a, b) => b.rank + boost(b) - a.rank - boost(a) || a.name.localeCompare(b.name);
        const wants = kind => filter === "all" || filter === kind;
        const ranked = wants("app") ? root.apps.map(app => ({
            kind: "app", name: app.entry.name, subtitle: app.entry.genericName || app.entry.comment || app.entry.id,
            glyph: app.entry.icon, entry: app.entry, key: app.entry.id, rank: Search.scoreApp(app.text, folded)
        })).filter(i => i.rank > 0).sort(order) : [];
        const windows = wants("window") ? windowResults(folded) : [];
        const actions = wants("action") ? actionResults(folded) : [];
        let groups;
        if (!folded && filter === "all")
            groups = [["Suggested", ranked.slice(0, 3)], ["Open windows", windows.slice(0, 1)], ["Actions", actions.slice(0, 1)], ["All apps", ranked.slice(3)]];
        else {
            // Every app stays reachable from the empty query; a search only needs the best matches.
            groups = [["Apps", term ? ranked.slice(0, 100) : ranked], ["Open windows", windows], ["Actions", actions]];
            if (folded)
                groups.sort((a, b) => (b[1].length ? b[1][0].rank + boost(b[1][0]) : -1) - (a[1].length ? a[1][0].rank + boost(a[1][0]) : -1));
        }
        if (commandResults.length)
            groups.unshift([({timer: "Timer", focus: "Focus", note: "Note"})[commandResults[0].kind], commandResults]);
        return grouped(groups);
    }
    // [[title, rows], …] → one list with the title on each group's first row.
    function grouped(groups) {
        const rows = [];
        for (const [title, items] of groups)
            items.forEach((item, index) => rows.push(Object.assign(item, {header: index === 0 ? title : ""})));
        return rows;
    }
    // "timer 10m tea", "focus 40", "layout evening" and "note buy filters" become one row each, above everything else.
    readonly property var commandResults: {
        if (mode !== "apps")
            return [];
        const timer = Search.timerQuery(query);
        if (timer)
            return [{kind: "timer", key: "timer", name: "Start a " + Focus.minutesText(timer.seconds) + " timer" + (timer.label ? " · " + timer.label : ""),
                     subtitle: "Counts down in the bar and chimes when done", fallback: "timer", seconds: timer.seconds, label: timer.label}];
        const minutes = Search.focusQuery(query);
        if (minutes)
            return [{kind: "focus", key: "focus", name: "Focus for " + minutes + " min", subtitle: "Holds notifications, then sums them up",
                     fallback: "focus", minutes: minutes}];
        const layoutName = Search.layoutQuery(query);
        if (layoutName !== null) {
            const key = Parts.layoutNamed(layoutName);
            const saved = Parts.clean(ShellState.setting("widgetSaved", []));
            const layout = Parts.layouts.find(item => item.id === key);
            const cards = key === "mine" ? saved : layout ? layout.cards : [];
            if (cards.length)
                return [{kind: "layout", key: "layout", name: "Use the " + (layout ? layout.title : "Mine") + " layout",
                         subtitle: cards.map(id => Parts.find(id).title).join(", ") + (ShellState.setting("widgets", false) ? "" : " · turns widgets on"),
                         fallback: "widgets", cards: cards}];
        }
        const line = Search.noteQuery(query);
        if (line)
            return [{kind: "note", key: "note", name: line, fallback: "note", text: line,
                     subtitle: noteShown ? "Add to the note on the desktop" : "Add to the note · Settings → Desktop shows it"}];
        return [];
    }
    // Whether the desktop shows the Note card, for the footer hint and the note row's line.
    readonly property bool noteShown: ShellState.setting("widgets", false) && ShellState.setting("widgetCards", ["clock", "sky", "note", "system"]).indexOf("note") >= 0
    // Open windows by their app and title; with no search, all of them, the most recently used first.
    function windowResults(folded) {
        const results = [];
        for (const window of Services.windows) {
            const appId = window.wayland ? window.wayland.appId || "" : (window.lastIpcObject || {}).class || "";
            const rank = folded ? Search.scoreWindow(window.title, appId, folded) : 1;
            if (rank <= 0)
                continue;
            const entry = appId && DesktopEntries.heuristicLookup ? DesktopEntries.heuristicLookup(appId) : null;
            const app = entry ? entry.name : appId || "Window";
            const workspace = window.workspace ? (window.workspace.id > 0 ? "Page " + window.workspace.id : String(window.workspace.name || "").replace(/^special:/, "")) : "";
            const recent = (window.lastIpcObject || {}).focusHistoryID;
            results.push({kind: "window", key: "window:" + window.address, name: app, subtitle: window.title || "", hint: workspace,
                          glyph: entry ? entry.icon : appId, fallback: "window", window: window, rank: rank,
                          // The window under Find is where you already are; suggest the one before it.
                          recent: window.activated ? 1000 : recent === undefined || recent < 0 ? 999 : recent});
        }
        return results.sort((a, b) => b.rank - a.rank || a.recent - b.recent).slice(0, folded ? 5 : results.length);
    }
    function actionResults(folded) {
        return Search.ACTIONS.map(action => ({kind: "action", key: "action:" + action.key, action: action.key, name: action.name,
                                              subtitle: actionSubtitle(action.key), fallback: action.glyph, rank: folded ? Search.scoreAction(action, folded) : 1}))
            .filter(item => item.rank > 0).sort((a, b) => b.rank - a.rank || Search.ACTIONS.findIndex(x => x.key === a.action) - Search.ACTIONS.findIndex(x => x.key === b.action));
    }
    function actionSubtitle(key) {
        if (key.startsWith("power:"))
            return "Opens the session menu";
        if (key === "focus")
            return Focus.active ? "End focus · " + Focus.minutesText(focusMinutesLeft * 60) + " left" : "Focus for " + Focus.lastMinutes + " minutes";
        if (key === "dnd")
            return ShellState.setting("dnd", false) ? "Turn off" : "Turn on";
        return key.startsWith("page:") ? "Control" : key.startsWith("settings:") ? "Settings" : "Shale";
    }
    function runAction(key) {
        const [kind, name] = key.split(":");
        if (kind === "power")
            ShellState.open("power");
        else if (kind === "page") {
            ShellState.open("control");
            ShellState.detail = name;
        } else if (kind === "panel")
            ShellState.open(name);
        else if (kind === "settings")
            ShellState.openSettings(name);
        else if (key === "lock" || key === "suspend" || key === "color")
            ShellState.action(key);
        else {
            ShellState.close();
            if (key === "screenshot")
                ShellState.action("screenshot");
            else if (key === "focus")
                Focus.active ? Focus.end(true) : Focus.start(Focus.lastMinutes);
            else if (key === "dnd")
                ShellState.setSetting("dnd", !ShellState.setting("dnd", false));
        }
    }

    // Commands: ">" runs one in its own scope, Shift+Enter in a terminal. The last 20 are kept.
    readonly property var runResults: {
        if (mode !== "run") return [];
        const history = ShellState.setting("runHistory", []);
        const results = term ? [{kind: "run", key: "run", name: term, subtitle: "Shift+Enter runs it in a terminal", fallback: "terminal", command: term}] : [];
        const folded = Search.fold(term);
        const recent = [];
        for (const command of history)
            if (command !== term && Search.fold(command).indexOf(folded) >= 0)
                recent.push({kind: "run", key: "history:" + command, name: command, subtitle: "", fallback: "terminal", command: command});
        return grouped([["Run a command", results], ["Recent commands", recent]]);
    }
    function runCommand(command, inTerminal) {
        if (inTerminal) {
            const terminal = Backend.capabilities.terminal || [];
            if (!terminal.length) {
                ShellState.message("Install a terminal, such as foot or kitty, or set $TERMINAL.", "error");
                return false;
            }
            // The shell stays open afterwards, so the output can be read.
            ShellState.launch(terminal.concat(["sh", "-c", command + '\nexec "${SHELL:-sh}"']), "", "shale-run");
        } else
            ShellState.launch(["sh", "-c", command], "", "shale-run");
        ShellState.setSetting("runHistory", [command].concat(ShellState.setting("runHistory", []).filter(c => c !== command)).slice(0, 20));
        return true;
    }

    // Emoji: bundled data (scripts/build-emoji.py), loaded the first time the picker is used.
    property var emojiData: []
    property bool emojiWanted: false
    property bool colorEmoji: true
    onModeChanged: if (mode === "emoji" && !emojiWanted) {
        emojiWanted = true;
        fontCheck.running = true;
    }
    FileView {
        path: root.emojiWanted ? Paths.localPath(Qt.resolvedUrl("../assets/emoji.json")) : ""
        onLoaded: {
            try {
                // Lowercased once here instead of for every emoji on every keystroke.
                root.emojiData = JSON.parse(text()).map(item => Object.assign(item, {nl: item.n.toLowerCase(), all: (item.n + " " + item.k).toLowerCase()}));
            } catch (error) {
                root.emojiData = [];
            }
        }
    }
    Process {
        id: fontCheck
        command: ["sh", "-c", "fc-list ':color=true:charset=1f600' family | grep -q ."]
        onExited: code => root.colorEmoji = code === 0
    }
    readonly property var emojiResults: {
        if (mode !== "emoji") return [];
        const usage = ShellState.setting("emojiUsage", {});
        const words = term.toLowerCase().split(/\s+/).filter(w => !!w);
        const matches = [];
        for (const item of emojiData) {
            // Names keep their case for display ("OK hand", "flag: Germany"); matching ignores it.
            const name = item.n, folded = item.nl, all = item.all;
            let rank = 0;
            if (words.length) {
                if (!words.every(w => all.indexOf(w) >= 0)) continue;
                rank = folded === words.join(" ") ? 400 : folded.startsWith(words[0]) ? 300 : (" " + folded).indexOf(" " + words[0]) >= 0 ? 200 : 100;
            }
            matches.push({kind: "emoji", key: item.e, emoji: item.e, name: name, subtitle: "", rank: rank + Math.min(50, (usage[item.e] || 0) * 5), order: matches.length});
        }
        // Stable: equal ranks keep Unicode's order, so recent emoji lead and the rest stay grouped.
        return matches.sort((a, b) => b.rank - a.rank || a.order - b.order);
    }

    // Files: fd through the backend, debounced; late answers for older queries are ignored.
    property var fileResults: []
    property bool filesBusy: false
    property string filesError: ""
    property int filesGeneration: 0
    function searchFiles() {
        const request = ++filesGeneration;
        const text = term;
        if (!text) {
            fileResults = [];
            filesBusy = false;
            filesError = "";
            return;
        }
        filesBusy = true;
        Backend.request("files.search", {query: text}, (r, e) => {
            if (request !== filesGeneration)
                return;
            filesBusy = false;
            filesError = e ? e.message : "";
            fileResults = e ? [] : grouped([["Files in your home folder", r.results.map(f => ({kind: "file", key: f.path, name: f.name, subtitle: f.folder, path: f.path, directory: f.directory, glyph: fileIcon(f), fallback: f.directory ? "folder" : "text"}))]]);
        }, {owner: root});
    }
    function fileIcon(file) {
        if (file.directory) return "folder";
        const extension = file.name.indexOf(".") > 0 ? file.name.split(".").pop().toLowerCase() : "";
        const kinds = {image: ["png", "jpg", "jpeg", "webp", "gif", "svg", "bmp", "avif"], audio: ["mp3", "flac", "ogg", "opus", "wav", "m4a"],
            video: ["mp4", "mkv", "webm", "mov", "avi"], package: ["zip", "tar", "gz", "xz", "zst", "7z", "rar"]};
        for (const kind in kinds)
            if (kinds[kind].indexOf(extension) >= 0)
                return kind + "-x-generic";
        return extension === "pdf" ? "application-pdf" : "text-x-generic";
    }
    Timer {
        id: filesTimer
        interval: 180
        onTriggered: root.searchFiles()
    }

    readonly property var webResults: {
        if (mode !== "web" || !term) return [];
        const results = [];
        // An address opens directly; "node.js" and other file-like names are searched.
        if (Search.isAddress(term))
            results.push({kind: "web", key: "url", name: "Open " + term, subtitle: "Website", fallback: "link", url: Search.addressUrl(term)});
        results.push({kind: "web", key: "search", name: term, subtitle: "Search " + engine.name, fallback: "search", url: engine.url + encodeURIComponent(term)});
        return grouped([["Web", results]]);
    }
    readonly property var results: mode === "emoji" ? emojiResults : mode === "files" ? fileResults : mode === "web" ? webResults : mode === "run" ? runResults : appResults

    function activate(item, modifiers) {
        if (!item) return;
        if (item.kind === "emoji") {
            const usage = Object.assign({}, ShellState.setting("emojiUsage", {}));
            usage[item.emoji] = Math.min(1000, (usage[item.emoji] || 0) + 1);
            // Keep the 60 most used so the setting stays small.
            const kept = {};
            for (const key of Object.keys(usage).sort((a, b) => usage[b] - usage[a]).slice(0, 60))
                kept[key] = usage[key];
            ShellState.setSetting("emojiUsage", kept);
            copyText(item.emoji, "Copied " + item.emoji + " " + item.name);
        } else if (item.kind === "file") {
            if (modifiers & Qt.ShiftModifier)
                copyText(item.path, "Path copied · " + item.name);
            else if (modifiers & Qt.ControlModifier)
                ShellState.openPath(item.directory ? item.path : item.path.slice(0, item.path.lastIndexOf("/")) || "/");
            else
                ShellState.openPath(item.path);
        } else if (item.kind === "web") {
            ShellState.openUrl(item.url);
        } else if (item.kind === "window") {
            Services.focusWindow(item.window);
        } else if (item.kind === "action") {
            runAction(item.action);
            return;
        } else if (item.kind === "timer") {
            Focus.addTimer(item.seconds, item.label);
        } else if (item.kind === "focus") {
            Focus.start(item.minutes);
        } else if (item.kind === "layout") {
            ShellState.setSetting("widgetCards", item.cards);
            if (!ShellState.setting("widgets", false))
                ShellState.setSetting("widgets", true);
        } else if (item.kind === "note") {
            Note.add(item.text, () => ShellState.message("Added to the note", "success"));
        } else if (item.kind === "run") {
            if (!runCommand(item.command, modifiers & Qt.ShiftModifier))
                return;
        } else {
            if (!item.entry.runInTerminal) {
                ShellState.launch(item.entry.command, item.entry.workingDirectory, item.entry.id);
            } else {
                // The helper picks $TERMINAL, xdg-terminal-exec or an installed terminal, with its own argument style.
                const terminal = Backend.capabilities.terminal || [];
                if (!terminal.length) {
                    ShellState.message(item.name + " runs in a terminal. Install one, such as foot or kitty, or set $TERMINAL.", "error");
                    return;
                }
                ShellState.launch(terminal.concat(item.entry.command), item.entry.workingDirectory, item.entry.id);
            }
            const usage = Object.assign({}, ShellState.setting("appUsage", {}));
            usage[item.key] = Math.min(1000, (usage[item.key] || 0) + 1);
            // Keep the 200 most used so uninstalled apps don't pile up in the setting.
            const kept = {};
            for (const key of Object.keys(usage).sort((a, b) => usage[b] - usage[a]).slice(0, 200))
                kept[key] = usage[key];
            ShellState.setSetting("appUsage", kept);
        }
        ShellState.close();
    }
    function pin(item) {
        const pins = ShellState.setting("pinnedApps", []);
        ShellState.setSetting("pinnedApps", pins.indexOf(item.key) < 0 ? pins.concat([item.key]) : pins.filter(k => k !== item.key));
    }
    function cycleEngine() {
        const index = engines.indexOf(engine);
        ShellState.setSetting("searchEngine", engines[(index + 1) % engines.length].key);
    }
    // Rows rebuilt under a resting pointer must not steal keyboard selection;
    // only real pointer movement selects.
    property point lastPointer: Qt.point(-1, -1)
    function pointerMoved(position) {
        const moved = lastPointer.x >= 0 && (Math.abs(position.x - lastPointer.x) > 1 || Math.abs(position.y - lastPointer.y) > 1);
        lastPointer = position;
        return moved;
    }
    function moveSelection(amount) {
        if (!view.count) return;
        select(Math.max(0, Math.min(view.count - 1, view.currentIndex + amount)));
        view.positionViewAtIndex(view.currentIndex, view === grid ? GridView.Contain : ListView.Contain);
    }
    // The user's choice of row; selectedKey follows only this, never a view resetting itself to row 0.
    function select(index) {
        view.currentIndex = index;
        selectedKey = results[index] ? results[index].key : "";
    }
    // A re-sort for the same query (pinning, a settings write) keeps the selected item; a new query starts at the top.
    property string selectedKey: ""
    property string resultsQuery: ""
    onResultsChanged: {
        const sameQuery = query === resultsQuery;
        resultsQuery = query;
        if (!sameQuery)
            selectedKey = "";
        // After the views have taken the new model, which resets their currentIndex to 0.
        Qt.callLater(restoreSelection);
    }
    function restoreSelection() {
        const kept = selectedKey ? results.findIndex(item => item.key === selectedKey) : -1;
        const index = kept >= 0 ? kept : results.length ? 0 : -1;
        list.currentIndex = mode !== "emoji" ? index : -1;
        grid.currentIndex = mode === "emoji" ? index : -1;
        selectedKey = results[index] ? results[index].key : "";
        if (kept >= 0)
            view.positionViewAtIndex(kept, view === grid ? GridView.Contain : ListView.Contain);
    }
    // The at-a-glance strip over the empty query: today, the weather Clock and sky keeps (cached by the backend, never
    // fetched for this), the battery and a running focus session.
    readonly property var weather: Weather.forecast
    // The Note card opens Find with "note " typed (as ShellState.detail), so Enter adds the line.
    function prefill() {
        if (ShellState.panel === "launcher" && ShellState.detail !== "")
            search.text = ShellState.detail;
    }
    Component.onCompleted: prefill()
    Connections {
        target: ShellState
        function onDetailChanged() {
            root.prefill();
        }
    }
    readonly property var glance: {
        const items = [{glyph: "calendar", text: Qt.formatDate(new Date(), "dddd d MMMM")}];
        const current = weather && weather.current;
        if (current && current.temperature !== null && current.temperature !== undefined)
            items.push({glyph: current.icon || "cloud", text: current.temperature + "° " + String(current.label || "").toLowerCase()});
        if (Services.batteryAvailable) {
            const seconds = Services.batterySeconds;
            const span = Format.shortSpan(seconds);
            items.push({glyph: Services.batteryCharging ? "bolt" : "battery",
                        text: Math.round(Services.batteryPercent) + "%" + (Services.batteryCharging ? " · charging" : span ? " · " + span + " left" : "")});
        }
        if (Focus.active)
            items.push({glyph: "focus", text: "Focus · " + Focus.minutesText(Focus.remainingSeconds) + " left"});
        return items;
    }
    // What Enter does to the selected row, for its hint and the footer.
    function verb(item) {
        if (!item)
            return "Open";
        return ({window: "Switch", emoji: "Copy", run: "Run", timer: "Start", focus: "Start", note: "Add"})[item.kind] || "Open";
    }
    readonly property var current: mode === "emoji" ? results[grid.currentIndex] : results[list.currentIndex]
    // Footer key hints for the mode, with the prefixes on an empty query.
    readonly property var footerKeys: {
        if (calculatorQuery)
            return [{key: "↵", text: "Copy"}];
        if (mode === "emoji")
            return [{key: "↑↓←→", text: "Move"}, {key: "↵", text: "Copy"}];
        if (mode === "files")
            return [{key: "↵", text: "Open"}, {key: "Ctrl ↵", text: "Folder"}, {key: "Shift ↵", text: "Copy path"}];
        if (mode === "web")
            return [{key: "↵", text: "Open"}, {key: "Tab", text: "Engine"}];
        if (mode === "run")
            return [{key: "↵", text: "Run"}, {key: "Shift ↵", text: "In a terminal"}];
        const keys = [{key: "↑↓", text: "Move"}, {key: "↵", text: verb(current)}];
        if (current && current.kind === "app")
            keys.push({key: "Ctrl P", text: ShellState.setting("pinnedApps", []).indexOf(current.key) >= 0 ? "Unpin" : "Pin"});
        return keys;
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        // The 60 px search row across the top of the case, with a hairline under it from edge to edge.
        Item {
            Layout.fillWidth: true
            implicitHeight: 60 - Theme.casePadding
            C.Icon {
                id: searchIcon
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -Theme.casePadding / 2
                name: "search"
                size: 20
                color: Theme.textDim
            }
            C.Field {
                id: search
                anchors.left: searchIcon.right
                anchors.leftMargin: Theme.gapM
                anchors.right: clear.visible ? clear.left : escHint.left
                anchors.rightMargin: Theme.gapS
                anchors.verticalCenter: searchIcon.verticalCenter
                focus: true
                leftPadding: 0
                rightPadding: 0
                font.pixelSize: 18
                placeholderText: "Search apps, windows and actions…"
                background: Item {}
                onTextChanged: {
                    ++root.calculationGeneration;
                    root.calculationValid = false;
                    root.calculation = "";
                    root.calculationError = "";
                    root.calculatedExpression = "";
                    root.calculating = root.isExpression(text) || (root.isConversion(text) && root.rejectedConversion !== text);
                    if (root.calculating) calcTimer.restart();
                    else calcTimer.stop();
                    if (root.modeOf(text) === "files") {
                        root.filesBusy = text.slice(1).trim() !== "";
                        filesTimer.restart();
                    } else {
                        filesTimer.stop();
                        ++root.filesGeneration;
                        root.fileResults = [];
                        root.filesBusy = false;
                        root.filesError = "";
                    }
                }
                Keys.onDownPressed: root.moveSelection(root.mode === "emoji" ? 8 : 1)
                Keys.onUpPressed: root.moveSelection(root.mode === "emoji" ? -8 : -1)
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) {
                        root.moveSelection((event.key === Qt.Key_PageDown ? 1 : -1) * (root.mode === "emoji" ? 32 : 6));
                        event.accepted = true;
                    } else if (root.mode === "emoji" && (event.key === Qt.Key_Left || event.key === Qt.Key_Right) && event.modifiers === Qt.NoModifier) {
                        // The grid owns left and right; the query is short enough to edit without them.
                        root.moveSelection(event.key === Qt.Key_Right ? 1 : -1);
                        event.accepted = true;
                    } else if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && (event.modifiers & Qt.ControlModifier) && root.mode === "apps" && !root.calculatorQuery) {
                        root.stepFilter(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1);
                        event.accepted = true;
                    } else if (root.mode === "web" && event.key === Qt.Key_Tab) {
                        root.cycleEngine();
                        event.accepted = true;
                    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) && (root.mode === "files" || root.mode === "run")) {
                        root.activate(root.results[list.currentIndex], event.modifiers);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier) && root.mode === "apps" && !root.calculatorQuery && root.results[list.currentIndex]
                               && root.results[list.currentIndex].kind === "app") {
                        root.pin(root.results[list.currentIndex]);
                        event.accepted = true;
                    }
                }
                onAccepted: {
                    if (root.calculatorQuery) root.copyCalculation();
                    else root.activate(root.results[root.view.currentIndex], Qt.NoModifier);
                }
            }
            C.Button {
                id: clear
                visible: search.text !== ""
                anchors.right: escHint.left
                anchors.rightMargin: Theme.gapS
                anchors.verticalCenter: searchIcon.verticalCenter
                implicitWidth: 28
                implicitHeight: 28
                glyph: "close"
                hint: "Clear search"
                flat: true
                foreground: hovered || visualFocus ? Theme.text : Theme.textDim
                onClicked: { search.clear(); search.forceActiveFocus(); }
            }
            C.KeyHint {
                id: escHint
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: searchIcon.verticalCenter
                text: "Esc"
                textColor: Theme.textDim
            }
            Rectangle {
                anchors.bottom: parent.bottom
                x: -Theme.casePadding
                width: parent.width + 2 * Theme.casePadding
                height: 1
                color: Theme.hairline
            }
        }
        // Filter chips for everything; the engine for "?" searches (Tab switches it); the mode for the other prefixes.
        RowLayout {
            visible: !root.calculatorQuery
            Layout.fillWidth: true
            Layout.topMargin: 10
            Layout.bottomMargin: 4
            spacing: 6
            Repeater {
                model: root.mode === "apps" ? root.filters : root.mode === "web" ? root.engines.map(e => ({key: e.key, text: e.name})) : []
                C.Chip {
                    required property var modelData
                    text: modelData.text
                    selected: root.mode === "web" ? root.engine.key === modelData.key : root.filter === modelData.key
                    focusPolicy: Qt.NoFocus
                    Accessible.role: Accessible.RadioButton
                    Accessible.checked: selected
                    onClicked: {
                        if (root.mode === "web")
                            ShellState.setSetting("searchEngine", modelData.key);
                        else
                            root.filter = modelData.key;
                        search.forceActiveFocus();
                    }
                }
            }
            // A prefix search names itself; the chip takes the prefix away again.
            C.Chip {
                visible: root.mode !== "apps" && root.mode !== "web"
                text: ({emoji: "Emoji", files: "Files", run: "Run"})[root.mode] || ""
                glyph: "close"
                selected: true
                focusPolicy: Qt.NoFocus
                hint: "Back to everything"
                onClicked: {
                    search.clear();
                    search.forceActiveFocus();
                }
            }
            Item {
                Layout.fillWidth: true
            }
            C.KeyHint {
                visible: root.mode === "apps" || root.mode === "web"
                text: root.mode === "web" ? "Tab" : "Ctrl Tab"
                textColor: Theme.textFaint
            }
        }
        Rectangle {
            visible: root.mode === "emoji" && !root.colorEmoji
            Layout.fillWidth: true
            Layout.topMargin: 6
            implicitHeight: fontHint.implicitHeight + 16
            radius: Theme.radiusCard
            color: Theme.module
            C.Label {
                id: fontHint
                anchors.fill: parent
                anchors.margins: 8
                anchors.leftMargin: 12
                text: "Emoji are shown without colour. Install noto-fonts-emoji for full-colour emoji."
                color: Theme.textMuted
                font.pixelSize: Theme.small
                wrapMode: Text.WordWrap
                verticalAlignment: Text.AlignVCenter
            }
        }
        // A sum or conversion: the query, its result, and Enter copies it.
        Rectangle {
            visible: root.calculatorQuery
            Layout.fillWidth: true
            Layout.topMargin: 8
            implicitHeight: 60
            radius: Theme.radiusCard
            color: Theme.accentSoft
            border.width: 1
            border.color: Theme.accentLine
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 8
                spacing: 14
                C.Label {
                    text: root.query.trim().replace(/^=\s*/, "")
                    color: Theme.textSecondary
                    font.pixelSize: 15
                    Layout.maximumWidth: parent.width * 0.4
                }
                C.Label {
                    text: "="
                    color: Theme.textDim
                    font.pixelSize: 15
                }
                C.Label {
                    text: root.calculationValid ? root.calculation : root.calculating ? "…" : root.unitQuery ? "Check the units" : "Check your expression"
                    color: root.calculationValid ? Theme.text : Theme.textDim
                    font.pixelSize: root.calculationValid ? 26 : 16
                    font.weight: root.calculationValid ? 650 : Font.Normal
                    font.features: ({"tnum": 1})
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 16
                    Layout.fillWidth: true
                }
                C.Button {
                    text: root.copying ? "Copying…" : "Copy"
                    glyph: "copy"
                    flat: true
                    labelSize: 12
                    implicitHeight: 32
                    enabled: root.calculationValid && !root.copying
                    onClicked: root.copyCalculation()
                }
            }
        }
        C.Label {
            visible: root.calculationError !== "" && !root.calculating
            text: root.calculationError
            color: Theme.dangerText
            font.pixelSize: Theme.label
            Layout.fillWidth: true
            Layout.topMargin: Theme.gapS
            Layout.leftMargin: 4
            wrapMode: Text.WordWrap
        }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 6
            // Rows reach 8 px from the case edge, so their text lines up with the field above.
            ListView {
                id: list
                x: -6
                width: parent.width + 12
                height: parent.height
                visible: !root.calculatorQuery && root.mode !== "emoji"
                clip: true
                model: root.mode !== "emoji" && !root.calculatorQuery ? root.results : []
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: Theme.fast
                ScrollBar.vertical: C.ScrollBar {}
                header: Item {
                    width: list.width
                    height: glanceStrip.visible ? glanceStrip.height + 6 : 0
                    Rectangle {
                        id: glanceStrip
                        visible: root.mode === "apps" && root.query.trim() === "" && root.filter === "all"
                        x: 6
                        y: 2
                        width: parent.width - 12
                        height: 34
                        radius: Theme.radiusCard
                        color: Theme.module
                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 18
                            Repeater {
                                model: root.glance
                                Row {
                                    required property var modelData
                                    spacing: 6
                                    C.Icon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: parent.modelData.glyph
                                        size: 14
                                        color: Theme.textSecondary
                                    }
                                    C.Label {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: parent.modelData.text
                                        color: Theme.textSecondary
                                        font.pixelSize: 13
                                        font.features: ({"tnum": 1})
                                    }
                                }
                            }
                        }
                    }
                }
                delegate: Column {
                    id: entry
                    required property var modelData
                    required property int index
                    readonly property bool current: ListView.isCurrentItem
                    width: list.width
                    // Opening Find, the results cascade in under the field.
                    opacity: arrive.shown
                    transform: C.Cascade {
                        id: arrive
                        panel: "launcher"
                        order: entry.index
                        dy: 8
                        limit: 8
                    }
                    C.Label {
                        visible: entry.modelData.header !== ""
                        width: parent.width
                        height: 24
                        leftPadding: 12
                        topPadding: 4
                        text: entry.modelData.header || ""
                        color: Theme.textDim
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    C.ListRow {
                        id: row
                        readonly property bool pinned: entry.modelData.kind === "app" && ShellState.setting("pinnedApps", []).indexOf(entry.modelData.key) >= 0
                        readonly property string iconSource: {
                            const icon = entry.modelData.glyph || "";
                            if (icon.startsWith("/")) return "file://" + icon;
                            if (icon.startsWith("file:")) return icon;
                            return icon && Quickshell.hasThemeIcon(icon) ? Quickshell.iconPath(icon) : "";
                        }
                        width: parent.width
                        height: 42
                        topPadding: 6
                        bottomPadding: 6
                        quiet: true
                        inline: true
                        tileImage: true
                        image: iconSource
                        glyph: entry.modelData.fallback || "grid"
                        text: entry.modelData.name
                        subtitle: entry.modelData.subtitle !== entry.modelData.name ? entry.modelData.subtitle || "" : ""
                        selected: entry.current
                        checkmark: false
                        activeFocusOnTab: entry.current
                        Accessible.name: entry.modelData.kind === "web" ? entry.modelData.subtitle + ": " + entry.modelData.name
                            : entry.modelData.kind === "window" ? "Switch to " + entry.modelData.name + ": " + entry.modelData.subtitle : entry.modelData.name
                        onClicked: root.activate(entry.modelData, Qt.NoModifier)
                        HoverHandler {
                            onPointChanged: if (hovered && root.pointerMoved(point.scenePosition)) root.select(entry.index)
                        }
                        Keys.onReturnPressed: event => root.activate(entry.modelData, event.modifiers)
                        trailing: [
                            C.Button {
                                visible: entry.modelData.kind === "app"
                                glyph: "pin"
                                flat: true
                                selected: row.pinned
                                // Shown for the pinned, hovered, or selected row only; the rest stay quiet.
                                opacity: row.pinned || row.hovered || entry.current || row.visualFocus || visualFocus ? 1 : 0
                                activeFocusOnTab: entry.current
                                hint: (row.pinned ? "Unpin " : "Pin ") + entry.modelData.name
                                implicitWidth: 28
                                implicitHeight: 28
                                onClicked: root.pin(entry.modelData)
                                Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                            },
                            C.Label {
                                visible: text !== ""
                                text: entry.current ? root.verb(entry.modelData) + " ↵" : entry.modelData.hint || ""
                                color: entry.current ? Theme.accentText : Theme.textDim
                                font.pixelSize: 12
                                elide: Text.ElideNone
                                Layout.rightMargin: 2
                            }
                        ]
                    }
                }
                C.EmptyState {
                    anchors.centerIn: parent
                    width: parent.width - 40
                    visible: list.count === 0 && !root.calculatorQuery && root.mode !== "emoji"
                    glyph: root.mode === "files" ? "folder" : root.mode === "run" ? "terminal" : "search"
                    title: root.mode === "files" ? (!root.term ? "Search your files" : root.filesBusy ? "Searching…" : root.filesError ? "Search failed" : "No matching files")
                        : root.mode === "web" ? "Search the web"
                        : root.mode === "run" ? "Run a command"
                        : root.filter === "window" && !root.query.trim() ? "No open windows"
                        : root.query.trim() ? "Nothing matches" : "No apps available"
                    description: root.mode === "files" ? (root.filesError || (!root.term ? "Type part of a file or folder name." : root.filesBusy ? "" : "Hidden and ignored files are skipped."))
                        : root.mode === "web" ? "Type what you are looking for after the question mark."
                        : root.mode === "run" ? "Type a command after the >. Shift+Enter runs it in a terminal."
                        : root.rejectedConversion === root.query ? root.rejectedReason + " Nothing else matches either."
                        : root.query.trim() ? (root.filter !== "all" ? "Try All, or ? to search the web." : "Try ? to search the web.")
                        : root.filter === "window" ? "" : "Installed applications will appear here."
                }
            }
            GridView {
                id: grid
                readonly property int columns: 8
                anchors.fill: parent
                visible: root.mode === "emoji"
                clip: true
                // Bound to the emoji list itself: `results` switches to app rows a moment before `mode` empties this grid.
                model: root.emojiResults
                cellWidth: Math.floor(width / columns)
                cellHeight: Math.min(cellWidth, 60)
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                ScrollBar.vertical: C.ScrollBar {}
                delegate: AbstractButton {
                    id: cell
                    required property var modelData
                    required property int index
                    width: grid.cellWidth
                    height: grid.cellHeight
                    hoverEnabled: true
                    Accessible.name: modelData.name
                    onClicked: root.activate(modelData, Qt.NoModifier)
                    HoverHandler {
                        onPointChanged: if (hovered && root.pointerMoved(point.scenePosition)) root.select(cell.index)
                    }
                    background: Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: Theme.radiusCard
                        color: cell.GridView.isCurrentItem ? Theme.accentSoft : cell.down || cell.hovered ? Theme.keyWash(cell.down) : "transparent"
                        border.width: cell.GridView.isCurrentItem ? 1 : 0
                        border.color: Theme.accentLine
                    }
                    contentItem: Text {
                        text: cell.modelData.emoji
                        font.pixelSize: 28
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: Theme.text
                    }
                }
                C.EmptyState {
                    anchors.centerIn: parent
                    width: parent.width - 40
                    visible: grid.count === 0
                    glyph: "search"
                    title: root.emojiData.length ? "No matching emoji" : "Loading emoji…"
                    description: root.emojiData.length ? "Try a simpler word, such as heart or smile." : ""
                }
            }
        }
        // Key hints, the prefixes on an empty query, and the count; a hairline above it from edge to edge.
        Item {
            Layout.fillWidth: true
            implicitHeight: 40 - Theme.casePadding
            Rectangle {
                anchors.top: parent.top
                x: -Theme.casePadding
                width: parent.width + 2 * Theme.casePadding
                height: 1
                color: Theme.hairline
            }
            RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 2
                anchors.rightMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: Theme.casePadding / 2
                spacing: 16
                Repeater {
                    model: root.footerKeys
                    RowLayout {
                        required property var modelData
                        spacing: 6
                        C.KeyHint {
                            text: parent.modelData.key
                        }
                        C.Label {
                            text: parent.modelData.text
                            color: Theme.textDim
                            font.pixelSize: 12
                            elide: Text.ElideNone
                        }
                    }
                }
                // Each prefix starts that search when clicked.
                Row {
                    visible: root.mode === "apps" && root.query === ""
                    spacing: 0
                    Repeater {
                        model: [{prefix: "=", text: "= sums", label: "Calculate"}, {prefix: "?", text: "? web", label: "Web"}, {prefix: "/", text: "/ files", label: "Files"},
                                {prefix: ":", text: ": emoji", label: "Emoji"}, {prefix: ">", text: "> run", label: "Run"}]
                            .concat(root.noteShown ? [{prefix: "note ", text: "note …", label: "Add to the note"}] : [])
                        AbstractButton {
                            id: prefixButton
                            required property var modelData
                            required property int index
                            implicitWidth: prefixLabel.implicitWidth
                            implicitHeight: 24
                            hoverEnabled: true
                            focusPolicy: Qt.NoFocus
                            Accessible.name: modelData.label + ", type " + modelData.prefix
                            onClicked: {
                                search.text = modelData.prefix;
                                search.forceActiveFocus();
                            }
                            contentItem: Item {}
                            C.Label {
                                id: prefixLabel
                                anchors.verticalCenter: parent.verticalCenter
                                text: (prefixButton.index > 0 ? " · " : "") + prefixButton.modelData.text
                                color: prefixButton.hovered ? Theme.text : Theme.textDim
                                font.pixelSize: 12
                                elide: Text.ElideNone
                            }
                        }
                    }
                }
                C.Label {
                    visible: root.mode === "emoji" && !!root.current
                    text: root.current ? root.current.name : ""
                    color: Theme.textDim
                    font.pixelSize: 12
                    Layout.fillWidth: true
                }
                Item {
                    visible: !(root.mode === "emoji" && !!root.current)
                    Layout.fillWidth: true
                }
                C.Label {
                    visible: !root.calculatorQuery && (root.mode !== "web")
                    text: root.view.count + (root.view.count === 1 ? " result" : " results")
                    color: Theme.textDim
                    font.pixelSize: 12
                    font.features: ({"tnum": 1})
                    elide: Text.ElideNone
                }
            }
        }
    }
    Connections {
        target: Backend
        function onReadyChanged() {
            if (Backend.ready && root.calculatorQuery && !root.calculationValid) calcTimer.restart();
            if (Backend.ready && root.mode === "files") filesTimer.restart();
        }
    }
    Timer {
        id: calcTimer
        interval: 160
        onTriggered: {
            const query = root.query;
            const generation = root.calculationGeneration;
            const conversion = root.isConversion(query);
            const done = (result, error) => {
                if (generation !== root.calculationGeneration || query !== root.query) return;
                root.calculating = false;
                // Unknown units mean this was probably an app name, such as "7 days to die".
                if (conversion && error && /^Unknown unit/.test(error.message)) {
                    root.rejectedConversion = query;
                    root.rejectedReason = error.message;
                    return;
                }
                root.calculationValid = !error;
                root.calculation = error ? "" : result.text;
                root.calculatedExpression = error ? "" : query;
                root.calculationError = error ? error.message : "";
            };
            if (conversion)
                Backend.request("units.convert", {query: query}, done, {owner: root});
            else
                Backend.request("calculator", {expression: root.expression(query)}, done, {owner: root});
        }
    }
}
