import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../core"
import "../components" as C

// Where your time goes: Overview (headline numbers, the year, the hours you're active, top apps), Day (a timeline you
// can click, its breakdown, its hours and apps) and Apps (ranked by time, each with its own page). Nothing is
// recorded or shown until tracking is turned on here; Pause and Clear history stay within reach.
FocusScope {
    id: root
    readonly property string title: "Activity"
    readonly property bool showHeader: false
    readonly property int panelWidth: 960
    readonly property int panelHeight: 660
    property string mode: "overview"
    property string selectedDate: today()
    property var overview: ({days: [], started: null, paused: false, state: null, insights: ({}), topApps: [], firstDay: null})
    property var day: ({segments: [], windows: [], hours: [], apps: [], active: 0, watching: 0, unlocked: 0, detailAvailable: true, firstActive: null, lastActive: null})
    property string appsRange: "week"
    property var appsData: ({apps: [], total: 0, previousTotal: 0, days: [], start: "", end: ""})
    property string appDetail: ""
    property var appData: ({days: [], hours: [], total: 0, daysUsed: 0, firstDay: null, averagePerDay: 0})
    property int heatPage: 0
    // Weeks the year grid fits: 9 px squares, 2 px apart, at most 53.
    property int graphWeeks: 53
    property string hoverDate: ""
    property bool busy: false
    property string error: ""
    // The load the error came from: only that load working again clears it, so the other loads sent with it can't
    // hide it. "" (Pause, Clear history) is cleared by any load that works.
    property string errorFrom: ""
    property string caption: ""
    property double nowMs: Date.now()
    property real contentProgress: 1
    // "ask" until chosen here; nothing is recorded or shown unless it's "on".
    readonly property string tracking: ShellState.setting("activityTracking", "ask")
    readonly property date selected: new Date(selectedDate + "T12:00:00")
    // Weeks start on the locale's first day, as in the Calendar.
    readonly property int weekStart: ShellState.firstDayOfWeek
    readonly property var insights: overview.insights || ({})
    readonly property string phase: overview.paused ? "paused" : overview.state || "away"
    readonly property var dayMap: {
        const result = {};
        for (const entry of overview.days || []) result[entry.date] = entry;
        return result;
    }
    // Apps keep one shade across the day: ranked by time, the busiest lightest.
    readonly property var dayRanking: (day.apps || []).map(entry => entry.app)
    readonly property var heatmapDays: {
        const now = new Date();
        now.setHours(12, 0, 0, 0);
        const end = new Date(now);
        end.setDate(end.getDate() - heatPage * graphWeeks * 7);
        const start = new Date(end);
        start.setDate(start.getDate() - ((start.getDay() - weekStart + 7) % 7) - (graphWeeks - 1) * 7);
        const cells = [];
        for (let i = 0; i < graphWeeks * 7; i++) {
            const date = new Date(start);
            date.setDate(start.getDate() + i);
            const key = Qt.formatDate(date, "yyyy-MM-dd");
            const entry = dayMap[key] || {};
            cells.push({date: key, future: date > now, before: !!overview.firstDay && key < overview.firstDay, active: entry.active || 0, watching: entry.watching || 0});
        }
        return cells;
    }
    // Month names under the year, at the week each month starts; every other one, as there is room for.
    readonly property var heatMonths: {
        const labels = [];
        let previous = -1;
        for (let week = 0; week < graphWeeks; week++) {
            const cell = heatmapDays[week * 7];
            if (!cell) break;
            const date = new Date(cell.date + "T12:00:00");
            if (date.getMonth() !== previous) {
                if (previous >= 0 && week < graphWeeks - 2)
                    labels.push({week: week, text: Qt.locale().monthName(date.getMonth(), Locale.ShortFormat)});
                previous = date.getMonth();
            }
        }
        return labels.filter((label, index) => index % 2 === 0);
    }
    readonly property bool heatHasEarlier: !!overview.firstDay && heatmapDays.length > 0 && overview.firstDay < heatmapDays[0].date
    readonly property var dayAppRows: {
        const windows = {};
        for (const window of day.windows || []) (windows[window.app] = windows[window.app] || []).push(window);
        const focus = {};
        for (const segment of day.segments || []) if (segment.app && segment.state !== "idle") (focus[segment.app] = focus[segment.app] || []).push(segment);
        const rows = (day.apps || []).map(entry => ({app: entry.app, total: entry.total, active: entry.active, watching: entry.watching, windows: windows[entry.app] || [], focus: focus[entry.app] || []}));
        for (const app in windows) if (!focus[app]) rows.push({app: app, total: 0, active: 0, watching: 0, windows: windows[app], focus: []});
        return rows;
    }
    // The stretches drawn on the day's timeline: time in an app, active or watching.
    readonly property var daySpans: (day.segments || []).filter(segment => segment.app && segment.state !== "idle")
    readonly property double dayStart: new Date(selected.getFullYear(), selected.getMonth(), selected.getDate()).getTime()
    readonly property int dayLength: new Date(selected.getFullYear(), selected.getMonth(), selected.getDate() + 1).getTime() - dayStart
    readonly property bool showingToday: selectedDate === today()

    function today() { return Qt.formatDate(new Date(), "yyyy-MM-dd"); }
    // 5 h 12, 34 h, 38 min.
    function formatTime(seconds) {
        const minutes = Math.round(Math.max(0, seconds || 0) / 60);
        if (minutes < 60) return minutes + " min";
        return Math.floor(minutes / 60) + " h" + (minutes % 60 ? " " + String(minutes % 60).padStart(2, "0") : "");
    }
    // "+38 min vs usual", "−2 h vs last week" or "same as usual"; "" when there is nothing to compare with.
    function compare(now, before, against) {
        if (before === null || before === undefined) return "";
        const change = (now || 0) - before;
        if (Math.abs(change) < 60) return "same as " + against;
        return (change > 0 ? "+" : "−") + formatTime(Math.abs(change)) + " vs " + against;
    }
    function clockTime(milliseconds) { return Qt.formatTime(new Date(milliseconds), ShellState.timeFormat); }
    function minuteClock(minutes) {
        if (minutes === null || minutes === undefined) return "–";
        const value = Math.round(minutes) % 1440;
        return Qt.formatTime(new Date(2000, 0, 1, Math.floor(value / 60), value % 60), ShellState.timeFormat);
    }
    // The year's single-hue ramp, from an empty square to the accent.
    readonly property color heatEmpty: Theme.mix(Theme.module, Theme.key, 0.5)
    readonly property var heatSteps: [0, 0.25, 0.45, 0.7, 1]
    function heatLevel(seconds) { return seconds >= 14400 ? 4 : seconds >= 7200 ? 3 : seconds >= 2400 ? 2 : seconds >= 60 ? 1 : 0; }
    function heatColor(seconds) {
        const level = heatLevel(seconds);
        return level === 0 ? heatEmpty : Theme.mix(heatEmpty, Theme.accent, heatSteps[level]);
    }
    // Letter tiles: the first app in the accent, the rest in greys that step down with rank.
    function tileColor(rank) { return rank === 0 ? Theme.accent : Theme.mix(Theme.textSecondary, Theme.key, Math.min(0.8, 0.15 + rank * 0.11)); }
    function inkOn(color) { return Theme.contrast(color, Theme.accentInk) >= 4.5 ? Theme.accentInk : Theme.text; }
    function appShade(app) {
        const index = dayRanking.indexOf(app);
        return Theme.mix(Theme.textSecondary, Theme.key, Math.min(0.75, 0.1 + Math.max(0, index) * 0.12));
    }
    function appEntry(app) {
        const key = app.toLowerCase().replace(/\.desktop$/, "");
        return DesktopEntries.applications.values.find(entry => {
            const id = (entry.id || "").toLowerCase().replace(/\.desktop$/, "");
            return id === key || id.split(".").pop() === key || (entry.name || "").toLowerCase() === key;
        }) || null;
    }
    function appLabel(app) {
        if (!app) return "No window";
        const entry = appEntry(app);
        if (entry) return entry.name;
        return app.split(".").pop().replace(/[-_]/g, " ").replace(/\b\w/g, letter => letter.toUpperCase());
    }
    // Days an arrow key moves in a calendar grid: `across` for Left and Right, `down` for Up and Down.
    function arrowDays(key, across, down) {
        return key === Qt.Key_Left ? -across : key === Qt.Key_Right ? across : key === Qt.Key_Up ? -down : key === Qt.Key_Down ? down : 0;
    }
    function stepDay(days, earliest) {
        const date = new Date(selected);
        date.setDate(date.getDate() + days);
        const key = Qt.formatDate(date, "yyyy-MM-dd");
        if (key <= today() && !(earliest && key < earliest))
            setDate(key);
    }
    // Pages the year to the selected day.
    function revealHeat() {
        while (heatHasEarlier && selectedDate < heatmapDays[0].date)
            heatPage++;
        while (heatPage > 0 && selectedDate > heatmapDays[heatmapDays.length - 1].date)
            heatPage--;
    }
    function timeX(milliseconds, width) { return Math.max(0, Math.min(width, (milliseconds - dayStart) / dayLength * width)); }
    function dayTitle() {
        if (showingToday) return "Today";
        const yesterday = new Date();
        yesterday.setDate(yesterday.getDate() - 1);
        return selectedDate === Qt.formatDate(yesterday, "yyyy-MM-dd") ? "Yesterday" : Qt.formatDate(selected, "dddd");
    }
    function periodLabel() {
        if (!appsData.start) return "";
        const first = new Date(appsData.start + "T12:00:00"), last = new Date(appsData.end + "T12:00:00");
        if (appsRange === "day") return Qt.formatDate(first, "ddd d MMM yyyy");
        if (appsRange === "month") return Qt.formatDate(first, "MMMM yyyy");
        return Qt.formatDate(first, "d MMM") + " – " + Qt.formatDate(last, "d MMM yyyy");
    }
    // "in apps this week · 2 h less than last week"
    function appsSummary() {
        const words = ({day: "this day", week: "this week", month: "this month"})[appsRange];
        const change = (appsData.total || 0) - (appsData.previousTotal || 0);
        const before = ({day: "the day before", week: "last week", month: "last month"})[appsRange];
        if (!appsData.previousTotal || appsData.previousTotal < 60) return "in apps " + words;
        if (Math.abs(change) < 60) return "in apps " + words + " · same as " + before;
        return "in apps " + words + " · " + formatTime(Math.abs(change)) + (change > 0 ? " more than " : " less than ") + before;
    }

    function setDate(date) {
        if (date > today()) date = today();
        selectedDate = date;
        caption = "";
        loadDay();
        if (mode === "apps") loadApps();
    }
    function shiftDate(days) {
        const date = new Date(selected);
        date.setDate(date.getDate() + days);
        setDate(Qt.formatDate(date, "yyyy-MM-dd"));
    }
    function shiftMonth(months) {
        setDate(Qt.formatDate(new Date(selected.getFullYear(), selected.getMonth() + months, Math.min(selected.getDate(), 28), 12), "yyyy-MM-dd"));
    }
    function shiftPeriod(step) {
        if (appsRange === "day") shiftDate(step);
        else if (appsRange === "week") shiftDate(step * 7);
        else shiftMonth(step);
    }
    function openDay(date) {
        setDate(date);
        mode = "day";
    }
    function openApp(app) {
        appDetail = app;
        mode = "apps";
        loadApp();
    }
    function request(method, params, done) {
        if (!Backend.ready) return;
        Backend.request(method, params, (result, failure) => {
            if (failure) { error = failure.message; errorFrom = method; }
            else { if (errorFrom === "" || errorFrom === method) error = ""; done(result); }
        }, {owner: root});
    }
    function loadOverview() { request("activity.overview", {weekStart: weekStart}, result => overview = result); }
    function loadDay() {
        const date = selectedDate;
        request("activity.day", {date: date}, result => { if (date === selectedDate) day = result; });
    }
    function loadApps() {
        const date = selectedDate, range = appsRange;
        request("activity.apps", {range: range, date: date, weekStart: weekStart}, result => { if (date === selectedDate && range === appsRange) appsData = result; });
    }
    function loadApp() {
        const app = appDetail;
        if (app) request("activity.app", {app: app, date: today()}, result => { if (app === appDetail) appData = result; });
    }
    function refresh() {
        nowMs = Date.now();
        if (tracking !== "on") return;
        loadOverview();
        loadDay();
        if (mode === "apps") { loadApps(); loadApp(); }
    }
    onModeChanged: {
        contentProgress = 0;
        modeEntrance.restart();
        caption = "";
        if (mode !== "apps") appDetail = "";
        if (mode === "apps") loadApps();
    }
    onAppsRangeChanged: loadApps()
    onTrackingChanged: refresh()
    NumberAnimation { id: modeEntrance; target: root; property: "contentProgress"; to: 1; duration: Theme.enter; easing.type: Easing.OutCubic }
    function pause() {
        if (busy) return;
        busy = true;
        Backend.request("activity.pause", {paused: !overview.paused}, (result, failure) => {
            // Recording again starts from what is on screen now, whether or not the panel is still open.
            if (!failure && !result.paused) ShellState.activitySnapshotRequested();
            if (!root) return;
            busy = false;
            if (failure) { error = failure.message; errorFrom = ""; }
            else {
                overview = Object.assign({}, overview, result);
                refresh();
            }
        });
    }
    function clear() {
        if (busy) return;
        busy = true;
        Backend.request("activity.clear", {}, (result, failure) => {
            if (!failure) ShellState.activitySnapshotRequested();
            if (!root) return;
            busy = false;
            clearHistoryButton.triggered = false;
            if (failure) { error = failure.message; errorFrom = ""; }
            else refresh();
        });
    }
    Component.onCompleted: refresh()
    Connections {
        target: Backend
        function onReadyChanged() { if (Backend.ready) root.refresh(); }
    }
    Timer { interval: 30000; running: root.tracking === "on"; repeat: true; onTriggered: root.refresh() }

    // Reusable pieces ----------------------------------------------------------
    // A rank-coloured square with the app's first letter.
    component AppTile: Rectangle {
        id: tile
        property string app: ""
        property int rank: 0
        property int size: 28
        implicitWidth: size
        implicitHeight: size
        Layout.preferredWidth: size
        Layout.preferredHeight: size
        radius: size > 24 ? 8 : 6
        color: root.tileColor(rank)
        C.Label {
            anchors.centerIn: parent
            text: root.appLabel(tile.app).charAt(0).toUpperCase()
            font.pixelSize: tile.size > 24 ? 12 : 10
            font.weight: Font.Bold
            color: root.inkOn(tile.color)
        }
    }
    // A module title, 14/600, with an optional quiet note beside it.
    component ModuleTitle: RowLayout {
        property string text: ""
        property string note: ""
        spacing: 8
        C.Label { text: parent.text; font.pixelSize: 14; font.weight: Font.DemiBold; elide: Text.ElideNone }
        C.Label { visible: text !== ""; text: parent.note; font.pixelSize: 12; color: Theme.textDim; Layout.fillWidth: true }
    }
    // Columns from the bottom: `a` in `color` (the accent at `highlight`), `b` stacked on top in the second colour.
    component Bars: Item {
        id: chart
        property var values: []
        property real maximum: 1
        property color color: Theme.accent
        property int highlight: -1
        property int selectedIndex: -1
        property var names: []
        signal picked(int index)
        RowLayout {
            anchors.fill: parent
            spacing: chart.values.length > 26 ? 2 : 3
            Repeater {
                model: chart.values
                Item {
                    id: column
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    opacity: chart.selectedIndex < 0 || chart.selectedIndex === index ? 1 : 0.55
                    // Opening Activity, the chart is plotted from left to right behind the pen, each bar overshooting
                    // a little as it lands.
                    readonly property real plotted: Math.max(0, plotIn.progress)
                    transform: C.Cascade {
                        id: plotIn
                        panel: "activity"
                        order: column.index
                        dy: 0
                        limit: 60
                        spacing: 0.7
                        overshoot: 1.2
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: chart.names[index] || ""
                    Rectangle {
                        id: lower
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Math.max(2, Math.min(1, (column.modelData.a || 0) / chart.maximum) * parent.height * column.plotted)
                        radius: 3
                        color: column.index === chart.highlight ? Theme.accent : chart.color
                        Behavior on height {
                            enabled: column.plotted === 1
                            NumberAnimation { duration: Theme.enter; easing.type: Easing.OutCubic }
                        }
                    }
                    Rectangle {
                        anchors.bottom: lower.top
                        anchors.bottomMargin: height > 0 ? 1 : 0
                        width: parent.width
                        height: Math.min(1, (column.modelData.b || 0) / chart.maximum) * parent.height * column.plotted
                        radius: 3
                        color: Theme.second
                        Behavior on height {
                            enabled: column.plotted === 1
                            NumberAnimation { duration: Theme.enter; easing.type: Easing.OutCubic }
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: chart.picked(column.index) }
                }
            }
        }
    }
    component HourAxis: RowLayout {
        property bool clock: false
        spacing: 0
        Repeater {
            model: ["00", "06", "12", "18", "24"]
            C.Label {
                required property string modelData
                required property int index
                text: modelData + (parent.clock ? ":00" : "")
                font.pixelSize: 11
                color: Theme.textDim
                // Halves at the ends, so the middle labels centre on 06, 12 and 18.
                Layout.fillWidth: true
                Layout.preferredWidth: index > 0 && index < 4 ? 2 : 1
                horizontalAlignment: index === 0 ? Text.AlignLeft : index === 4 ? Text.AlignRight : Text.AlignHCenter
            }
        }
    }
    // Active in the accent, watching in the second colour, on an empty track.
    component AppBar: Item {
        id: bar
        property real active: 0
        property real watching: 0
        property real maximum: 1
        property color color: Theme.accent
        implicitHeight: 6
        Rectangle { anchors.fill: parent; radius: height / 2; color: Theme.key }
        Item {
            width: Math.min(bar.width, activePart.width + watchingPart.width)
            height: parent.height
            clip: true
            Rectangle {
                id: activePart
                width: bar.width * Math.min(1, bar.active / Math.max(1, bar.maximum))
                height: parent.height
                radius: height / 2
                color: bar.color
                Behavior on width { NumberAnimation { duration: Theme.enter; easing.type: Easing.OutCubic } }
            }
            Rectangle {
                id: watchingPart
                x: activePart.width
                width: bar.width * Math.min(1, bar.watching / Math.max(1, bar.maximum))
                height: parent.height
                color: Theme.second
                Behavior on width { NumberAnimation { duration: Theme.enter; easing.type: Easing.OutCubic } }
            }
        }
    }
    component Swatch: Rectangle {
        Layout.preferredWidth: 10
        Layout.preferredHeight: 4
        radius: 2
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // Title, the three views, whether it's recording, Pause and close.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            spacing: 12
            C.Label { text: "Activity"; font.pixelSize: 17; font.weight: 650; elide: Text.ElideNone; Layout.leftMargin: 2 }
            C.Segmented {
                visible: root.tracking === "on"
                fill: false
                segmentHeight: 32
                model: [{key: "overview", text: "Overview", accessibleName: "Overview · 1"}, {key: "day", text: "Day", accessibleName: "Day · 2"}, {key: "apps", text: "Apps", accessibleName: "Apps · 3"}]
                current: root.mode
                onActivated: key => root.mode = key
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                id: phaseChip
                visible: root.tracking === "on"
                readonly property bool live: root.phase === "active" || root.phase === "watching"
                readonly property color ink: root.phase === "active" ? Theme.accent : root.phase === "watching" ? Theme.second : Theme.textMuted
                implicitWidth: phaseRow.implicitWidth + 20
                implicitHeight: 28
                radius: 14
                color: live ? Theme.tint(ink, 0.14) : Theme.key
                Behavior on color { ColorAnimation { duration: Theme.fast } }
                RowLayout {
                    id: phaseRow
                    anchors.centerIn: parent
                    spacing: 6
                    Rectangle { Layout.preferredWidth: 6; Layout.preferredHeight: 6; radius: 3; color: phaseChip.ink }
                    C.Label {
                        text: ({paused: "Paused", active: "Active now", watching: "Watching", idle: "Idle", away: "Tracking"})[root.phase]
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: phaseChip.ink
                        elide: Text.ElideNone
                    }
                }
            }
            C.Button {
                visible: root.tracking === "on"
                text: root.overview.paused ? "Resume" : "Pause"
                glyph: root.overview.paused ? "play" : "pause"
                implicitHeight: 32
                labelSize: 13
                enabled: !root.busy && Backend.ready
                Accessible.checkable: true
                Accessible.checked: root.overview.paused
                onClicked: root.pause()
            }
            C.Button {
                glyph: "close"
                implicitWidth: 32
                implicitHeight: 32
                flat: true
                hint: "Close · Escape"
                onClicked: ShellState.close()
            }
        }
        C.Label { visible: root.error !== ""; text: root.error; color: Theme.dangerText; font.pixelSize: 13; Layout.fillWidth: true; wrapMode: Text.WordWrap }

        // First run asks; once turned off, the panel says so and offers to turn it back on.
        Item {
            visible: root.tracking !== "on"
            Layout.fillWidth: true
            Layout.fillHeight: true
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width, 440)
                spacing: Theme.gapL
                C.EmptyState {
                    Layout.fillWidth: true
                    glyph: "activity"
                    title: root.tracking === "off" ? "Activity tracking is off" : "See where your time goes"
                    description: root.tracking === "off" ? "Nothing is being recorded. Turn it on to see your active time, your daily rhythm and the apps you use."
                        : "Shale can keep a private record of your time at this computer, so you can look back on your days and the apps you spend them in."
                }
                C.Card {
                    visible: root.tracking !== "off"
                    Layout.fillWidth: true
                    implicitHeight: facts.implicitHeight + 28
                    ColumnLayout {
                        id: facts
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 14
                        spacing: Theme.gapM
                        Repeater {
                            model: [
                                {glyph: "activity", text: "Records how long you use each app, and when you're active, watching or idle"},
                                {glyph: "lock", text: "Stays on this computer and is never sent anywhere"},
                                {glyph: "eye-off", text: "Never records window titles or what's on screen"},
                                {glyph: "pause", text: "Pause it, turn it off or clear it whenever you like"}
                            ]
                            RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Theme.gapM
                                C.Icon { name: parent.modelData.glyph; size: 16; color: Theme.textMuted; Layout.alignment: Qt.AlignTop }
                                C.Label { text: parent.modelData.text; font.pixelSize: 13; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Theme.gapS
                    C.Button {
                        visible: root.tracking !== "off"
                        text: "Not now"
                        flat: true
                        onClicked: ShellState.setSetting("activityTracking", "off")
                    }
                    C.Button {
                        text: "Turn on"
                        accent: true
                        onClicked: ShellState.setSetting("activityTracking", "on")
                    }
                }
            }
        }

        Item {
            visible: root.tracking === "on"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            opacity: root.contentProgress
            transform: Translate { y: Theme.reduced ? 0 : (1 - root.contentProgress) * 6 }

            // Overview ---------------------------------------------------------
            Loader {
                anchors.fill: parent
                active: root.mode === "overview"
                sourceComponent: ColumnLayout {
                    anchors.fill: parent
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Repeater {
                            model: {
                                const i = root.insights;
                                const usual = root.compare(i.today, i.average7, "usual");
                                const week = root.compare(i.thisWeek, i.lastWeek, "last week");
                                const streak = i.streak || 0;
                                return [
                                    {label: "Today", value: root.formatTime(i.today), note: usual || "active so far", up: usual.startsWith("+")},
                                    {label: "This week", value: root.formatTime(i.thisWeek), note: week || "since " + Qt.locale().dayName(root.weekStart, Locale.LongFormat)},
                                    {label: "Daily average", value: i.average30 === null || i.average30 === undefined ? "–" : root.formatTime(i.average30), note: "last 30 days"},
                                    {label: "Streak", value: streak + (streak === 1 ? " day" : " days"), note: "best " + (i.longestStreak || 0) + " · 15 min or more a day"}
                                ];
                            }
                            C.Stat {
                                required property var modelData
                                color: Theme.module
                                radius: Theme.radiusModule
                                inset: 13
                                valueSize: 24
                                noteSize: 12
                                noteColor: modelData.up ? Theme.accent : Theme.textDim
                                label: modelData.label
                                value: modelData.value
                                note: modelData.note
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 10
                            // The year: a square a day, deeper for more active time.
                            C.Card {
                                Layout.fillWidth: true
                                Layout.preferredHeight: yearColumn.implicitHeight + 24
                                border.width: heatmap.activeFocus ? 1 : 0
                                border.color: Theme.accentLine
                                ColumnLayout {
                                    id: yearColumn
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    anchors.topMargin: 12
                                    spacing: 8
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        ModuleTitle { text: "Your year"; note: "each square is a day"; Layout.fillWidth: true }
                                        C.Label {
                                            readonly property string date: root.hoverDate || (heatmap.activeFocus ? root.selectedDate : "")
                                            readonly property var entry: root.dayMap[date] || ({})
                                            text: date === "" ? "hover a day" : Qt.formatDate(new Date(date + "T12:00:00"), "ddd d MMM") + " · " + root.formatTime(entry.active)
                                                + (entry.watching >= 60 ? " · " + root.formatTime(entry.watching) + " watching" : "")
                                            font.pixelSize: 12
                                            color: Theme.textDim
                                            elide: Text.ElideNone
                                        }
                                        C.Button { visible: root.heatHasEarlier || root.heatPage > 0; glyph: "back"; flat: true; implicitWidth: 24; implicitHeight: 22; padding: 4; enabled: root.heatHasEarlier; hint: "Earlier"; onClicked: root.heatPage++ }
                                        C.Button { visible: root.heatHasEarlier || root.heatPage > 0; glyph: "chevron"; flat: true; implicitWidth: 24; implicitHeight: 22; padding: 4; enabled: root.heatPage > 0; hint: "Later"; onClicked: root.heatPage-- }
                                    }
                                    Item {
                                        id: heatArea
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 7 * 11 - 2
                                        onWidthChanged: if (width > 0) root.graphWeeks = Math.max(13, Math.min(53, Math.floor((width + 2) / 11)))
                                        Grid {
                                            id: heatmap
                                            rows: 7
                                            flow: Grid.TopToBottom
                                            spacing: 2
                                            // One tab stop: columns are weeks, so Left and Right move a week, Up and Down a day.
                                            activeFocusOnTab: true
                                            Accessible.role: Accessible.Table
                                            Accessible.name: "Daily activity, " + Qt.formatDate(root.selected, "d MMMM yyyy") + " selected"
                                            onActiveFocusChanged: if (activeFocus) root.revealHeat()
                                            Keys.onPressed: event => {
                                                const days = root.arrowDays(event.key, 7, 1);
                                                if (days) {
                                                    root.stepDay(days, root.overview.firstDay);
                                                    root.revealHeat();
                                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                                                    root.mode = "day";
                                                } else if (event.key === Qt.Key_Home) {
                                                    root.setDate(root.today());
                                                    root.heatPage = 0;
                                                } else {
                                                    return;
                                                }
                                                event.accepted = true;
                                            }
                                            Repeater {
                                                model: root.heatmapDays
                                                Rectangle {
                                                    required property var modelData
                                                    readonly property bool empty: modelData.future || modelData.before
                                                    width: 9
                                                    height: 9
                                                    radius: 2
                                                    // Days before tracking began stay as faint squares, so a short history still draws the
                                                    // whole year instead of a small block in an empty module.
                                                    color: modelData.future ? "transparent" : modelData.before ? Theme.tint(Theme.text, 0.035) : root.heatColor(modelData.active)
                                                    border.width: modelData.date === root.selectedDate && !empty ? 1 : 0
                                                    border.color: Theme.text
                                                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        anchors.margins: -1
                                                        enabled: !parent.empty
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onContainsMouseChanged: {
                                                            if (containsMouse)
                                                                root.hoverDate = parent.modelData.date;
                                                            else if (root.hoverDate === parent.modelData.date)
                                                                root.hoverDate = "";
                                                        }
                                                        onClicked: root.openDay(parent.modelData.date)
                                                    }
                                                    Accessible.role: Accessible.Button
                                                    Accessible.name: modelData.date + (modelData.before ? ", before tracking began" : ", " + root.formatTime(modelData.active))
                                                }
                                            }
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 4
                                        Item {
                                            id: monthRow
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 14
                                            Repeater {
                                                model: root.heatMonths
                                                C.Label {
                                                    required property var modelData
                                                    // Months that would run under the legend are left out.
                                                    visible: x + implicitWidth <= monthRow.width
                                                    x: modelData.week * 11
                                                    text: modelData.text
                                                    font.pixelSize: 11
                                                    color: Theme.textDim
                                                    elide: Text.ElideNone
                                                }
                                            }
                                        }
                                        C.Label { text: "Less"; font.pixelSize: 11; color: Theme.textDim }
                                        Repeater {
                                            model: root.heatSteps
                                            Rectangle { required property real modelData; width: 9; height: 9; radius: 2; color: Theme.mix(root.heatEmpty, Theme.accent, modelData) }
                                        }
                                        C.Label { text: "More"; font.pixelSize: 11; color: Theme.textDim }
                                    }
                                }
                            }
                            // Active time by hour over the last 30 days, the busiest hour in the accent, and the rhythm.
                            C.Card {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    anchors.topMargin: 12
                                    anchors.bottomMargin: 12
                                    spacing: 14
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        spacing: 8
                                        ModuleTitle { text: "When you're active"; note: "last 30 days"; Layout.fillWidth: true }
                                        Bars {
                                            readonly property var hours: root.insights.hours || []
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            values: hours.map(seconds => ({a: seconds}))
                                            maximum: Math.max(60, ...hours)
                                            color: Theme.mix(Theme.key, Theme.textFaint, 0.5)
                                            highlight: root.insights.busiestHour === null || root.insights.busiestHour === undefined ? -1 : root.insights.busiestHour
                                            names: hours.map((seconds, hour) => String(hour).padStart(2, "0") + ":00, " + root.formatTime(seconds))
                                        }
                                        HourAxis { Layout.fillWidth: true }
                                    }
                                    ColumnLayout {
                                        Layout.preferredWidth: 170
                                        Layout.alignment: Qt.AlignTop
                                        spacing: 6
                                        Repeater {
                                            model: [
                                                {label: "Starts", value: root.minuteClock(root.insights.typicalStart)},
                                                {label: "Ends", value: root.minuteClock(root.insights.typicalEnd)},
                                                {label: "Busiest", value: root.insights.busiestHour === null || root.insights.busiestHour === undefined ? "–" : root.minuteClock(root.insights.busiestHour * 60)},
                                                {label: "Since", value: root.overview.firstDay ? Qt.formatDate(new Date(root.overview.firstDay + "T12:00:00"), "d MMM yyyy") : "today"}
                                            ]
                                            Rectangle {
                                                id: rhythm
                                                required property var modelData
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 30
                                                radius: Theme.radiusKey
                                                color: Theme.moduleAlt
                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 10
                                                    anchors.rightMargin: 10
                                                    C.Label { text: rhythm.modelData.label; font.pixelSize: 12; color: Theme.textDim; Layout.fillWidth: true }
                                                    C.Label { text: rhythm.modelData.value; font.pixelSize: 13; font.weight: Font.DemiBold; font.features: ({"tnum": 1}); elide: Text.ElideNone }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        // Top apps this week.
                        C.Card {
                            Layout.preferredWidth: 300
                            Layout.fillHeight: true
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                anchors.topMargin: 12
                                anchors.bottomMargin: 12
                                spacing: 10
                                RowLayout {
                                    Layout.fillWidth: true
                                    ModuleTitle { text: "Top apps this week"; Layout.fillWidth: true }
                                    C.Button {
                                        text: "All apps"
                                        flat: true
                                        labelSize: 12
                                        implicitHeight: 22
                                        padding: 6
                                        foreground: Theme.accentText
                                        onClicked: { root.appsRange = "week"; root.setDate(root.today()); root.mode = "apps"; }
                                    }
                                }
                                Repeater {
                                    model: root.overview.topApps || []
                                    Item {
                                        id: topApp
                                        required property var modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 30
                                        Accessible.role: Accessible.Button
                                        Accessible.name: root.appLabel(modelData.app) + ", " + root.formatTime(modelData.total)
                                        RowLayout {
                                            anchors.fill: parent
                                            spacing: 10
                                            AppTile { app: topApp.modelData.app; rank: topApp.index }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 4
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    C.Label { text: root.appLabel(topApp.modelData.app); font.pixelSize: 13; Layout.fillWidth: true }
                                                    C.Label { text: root.formatTime(topApp.modelData.total); font.pixelSize: 13; font.features: ({"tnum": 1}); color: Theme.textSecondary; elide: Text.ElideNone }
                                                }
                                                AppBar {
                                                    Layout.fillWidth: true
                                                    implicitHeight: 4
                                                    active: topApp.modelData.total
                                                    maximum: (root.overview.topApps[0] || {}).total || 1
                                                    color: topApp.index === 0 ? Theme.accent : Theme.textDim
                                                }
                                            }
                                        }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openApp(topApp.modelData.app) }
                                    }
                                }
                                C.Label {
                                    visible: (root.overview.topApps || []).length === 0
                                    text: "Apps appear here once you use them this week."
                                    font.pixelSize: 13
                                    color: Theme.textDim
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }
                                Item { Layout.fillHeight: true }
                                C.Label {
                                    text: "App names and times only. Never window titles or what's on screen. It stays on this computer."
                                    font.pixelSize: 12
                                    color: Theme.textDim
                                    wrapMode: Text.WordWrap
                                    lineHeight: 1.2
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }
            }

            // Day --------------------------------------------------------------
            Loader {
                anchors.fill: parent
                active: root.mode === "day"
                sourceComponent: ColumnLayout {
                    anchors.fill: parent
                    spacing: 10
                    // The day as a strip you can click: each stretch in an app, watching in the second colour.
                    C.Card {
                        Layout.fillWidth: true
                        Layout.preferredHeight: dayColumn.implicitHeight + 28
                        ColumnLayout {
                            id: dayColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            anchors.topMargin: 14
                            spacing: 10
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                C.Label { text: root.dayTitle(); font.pixelSize: 20; font.weight: 650; elide: Text.ElideNone; Layout.alignment: Qt.AlignBaseline }
                                C.Label {
                                    text: Qt.formatDate(root.selected, root.dayTitle() === Qt.formatDate(root.selected, "dddd") ? "d MMMM yyyy" : "dddd d MMMM")
                                    font.pixelSize: 13
                                    color: Theme.textDim
                                    elide: Text.ElideNone
                                    Layout.alignment: Qt.AlignBaseline
                                }
                                C.Label {
                                    text: root.caption !== "" ? root.caption : "Click a stretch of the day"
                                    font.pixelSize: 13
                                    color: root.caption !== "" ? Theme.textSecondary : Theme.textDim
                                    horizontalAlignment: Text.AlignRight
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignBaseline
                                }
                                C.Button { glyph: "back"; flat: true; implicitWidth: 28; implicitHeight: 28; padding: 6; hint: "Previous day"; onClicked: root.shiftDate(-1) }
                                C.Button { glyph: "chevron"; flat: true; implicitWidth: 28; implicitHeight: 28; padding: 6; enabled: root.selectedDate < root.today(); hint: "Next day"; onClicked: root.shiftDate(1) }
                            }
                            Rectangle {
                                id: timeline
                                Layout.fillWidth: true
                                Layout.preferredHeight: 44
                                radius: Theme.radiusKey
                                color: Theme.well
                                clip: true
                                property int picked: -1
                                Connections {
                                    target: root
                                    function onDayChanged() { timeline.picked = -1; }
                                }
                                Repeater {
                                    model: root.daySpans
                                    Rectangle {
                                        id: span
                                        required property var modelData
                                        required property int index
                                        // Today's last stretch while it's still going.
                                        readonly property bool live: root.showingToday && index === root.daySpans.length - 1 && root.nowMs - modelData.end < 120000 && root.phase !== "paused"
                                        x: root.timeX(modelData.start, timeline.width)
                                        y: 6
                                        width: Math.max(2, root.timeX(modelData.end, timeline.width) - x)
                                        height: timeline.height - 12
                                        radius: Math.min(5, width / 2)
                                        color: live ? Theme.accent : modelData.state === "watching" ? Theme.second : root.appShade(modelData.app)
                                        border.width: timeline.picked === index ? 2 : 0
                                        border.color: Theme.text
                                        Accessible.role: Accessible.Button
                                        Accessible.name: root.appLabel(modelData.app) + ", " + root.clockTime(modelData.start) + " to " + root.clockTime(modelData.end)
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                const segment = span.modelData;
                                                timeline.picked = span.index;
                                                root.caption = root.appLabel(segment.app) + " · " + root.clockTime(segment.start) + " – " + (span.live ? "now" : root.clockTime(segment.end))
                                                    + " · " + root.formatTime((segment.end - segment.start) / 1000) + " " + segment.state;
                                            }
                                        }
                                    }
                                }
                                // Focus sessions underline the time they covered.
                                Repeater {
                                    model: root.day.focus || []
                                    Rectangle {
                                        required property var modelData
                                        x: root.timeX(modelData.start, timeline.width)
                                        y: timeline.height - 4
                                        width: Math.max(2, root.timeX(modelData.end, timeline.width) - x)
                                        height: 2
                                        radius: 1
                                        color: Theme.text
                                    }
                                }
                                Rectangle {
                                    visible: root.showingToday
                                    x: root.timeX(root.nowMs, timeline.width) - 1
                                    width: 2
                                    height: timeline.height
                                    color: Theme.text
                                }
                                C.Label {
                                    anchors.centerIn: parent
                                    visible: root.daySpans.length === 0
                                    text: root.day.legacy ? "Only the daily total was kept for this day" : "Nothing recorded"
                                    font.pixelSize: 12
                                    color: Theme.textDim
                                }
                            }
                            HourAxis { clock: true; Layout.fillWidth: true }
                        }
                    }
                    // How the day split up.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Repeater {
                            model: {
                                const source = root.day;
                                const rows = [
                                    {label: "Active", value: root.formatTime(source.active), color: Theme.accent},
                                    {label: "Watching", value: root.formatTime(source.watching), color: Theme.second},
                                    {label: "Idle", value: root.formatTime(Math.max(0, source.unlocked - source.active - (source.watching || 0))), color: Theme.mix(Theme.key, Theme.textFaint, 0.5)}
                                ];
                                if (source.focused >= 60) rows.push({label: "Focused", value: root.formatTime(source.focused), color: Theme.text});
                                rows.push({label: "First – last", value: source.firstActive ? root.clockTime(source.firstActive) + " – " + (root.showingToday && root.phase !== "paused" && root.nowMs - source.lastActive < 120000 ? "now" : root.clockTime(source.lastActive)) : "–", color: "transparent"});
                                return rows;
                            }
                            C.Card {
                                id: part
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.preferredHeight: 72
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    anchors.topMargin: 12
                                    anchors.bottomMargin: 12
                                    spacing: 4
                                    RowLayout {
                                        spacing: 6
                                        Rectangle { Layout.preferredWidth: 8; Layout.preferredHeight: 8; radius: 2; color: part.modelData.color }
                                        C.Label { text: part.modelData.label; font.pixelSize: 12; color: Theme.textDim }
                                    }
                                    C.Label { text: part.modelData.value; font.pixelSize: 22; font.weight: 650; font.features: ({"tnum": 1}); Layout.fillWidth: true }
                                }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10
                        // Hour by hour.
                        C.Card {
                            Layout.preferredWidth: 380
                            Layout.fillHeight: true
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                anchors.topMargin: 12
                                anchors.bottomMargin: 12
                                spacing: 8
                                ModuleTitle { text: "Hour by hour"; Layout.fillWidth: true }
                                Bars {
                                    id: dayHours
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    values: (root.day.hours || []).map(slot => ({a: slot.active, b: slot.watching || 0}))
                                    maximum: 3600
                                    names: (root.day.hours || []).map(slot => slot.label + ", " + root.formatTime(slot.active) + " active")
                                    onPicked: index => {
                                        const slot = root.day.hours[index];
                                        selectedIndex = index;
                                        root.caption = slot.label + " · " + root.formatTime(slot.active) + " active · " + root.formatTime(slot.watching || 0) + " watching";
                                    }
                                    Connections {
                                        target: root
                                        function onDayChanged() { dayHours.selectedIndex = -1; }
                                    }
                                }
                                HourAxis { Layout.fillWidth: true }
                            }
                        }
                        // The day's apps, each with when its windows were open and when it had you.
                        C.Card {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                anchors.topMargin: 12
                                anchors.bottomMargin: 12
                                spacing: 8
                                ModuleTitle { text: "Apps"; note: "open in grey, in use in colour"; Layout.fillWidth: true }
                                ScrollView {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    contentWidth: availableWidth
                                    ColumnLayout {
                                        width: parent.width
                                        spacing: 8
                                        Repeater {
                                            model: root.dayAppRows
                                            ColumnLayout {
                                                id: appLine
                                                required property var modelData
                                                required property int index
                                                Layout.fillWidth: true
                                                spacing: 4
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 8
                                                    AppTile { app: appLine.modelData.app; rank: appLine.index; size: 20 }
                                                    C.Label {
                                                        text: root.appLabel(appLine.modelData.app)
                                                        font.pixelSize: 13
                                                        Layout.fillWidth: true
                                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openApp(appLine.modelData.app) }
                                                    }
                                                    C.Label {
                                                        text: (appLine.modelData.windows.some(window => !window.startKnown || window.endReason === "gap") ? "partial · " : "") + root.formatTime(appLine.modelData.total)
                                                        font.pixelSize: 12
                                                        font.features: ({"tnum": 1})
                                                        color: Theme.textSecondary
                                                        elide: Text.ElideNone
                                                    }
                                                }
                                                Item {
                                                    id: lane
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 6
                                                    Rectangle { anchors.fill: parent; radius: 3; color: Theme.key }
                                                    Repeater {
                                                        model: appLine.modelData.windows
                                                        Rectangle {
                                                            required property var modelData
                                                            x: root.timeX(modelData.start, lane.width)
                                                            width: Math.max(2, root.timeX(modelData.end, lane.width) - x)
                                                            height: lane.height
                                                            radius: 3
                                                            color: Theme.mix(Theme.key, Theme.textFaint, 0.6)
                                                            MouseArea {
                                                                anchors.fill: parent
                                                                anchors.topMargin: -4
                                                                anchors.bottomMargin: -4
                                                                onClicked: {
                                                                    const window = parent.modelData;
                                                                    root.caption = root.appLabel(window.app) + " · " + (window.startKnown ? "opened " : "already open at ") + root.clockTime(window.start) + " · "
                                                                        + (window.endReason === "open" ? "still open" : window.endReason === "continues" ? "continued next day" : window.endReason === "gap" ? "last seen " + root.clockTime(window.end) : "closed " + root.clockTime(window.end));
                                                                }
                                                            }
                                                        }
                                                    }
                                                    Repeater {
                                                        model: appLine.modelData.focus
                                                        Rectangle {
                                                            required property var modelData
                                                            x: root.timeX(modelData.start, lane.width)
                                                            width: Math.max(2, root.timeX(modelData.end, lane.width) - x)
                                                            height: lane.height
                                                            radius: 3
                                                            color: modelData.state === "watching" ? Theme.second : Theme.accent
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        C.Label {
                                            visible: root.dayAppRows.length === 0
                                            text: root.day.detailAvailable ? "No app windows recorded on this day." : "This day was recorded before app detail was kept; only its total remains."
                                            font.pixelSize: 13
                                            color: Theme.textDim
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Apps -------------------------------------------------------------
            Loader {
                anchors.fill: parent
                active: root.mode === "apps" && root.appDetail === ""
                sourceComponent: C.Card {
                    anchors.fill: parent
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.topMargin: 12
                        anchors.bottomMargin: 12
                        spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 4
                            spacing: 10
                            C.Label { text: root.formatTime(root.appsData.total); font.pixelSize: 20; font.weight: 650; font.features: ({"tnum": 1}); elide: Text.ElideNone }
                            C.Label { text: root.appsSummary(); font.pixelSize: 13; color: Theme.textDim; Layout.fillWidth: true }
                            C.Segmented {
                                fill: false
                                segmentHeight: 30
                                trackColor: Theme.well
                                model: [{key: "day", text: "Day"}, {key: "week", text: "Week"}, {key: "month", text: "Month"}]
                                current: root.appsRange
                                onActivated: key => root.appsRange = key
                            }
                            C.Button { glyph: "back"; flat: true; implicitWidth: 28; implicitHeight: 28; padding: 6; hint: "Earlier"; onClicked: root.shiftPeriod(-1) }
                            C.Label { text: root.periodLabel(); font.pixelSize: 13; color: Theme.textSecondary; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 150 }
                            C.Button { glyph: "chevron"; flat: true; implicitWidth: 28; implicitHeight: 28; padding: 6; enabled: root.appsData.end < root.today(); hint: "Later"; onClicked: root.shiftPeriod(1) }
                        }
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            ListView {
                                id: appList
                                anchors.fill: parent
                                clip: true
                                spacing: 0
                                boundsBehavior: Flickable.StopAtBounds
                                model: root.appsData.apps || []
                                currentIndex: -1
                                activeFocusOnTab: true
                                keyNavigationEnabled: true
                                Accessible.role: Accessible.List
                                Accessible.name: "Apps by time"
                                Keys.onPressed: event => {
                                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) && currentIndex >= 0) {
                                        root.openApp(model[currentIndex].app);
                                        event.accepted = true;
                                    }
                                }
                                onActiveFocusChanged: if (activeFocus && currentIndex < 0 && count > 0) currentIndex = 0
                                delegate: Rectangle {
                                    id: appRow
                                    required property var modelData
                                    required property int index
                                    readonly property bool current: appList.activeFocus && ListView.isCurrentItem
                                    width: appList.width
                                    height: 42
                                    radius: Theme.radiusKey
                                    color: current ? Theme.accentSoft : rowArea.containsMouse ? Theme.mix(Theme.moduleAlt, Theme.text, 0.04) : index % 2 === 0 ? Theme.moduleAlt : "transparent"
                                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                                    Accessible.role: Accessible.ListItem
                                    Accessible.name: root.appLabel(modelData.app) + ", " + root.formatTime(modelData.total)
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 12
                                        AppTile { app: appRow.modelData.app; rank: appRow.index }
                                        C.Label { text: root.appLabel(appRow.modelData.app); font.pixelSize: 14; Layout.preferredWidth: 140 }
                                        AppBar {
                                            Layout.fillWidth: true
                                            active: appRow.modelData.active
                                            watching: appRow.modelData.watching
                                            maximum: ((root.appsData.apps || [])[0] || {}).total || 1
                                        }
                                        C.Label {
                                            text: root.formatTime(appRow.modelData.total)
                                            font.pixelSize: 13
                                            font.features: ({"tnum": 1})
                                            horizontalAlignment: Text.AlignRight
                                            Layout.preferredWidth: 70
                                        }
                                    }
                                    MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openApp(appRow.modelData.app) }
                                }
                            }
                            C.EmptyState {
                                visible: appList.count === 0
                                anchors.centerIn: parent
                                width: Math.min(parent.width, 360)
                                glyph: "activity"
                                title: "No app time in this " + root.appsRange
                                description: "Focused apps are counted while you are active or watching."
                            }
                        }
                        RowLayout {
                            spacing: 14
                            RowLayout { spacing: 6; Swatch { color: Theme.accent } C.Label { text: "Active"; font.pixelSize: 12; color: Theme.textDim } }
                            RowLayout { spacing: 6; Swatch { color: Theme.second } C.Label { text: "Watching"; font.pixelSize: 12; color: Theme.textDim } }
                        }
                    }
                }
            }

            // App detail -------------------------------------------------------
            Loader {
                anchors.fill: parent
                active: root.mode === "apps" && root.appDetail !== ""
                sourceComponent: C.Card {
                    anchors.fill: parent
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.topMargin: 12
                        anchors.bottomMargin: 12
                        spacing: 10
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            C.Button { glyph: "back"; flat: true; implicitWidth: 28; implicitHeight: 28; padding: 6; hint: "All apps · Escape"; onClicked: root.appDetail = "" }
                            AppTile { app: root.appDetail; rank: Math.max(0, (root.appsData.apps || []).findIndex(entry => entry.app === root.appDetail)) }
                            C.Label { text: root.appLabel(root.appDetail); font.pixelSize: 20; font.weight: 650; elide: Text.ElideNone }
                            C.Label { text: root.appDetail; font.pixelSize: 12; font.family: Theme.mono; color: Theme.textFaint; elide: Text.ElideMiddle; Layout.fillWidth: true }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            C.Stat { label: "All time"; value: root.formatTime(root.appData.total); note: root.formatTime(root.appData.watching) + " watching"; valueSize: 20; noteSize: 12; noteColor: Theme.textDim }
                            C.Stat { label: "Last 30 days"; value: root.formatTime((root.appData.days || []).reduce((sum, entry) => sum + entry.total, 0)); note: (root.appData.days || []).filter(entry => entry.total >= 60).length + " days used"; valueSize: 20; noteSize: 12; noteColor: Theme.textDim }
                            C.Stat { label: "Per day used"; value: root.formatTime(root.appData.averagePerDay); note: root.appData.daysUsed + " days in all"; valueSize: 20; noteSize: 12; noteColor: Theme.textDim }
                            C.Stat { label: "First seen"; value: root.appData.firstDay ? Qt.formatDate(new Date(root.appData.firstDay + "T12:00:00"), "d MMM") : "–"; note: root.appData.firstDay ? Qt.formatDate(new Date(root.appData.firstDay + "T12:00:00"), "yyyy") : " "; valueSize: 20; noteSize: 12; noteColor: Theme.textDim }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 10
                            Rectangle {
                                id: monthCard
                                // The picked day, once one is.
                                property string note: ""
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.preferredWidth: 3
                                radius: Theme.radiusCard
                                color: Theme.moduleAlt
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 8
                                    ModuleTitle { text: "Last 30 days"; note: monthCard.note; Layout.fillWidth: true }
                                    Bars {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        values: (root.appData.days || []).map(entry => ({a: entry.total}))
                                        maximum: Math.max(3600, ...(root.appData.days || []).map(entry => entry.total))
                                        names: (root.appData.days || []).map(entry => entry.date + ", " + root.formatTime(entry.total))
                                        onPicked: index => {
                                            selectedIndex = index;
                                            const entry = root.appData.days[index];
                                            monthCard.note = Qt.formatDate(new Date(entry.date + "T12:00:00"), "ddd d MMM") + " · " + root.formatTime(entry.total);
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        C.Label { text: (root.appData.days || []).length ? Qt.formatDate(new Date(root.appData.days[0].date + "T12:00:00"), "d MMM") : ""; font.pixelSize: 11; color: Theme.textDim; Layout.fillWidth: true }
                                        C.Label { text: "today"; font.pixelSize: 11; color: Theme.textDim }
                                    }
                                }
                            }
                            Rectangle {
                                id: hourCard
                                property string note: "last 30 days"
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.preferredWidth: 2
                                radius: Theme.radiusCard
                                color: Theme.moduleAlt
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 8
                                    ModuleTitle { text: "When you use it"; note: hourCard.note; Layout.fillWidth: true }
                                    Bars {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        values: (root.appData.hours || []).map(seconds => ({a: seconds}))
                                        maximum: Math.max(60, ...(root.appData.hours || []))
                                        names: (root.appData.hours || []).map((seconds, hour) => String(hour).padStart(2, "0") + ":00, " + root.formatTime(seconds))
                                        onPicked: index => {
                                            selectedIndex = index;
                                            hourCard.note = String(index).padStart(2, "0") + ":00 · " + root.formatTime(root.appData.hours[index]) + " over 30 days";
                                        }
                                    }
                                    HourAxis { Layout.fillWidth: true }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Kept out of the way of the views: what this is, and the one way to wipe it (hold to confirm).
        RowLayout {
            visible: root.tracking !== "ask"
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            spacing: 12
            C.Label { text: "Private · local only · kept until you clear it"; font.pixelSize: 12; color: Theme.textDim; Layout.fillWidth: true; Layout.leftMargin: 2 }
            C.HoldButton {
                id: clearHistoryButton
                text: "Clear history"
                glyph: "trash"
                destructive: true
                // Measured: an eliding label reports its constrained width, not its natural one.
                implicitWidth: Math.max(150, Math.ceil(clearMetrics.advanceWidth) + 16 + 12 + 24 + leftPadding + rightPadding)
                TextMetrics {
                    id: clearMetrics
                    text: clearHistoryButton.text
                    font.family: Theme.font
                    font.pixelSize: Theme.body
                    font.weight: Font.DemiBold
                }
                implicitHeight: 32
                leftPadding: 12
                rightPadding: 12
                // Even, so the label sits on the button's centre line.
                topPadding: 0
                bottomPadding: 0
                armed: !root.busy && Backend.ready
                onConfirmed: root.clear()
            }
        }
    }
    Keys.onPressed: event => {
        if (tracking !== "on")
            return;
        if (event.key === Qt.Key_Escape && mode === "apps" && appDetail !== "") {
            appDetail = ""; event.accepted = true;
        } else if (event.key === Qt.Key_1 || event.key === Qt.Key_2 || event.key === Qt.Key_3) {
            mode = ["overview", "day", "apps"][event.key - Qt.Key_1]; event.accepted = true;
        } else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right) && mode !== "overview") {
            const step = event.key === Qt.Key_Left ? -1 : 1;
            if (mode === "apps") shiftPeriod(step);
            else shiftDate(step);
            event.accepted = true;
        } else if (event.key === Qt.Key_Home && mode !== "overview") { setDate(today()); event.accepted = true; }
    }
}
