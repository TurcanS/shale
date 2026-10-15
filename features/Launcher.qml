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

FocusScope {
    id: root
    readonly property string title: "Applications"
    // The search field heads the panel.
    readonly property bool showHeader: false
    readonly property int panelHeight: calculatorQuery && results.length === 0 ? (calculationError ? 262 : 202) : 520
    property alias query: search.text
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
    readonly property Item view: mode === "emoji" ? grid : list
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
            copying = false;
            if (error) { if (generation === calculationGeneration) calculationError = error.message; }
            else ShellState.message("Result copied", "success");
        });
    }
    // Folded once whenever the installed apps change, so typing only scores the term.
    readonly property var apps: DesktopEntries.applications.values.filter(e => !e.noDisplay).map(e => ({
        entry: e, text: Search.prepare({name: e.name, genericName: e.genericName, comment: e.comment, keywords: e.keywords,
                                        id: e.id, startupClass: e.startupClass, command: e.command})
    }))
    readonly property var appResults: {
        if (mode !== "apps" || calculatorQuery) return [];
        const pinned = ShellState.setting("pinnedApps", []);
        const usage = ShellState.setting("appUsage", {});
        const folded = Search.fold(term).trim();
        const ranked = apps.map(app => ({
            kind: "app", name: app.entry.name, subtitle: app.entry.genericName || app.entry.comment || app.entry.id,
            glyph: app.entry.icon, entry: app.entry, key: app.entry.id, rank: Search.scoreApp(app.text, folded)
        })).filter(i => i.rank > 0);
        // Open windows and built-in actions compete with apps on one scale. An open window edges out launching
        // its app again, even a frequently used one.
        const extras = folded ? windowResults(folded).concat(actionResults(folded)) : [];
        const sorted = ranked.concat(extras).sort((a, b) => {
            const boost = i => i.kind === "window" ? 400 : i.kind !== "app" ? 0 : (pinned.indexOf(i.key) >= 0 ? (term ? 100 : 100000) : 0) + Search.usageBoost(usage[i.key]);
            return b.rank + boost(b) - a.rank - boost(a) || a.name.localeCompare(b.name);
        });
        // Every app stays reachable from the empty query; a search only needs the best matches.
        return commandResults.concat(term ? sorted.slice(0, 100) : sorted);
    }
    // "timer 10m tea" and "focus 40" become one row each, above everything else.
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
        return [];
    }
    function windowResults(folded) {
        const results = [];
        for (const window of Services.windows) {
            const appId = window.wayland ? window.wayland.appId || "" : (window.lastIpcObject || {}).class || "";
            const rank = Search.scoreWindow(window.title, appId, folded);
            if (rank <= 0)
                continue;
            const entry = appId && DesktopEntries.heuristicLookup ? DesktopEntries.heuristicLookup(appId) : null;
            const workspace = window.workspace ? (window.workspace.id > 0 ? "workspace " + window.workspace.id : String(window.workspace.name || "").replace(/^special:/, "")) : "";
            results.push({kind: "window", key: "window:" + window.address, name: window.title || (entry ? entry.name : appId) || "Window",
                          subtitle: "Switch to " + (entry ? entry.name : appId || "window") + (workspace ? " · " + workspace : ""),
                          glyph: entry ? entry.icon : appId, fallback: "window", window: window, rank: rank});
        }
        return results.sort((a, b) => b.rank - a.rank).slice(0, 5);
    }
    function actionResults(folded) {
        return Search.ACTIONS.map(action => ({kind: "action", key: "action:" + action.key, action: action.key, name: action.name,
                                              subtitle: actionSubtitle(action.key), fallback: action.glyph, rank: Search.scoreAction(action, folded)}))
            .filter(item => item.rank > 0);
    }
    function actionSubtitle(key) {
        if (key.startsWith("power:"))
            return "Opens the session menu";
        if (key === "focus")
            return Focus.active ? "End focus · " + Focus.minutesText(Focus.remainingSeconds) + " left" : "Focus for " + Focus.lastMinutes + " minutes";
        if (key === "dnd")
            return ShellState.setting("dnd", false) ? "Turn off" : "Turn on";
        return key.startsWith("page:") ? "Control center" : "Shale";
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
        const results = term ? [{kind: "run", key: "run", name: term, subtitle: "Run · Shift+Enter to run in a terminal", fallback: "terminal", command: term}] : [];
        const folded = Search.fold(term);
        for (const command of history)
            if (command !== term && Search.fold(command).indexOf(folded) >= 0)
                results.push({kind: "run", key: "history:" + command, name: command, subtitle: "Recent command", fallback: "terminal", command: command});
        return results;
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
            fileResults = e ? [] : r.results.map(f => ({kind: "file", key: f.path, name: f.name, subtitle: f.folder, path: f.path, directory: f.directory, glyph: fileIcon(f), fallback: f.directory ? "grid" : "clipboard"}));
        });
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
            results.push({kind: "web", key: "url", name: "Open " + term, subtitle: "Website", fallback: "window", url: Search.addressUrl(term)});
        results.push({kind: "web", key: "search", name: term, subtitle: "Search " + engine.name, fallback: "search", url: engine.url + encodeURIComponent(term)});
        return results;
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
    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.gapM
        Item {
            Layout.fillWidth: true
            implicitHeight: 48
            C.Field {
                id: search
                anchors.fill: parent
                focus: true
                leftPadding: 42
                rightPadding: clear.visible ? 42 : 14
                placeholderText: "Apps, windows & calculations"
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
                    } else if (root.mode === "web" && event.key === Qt.Key_Tab) {
                        root.cycleEngine();
                        event.accepted = true;
                    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) && (root.mode === "files" || root.mode === "run")) {
                        root.activate(root.results[list.currentIndex], event.modifiers);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier) && root.mode === "apps" && !root.calculatorQuery && root.results[list.currentIndex]) {
                        root.pin(root.results[list.currentIndex]);
                        event.accepted = true;
                    }
                }
                onAccepted: {
                    if (root.calculatorQuery) root.copyCalculation();
                    else root.activate(root.results[root.view.currentIndex], Qt.NoModifier);
                }
            }
            C.Icon {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                size: 17
                color: Theme.muted
            }
            C.Button {
                id: clear
                visible: search.text !== ""
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: 32
                implicitHeight: 32
                glyph: "close"
                hint: "Clear search"
                flat: true
                onClicked: { search.clear(); search.forceActiveFocus(); }
            }
        }
        Rectangle {
            property real reveal: root.calculatorQuery ? 1 : 0
            Layout.fillWidth: true
            Layout.preferredHeight: 88 * reveal
            visible: reveal > 0
            opacity: reveal
            clip: true
            Behavior on reveal { NumberAnimation { duration: Theme.reduced ? 0 : Theme.enter; easing.type: Easing.OutCubic } }
            radius: Theme.controlRadius
            color: Theme.surface
            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: Theme.gapM
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.gapS
                    C.Label {
                        readonly property string noun: root.unitQuery ? "Conversion" : "Calculation"
                        text: root.calculationValid ? noun + " result" : root.calculating ? (root.unitQuery ? "Converting…" : "Calculating…") : noun
                        color: Theme.muted
                        font.pixelSize: Theme.small
                    }
                    C.Label {
                        text: root.calculationValid ? root.calculation : root.calculating ? "…" : root.unitQuery ? "Check the units" : "Check your expression"
                        color: root.calculationValid ? Theme.text : Theme.muted
                        font.family: root.calculationValid ? Theme.mono : Theme.font
                        font.pixelSize: root.calculationValid ? 26 : 16
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 16
                        Layout.fillWidth: true
                    }
                }
                C.Button {
                    text: root.copying ? "Copying…" : "Copy"
                    glyph: "copy"
                    enabled: root.calculationValid && !root.copying
                    onClicked: root.copyCalculation()
                }
            }
        }
        C.Label {
            visible: root.calculationError !== "" && !root.calculating
            text: root.calculationError
            color: Theme.danger
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
        // Search engine choice for "?" searches; Tab cycles it from the keyboard.
        RowLayout {
            visible: root.mode === "web"
            Layout.fillWidth: true
            spacing: Theme.gapS
            Repeater {
                model: root.engines
                C.Button {
                    required property var modelData
                    text: modelData.name
                    implicitHeight: 32
                    selected: root.engine.key === modelData.key
                    Accessible.role: Accessible.RadioButton
                    Accessible.checked: selected
                    onClicked: {
                        ShellState.setSetting("searchEngine", modelData.key);
                        search.forceActiveFocus();
                    }
                }
            }
            Item { Layout.fillWidth: true }
            C.Label {
                text: "Tab to switch"
                color: Theme.disabled
                font.pixelSize: Theme.caption
            }
        }
        Rectangle {
            visible: root.mode === "emoji" && !root.colorEmoji
            Layout.fillWidth: true
            implicitHeight: fontHint.implicitHeight + 16
            radius: Theme.radiusSmall + 2
            color: Theme.surface
            C.Label {
                id: fontHint
                anchors.fill: parent
                anchors.margins: 8
                anchors.leftMargin: 12
                text: "Emoji are shown without color. Install noto-fonts-emoji for full-color emoji."
                color: Theme.muted
                font.pixelSize: Theme.small
                wrapMode: Text.WordWrap
                verticalAlignment: Text.AlignVCenter
            }
        }
        RowLayout {
            visible: root.view.count > 0 && !root.calculatorQuery
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            C.Label {
                text: root.mode === "emoji" ? (root.term ? "Emoji" : "Recent & all emoji")
                    : root.mode === "files" ? "Files in your home folder"
                    : root.mode === "web" ? "Web"
                    : root.mode === "run" ? "Run a command"
                    : root.query.trim() ? "Search results" : ShellState.setting("pinnedApps", []).length ? "Pinned & frequently used" : "All apps"
                color: Theme.muted
                font.pixelSize: Theme.small
                Layout.fillWidth: true
            }
            C.Label {
                visible: root.mode !== "web"
                text: root.view.count
                color: Theme.disabled
                font.pixelSize: Theme.caption
                font.family: Theme.mono
            }
        }
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: !root.calculatorQuery && root.mode !== "emoji"
            visible: !root.calculatorQuery && root.mode !== "emoji"
            clip: true
            model: root.mode !== "emoji" ? root.results : []
            spacing: Theme.gapXs
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: Theme.fast
            ScrollBar.vertical: C.ScrollBar {}
            delegate: C.Button {
                id: row
                required property var modelData
                required property int index
                readonly property bool pinned: modelData.kind === "app" && ShellState.setting("pinnedApps", []).indexOf(modelData.key) >= 0
                width: list.width
                height: Math.max(56, Theme.body + 42)
                activeFocusOnTab: ListView.isCurrentItem
                Accessible.name: modelData.kind === "web" ? modelData.subtitle + ": " + modelData.name : modelData.name
                padding: 12
                onClicked: root.activate(modelData, Qt.NoModifier)
                HoverHandler {
                    onPointChanged: if (hovered && root.pointerMoved(point.scenePosition)) root.select(row.index)
                }
                Keys.onReturnPressed: event => root.activate(modelData, event.modifiers)
                background: Rectangle {
                    radius: Theme.controlRadius
                    color: row.down ? Theme.selectionHover : row.ListView.isCurrentItem || row.visualFocus ? Theme.selection : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                }
                contentItem: RowLayout {
                    spacing: Theme.gapM
                    Image {
                        id: appIcon
                        source: {
                            const icon = row.modelData.glyph || "";
                            if (icon.startsWith("/")) return "file://" + icon;
                            if (icon.startsWith("file:")) return icon;
                            return icon && Quickshell.hasThemeIcon(icon) ? Quickshell.iconPath(icon) : "";
                        }
                        visible: status === Image.Ready
                        sourceSize.width: 30
                        sourceSize.height: 30
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                    }
                    Rectangle {
                        visible: appIcon.status !== Image.Ready
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        radius: Theme.radiusSmall
                        color: row.modelData.kind === "app" ? "transparent" : Theme.raised
                        C.Icon {
                            anchors.centerIn: parent
                            name: row.modelData.fallback || "grid"
                            size: row.modelData.kind === "app" ? 30 : 16
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.gapXs
                        C.Label { text: row.modelData.name; elide: Text.ElideMiddle; Layout.fillWidth: true }
                        C.Label {
                            visible: row.modelData.subtitle !== row.modelData.name && row.modelData.subtitle !== ""
                            text: row.modelData.subtitle
                            color: Theme.muted
                            font.pixelSize: Theme.small
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                    }
                    C.Button {
                        visible: row.modelData.kind === "app"
                        glyph: "pin"
                        flat: true
                        selected: row.pinned
                        // Shown for the pinned, hovered, or selected row only; the rest stay quiet.
                        opacity: row.pinned || row.hovered || row.ListView.isCurrentItem || row.visualFocus || visualFocus ? 1 : 0
                        activeFocusOnTab: row.ListView.isCurrentItem
                        hint: (row.pinned ? "Unpin " : "Pin ") + row.modelData.name
                        implicitWidth: 32
                        implicitHeight: 32
                        onClicked: root.pin(row.modelData)
                        Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                    }
                }
            }
            C.EmptyState {
                anchors.centerIn: parent
                width: parent.width - 40
                visible: list.count === 0 && !root.calculatorQuery && root.mode !== "emoji"
                glyph: "search"
                title: root.mode === "files" ? (!root.term ? "Search your files" : root.filesBusy ? "Searching…" : root.filesError ? "Search failed" : "No matching files")
                    : root.mode === "web" ? "Search the web"
                    : root.mode === "run" ? "Run a command"
                    : root.query.trim() ? "No matching apps" : "No apps available"
                description: root.mode === "files" ? (root.filesError || (!root.term ? "Type part of a file or folder name." : root.filesBusy ? "" : "Hidden and ignored files are skipped."))
                    : root.mode === "web" ? "Type what you are looking for after the question mark."
                    : root.mode === "run" ? "Type a command after the >. Shift+Enter runs it in a terminal."
                    : root.rejectedConversion === root.query ? root.rejectedReason + " No app matches either."
                    : root.query.trim() ? "Try another app name." : "Installed applications will appear here."
            }
        }
        GridView {
            id: grid
            readonly property int columns: 8
            Layout.fillWidth: true
            Layout.fillHeight: root.mode === "emoji"
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
                    radius: Theme.radiusSmall + 2
                    color: cell.down ? Theme.selectionHover : cell.GridView.isCurrentItem ? Theme.selection : "transparent"
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
        // What Enter does here, or how to reach the other modes from an empty query.
        RowLayout {
            visible: !root.calculatorQuery
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            spacing: Theme.gapS
            C.Label {
                visible: root.mode === "apps" && root.query === ""
                text: "Type a prefix to search"
                color: Theme.disabled
                font.pixelSize: Theme.caption
                Layout.fillWidth: true
            }
            C.Label {
                visible: root.mode !== "apps" || root.query !== ""
                text: root.mode === "emoji" ? (root.results[grid.currentIndex] ? root.results[grid.currentIndex].name + " · Enter to copy" : "")
                    : root.mode === "files" ? "Enter to open · Ctrl+Enter for its folder · Shift+Enter to copy the path"
                    : root.mode === "web" ? "Enter to open in your browser"
                    : root.mode === "run" ? "Enter to run · Shift+Enter in a terminal"
                    : !root.results[list.currentIndex] || root.results[list.currentIndex].kind === "app" ? "Ctrl+P to pin"
                    : root.results[list.currentIndex].kind === "window" ? "Enter to switch to it"
                    : "Enter to start"
                color: Theme.disabled
                font.pixelSize: Theme.caption
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Repeater {
                model: root.mode === "apps" && root.query === "" ? [{prefix: ":", label: "Emoji"}, {prefix: "/", label: "Files"}, {prefix: "?", label: "Web"}, {prefix: ">", label: "Run"}, {prefix: "=", label: "Calculate"}] : []
                AbstractButton {
                    id: modeButton
                    required property var modelData
                    implicitWidth: chipRow.implicitWidth + 16
                    implicitHeight: 26
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    Accessible.name: modelData.label + ", type " + modelData.prefix
                    onClicked: {
                        search.text = modelData.prefix;
                        search.forceActiveFocus();
                    }
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: modeButton.hovered ? Theme.hover : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.fast } }
                    }
                    contentItem: Item {}
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: Theme.gapXs
                        Text {
                            text: modeButton.modelData.prefix
                            color: Theme.accentText
                            font.family: Theme.mono
                            font.pixelSize: Theme.caption
                        }
                        Text {
                            text: modeButton.modelData.label
                            color: modeButton.hovered ? Theme.text : Theme.muted
                            font.family: Theme.font
                            font.pixelSize: Theme.caption
                        }
                    }
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
                Backend.request("units.convert", {query: query}, done);
            else
                Backend.request("calculator", {expression: root.expression(query)}, done);
        }
    }
}
