import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../core"
import "../components" as C

FocusScope {
    id: root
    readonly property string title: "Activity"
    readonly property int panelWidth: 720
    readonly property int panelHeight: 620
    readonly property int graphWeeks: width < 520 ? 26 : 53
    property string mode: "overview"
    property string selectedDate: today()
    property var overview: ({days: [], started: null, paused: false, state: null, insights: ({}), topApps: [], firstDay: null})
    property var day: ({segments: [], windows: [], hours: [], apps: [], active: 0, watching: 0, unlocked: 0, detailAvailable: true, firstActive: null, lastActive: null})
    property var week: ({days: [], apps: []})
    property string appsRange: "week"
    property var appsData: ({apps: [], total: 0, previousTotal: 0, days: [], start: "", end: ""})
    property string appDetail: ""
    property var appData: ({days: [], hours: [], total: 0, daysUsed: 0, firstDay: null, averagePerDay: 0})
    property int heatPage: 0
    property bool busy: false
    property string error: ""
    property bool alive: true
    property bool weekly: false
    property string caption: ""
    property real contentProgress: 1
    readonly property bool previewMode: Quickshell.env("SHALE_PREVIEW") === "activity" && Quickshell.env("SHALE_DETAIL") !== ""
    // "ask" until chosen here; nothing is recorded or shown unless it's "on".
    readonly property string tracking: ShellState.setting("activityTracking", "ask")
    readonly property date selected: new Date(selectedDate + "T12:00:00")
    // Weeks start on the locale's first day, as in the Calendar.
    readonly property int weekStart: Qt.locale().firstDayOfWeek % 7
    readonly property var insights: overview.insights || ({})
    readonly property var dayMap: {
        const result = {};
        for (const entry of overview.days || []) result[entry.date] = entry;
        return result;
    }
    // Apps keep one color across the day: ranked by time, the top six get hues, the rest share "other".
    readonly property var dayRanking: (day.apps || []).slice(0, 6).map(entry => entry.app)
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
    readonly property string heatRange: heatmapDays.length ? Qt.formatDate(new Date(heatmapDays[0].date + "T12:00:00"), "MMM yyyy") + " – " + Qt.formatDate(new Date(heatmapDays[heatmapDays.length - 1].date + "T12:00:00"), "MMM yyyy") : ""
    readonly property bool heatHasEarlier: !!overview.firstDay && heatmapDays.length > 0 && overview.firstDay < heatmapDays[0].date
    readonly property var monthCells: {
        const start = new Date(selected.getFullYear(), selected.getMonth(), 1, 12);
        start.setDate(start.getDate() - ((start.getDay() - weekStart + 7) % 7));
        const days = [];
        for (let i = 0; i < 42; i++) {
            const date = new Date(start);
            date.setDate(start.getDate() + i);
            days.push({date: Qt.formatDate(date, "yyyy-MM-dd"), number: date.getDate(), current: date.getMonth() === selected.getMonth()});
        }
        return days;
    }
    readonly property bool weekHasHours: (week.days || []).some(entry => (entry.hours || []).length > 0)
    readonly property var weekHourLabels: {
        const labels = [];
        for (let hour = 0; hour < 24; hour++) {
            const number = String(hour).padStart(2, "0");
            const repeated = (week.days || []).some(entry => (entry.hours || []).some(slot => slot.label === number + "a"));
            if (repeated) labels.push(number + "a", number + "b");
            else labels.push(number + ":00");
        }
        return labels;
    }
    readonly property var dayAppRows: {
        const windows = {};
        for (const window of day.windows || []) (windows[window.app] = windows[window.app] || []).push(window);
        const focus = {};
        for (const segment of day.segments || []) if (segment.app && segment.state !== "idle") (focus[segment.app] = focus[segment.app] || []).push(segment);
        const rows = (day.apps || []).map(entry => ({app: entry.app, total: entry.total, windows: windows[entry.app] || [], focus: focus[entry.app] || []}));
        for (const app in windows) if (!focus[app]) rows.push({app: app, total: 0, windows: windows[app], focus: []});
        return rows;
    }
    readonly property double dayStart: new Date(selected.getFullYear(), selected.getMonth(), selected.getDate()).getTime()
    readonly property int dayLength: new Date(selected.getFullYear(), selected.getMonth(), selected.getDate() + 1).getTime() - dayStart

    function today() { return Qt.formatDate(new Date(), "yyyy-MM-dd"); }
    function formatTime(seconds) {
        if (!seconds || seconds < 60) return "0m";
        const minutes = Math.round(seconds / 60);
        return minutes >= 60 ? Math.floor(minutes / 60) + "h " + String(minutes % 60).padStart(2, "0") + "m" : minutes + "m";
    }
    function delta(now, before) {
        if (before === null || before === undefined || before < 60) return "";
        const change = Math.round((now - before) / before * 100);
        return change === 0 ? "same as before" : (change > 0 ? "▲ " : "▼ ") + Math.abs(change) + "%";
    }
    function clockTime(milliseconds) { return Qt.formatTime(new Date(milliseconds), ShellState.timeFormat); }
    function minuteClock(minutes) {
        if (minutes === null || minutes === undefined) return "–";
        const value = Math.round(minutes) % 1440;
        return Qt.formatTime(new Date(2000, 0, 1, Math.floor(value / 60), value % 60), ShellState.timeFormat);
    }
    function heatLevel(seconds) { return seconds >= 14400 ? 4 : seconds >= 7200 ? 3 : seconds >= 2400 ? 2 : seconds >= 60 ? 1 : 0; }
    function heatColor(seconds) {
        const level = heatLevel(seconds);
        return level === 4 ? Theme.accent : level === 3 ? Theme.activityLevel3 : level === 2 ? Theme.activityLevel2 : level === 1 ? Theme.activityLevel1 : Theme.raised;
    }
    function stateColor(state) { return state === "active" ? Theme.accent : state === "watching" ? Theme.activityWatching : Theme.activityIdle; }
    function appColor(app) {
        const index = dayRanking.indexOf(app);
        return Theme.activityApps[index >= 0 ? index : Theme.activityApps.length - 1];
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
    function appIcon(app) {
        const entry = app ? appEntry(app) : null;
        const icon = entry ? entry.icon || "" : "";
        if (icon.startsWith("/")) return "file://" + icon;
        if (icon.startsWith("file:")) return icon;
        return icon && Quickshell.hasThemeIcon(icon) ? Quickshell.iconPath(icon) : "";
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
    // Pages the heatmap to the selected day.
    function revealHeat() {
        while (heatHasEarlier && selectedDate < heatmapDays[0].date)
            heatPage++;
        while (heatPage > 0 && selectedDate > heatmapDays[heatmapDays.length - 1].date)
            heatPage--;
    }
    function timeX(milliseconds, width) { return Math.max(0, Math.min(width, (milliseconds - dayStart) / dayLength * width)); }
    function periodLabel() {
        if (!appsData.start) return "";
        const first = new Date(appsData.start + "T12:00:00"), last = new Date(appsData.end + "T12:00:00");
        if (appsRange === "day") return Qt.formatDate(first, "ddd, d MMM yyyy");
        if (appsRange === "month") return Qt.formatDate(first, "MMMM yyyy");
        return Qt.formatDate(first, "d MMM") + " – " + Qt.formatDate(last, "d MMM yyyy");
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
    function openApp(app) {
        appDetail = app;
        loadApp();
    }
    function request(method, params, done) {
        if (!Backend.ready) return;
        Backend.request(method, params, (result, failure) => {
            if (!alive) return;
            if (failure) error = failure.message;
            else { error = ""; done(result); }
        });
    }
    function loadOverview() { request("activity.overview", {weekStart: weekStart}, result => overview = result); }
    function loadDay() {
        const date = selectedDate;
        request("activity.day", {date: date}, result => { if (date === selectedDate) day = result; });
        request("activity.week", {date: date, weekStart: weekStart}, result => { if (date === selectedDate) week = result; });
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
        if (previewMode || tracking !== "on") return;
        loadOverview();
        loadDay();
        if (mode === "apps") { loadApps(); loadApp(); }
    }
    onModeChanged: {
        contentProgress = 0;
        modeEntrance.restart();
        caption = "";
        if (mode === "apps" && !previewMode) loadApps();
    }
    onAppsRangeChanged: if (!previewMode) loadApps()
    onTrackingChanged: refresh()
    NumberAnimation { id: modeEntrance; target: root; property: "contentProgress"; to: 1; duration: Theme.enter; easing.type: Easing.OutCubic }
    function pause() {
        if (busy) return;
        busy = true;
        Backend.request("activity.pause", {paused: !overview.paused}, (result, failure) => {
            if (!alive) return;
            busy = false;
            if (failure) error = failure.message;
            else {
                overview = Object.assign({}, overview, result);
                if (!result.paused) ShellState.activitySnapshotRequested();
                refresh();
            }
        });
    }
    function clear() {
        if (busy) return;
        busy = true;
        Backend.request("activity.clear", {}, (result, failure) => {
            if (!alive) return;
            busy = false;
            clearHistoryButton.triggered = false;
            if (failure) error = failure.message;
            else { ShellState.activitySnapshotRequested(); refresh(); }
        });
    }
    function previewSample() {
        const now = new Date();
        const current = Qt.formatDate(now, "yyyy-MM-dd");
        selectedDate = current;
        const days = [];
        for (let i = 0; i < 200; i++) {
            const date = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i, 12);
            const rest = i % 7 === 0;
            days.push({date: Qt.formatDate(date, "yyyy-MM-dd"), active: rest ? 0 : 1200 + ((i * 31) % 150) * 90, watching: rest ? 0 : ((i * 17) % 40) * 90, unlocked: rest ? 0 : 18000});
        }
        days.reverse();
        const apps = ["firefox", "kitty", "code-oss", "thunderbird", "libreoffice-writer", "mpv", "thunar"];
        const totals = [21600, 14400, 5400, 2700, 1500, 900, 300];
        const ranked = apps.map((app, index) => ({app: app, active: totals[index] * 0.8, watching: totals[index] * 0.2, total: totals[index], share: totals[index] / 46800, previous: totals[index] * (index % 2 ? 1.3 : 0.8), first: 0, last: 0}));
        overview = {days: days, started: now.getTime() - 200 * 86400000, firstDay: days[0].date, paused: false, state: "active", topApps: ranked.slice(0, 5),
            insights: {today: 16800, average7: 14200, average30: 13100, thisWeek: 61200, lastWeek: 55800, streak: 12, longestStreak: 31, typicalStart: 548, typicalEnd: 1390, busiestHour: 21}};
        const beginning = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        const hour = 3600000;
        const segments = [];
        const plan = [[9, 10.5, "active", "firefox"], [10.5, 10.6, "idle", null], [10.6, 12, "active", "kitty"], [12, 13, "idle", null], [13, 14.2, "active", "code-oss"],
                      [14.2, 15, "active", "firefox"], [15, 16.5, "watching", "firefox"], [16.5, 18, "active", "kitty"], [18, 18.4, "active", "thunderbird"],
                      [20, 21.5, "active", "libreoffice-writer"], [21.5, 23, "watching", "mpv"]];
        for (const entry of plan) segments.push({start: beginning + entry[0] * hour, end: beginning + entry[1] * hour, state: entry[2], app: entry[3]});
        const hours = [];
        for (let h = 0; h < 24; h++) {
            const slot = {start: beginning + h * hour, end: beginning + (h + 1) * hour, label: String(h).padStart(2, "0") + ":00", active: 0, watching: 0, unlocked: 0};
            for (const segment of segments) {
                const overlap = Math.max(0, Math.min(slot.end, segment.end) - Math.max(slot.start, segment.start)) / 1000;
                slot.unlocked += overlap;
                if (segment.state !== "idle") slot[segment.state] += overlap;
            }
            hours.push(slot);
        }
        const dayApps = ranked.slice(0, 6);
        day = {date: current, active: 36000, watching: 10800, unlocked: 50400, detailAvailable: true, legacy: false, hours: hours, segments: segments, apps: dayApps,
            firstActive: beginning + 9 * hour, lastActive: beginning + 23 * hour, windows: [
                {app: "firefox", start: beginning + 9 * hour, end: beginning + 23 * hour, startKnown: true, endReason: "open"},
                {app: "kitty", start: beginning + 10 * hour, end: beginning + 18 * hour, startKnown: true, endReason: "closed"},
                {app: "code-oss", start: beginning + 12.8 * hour, end: beginning + 14.4 * hour, startKnown: true, endReason: "closed"},
                {app: "thunderbird", start: beginning + 8 * hour, end: beginning + 23.5 * hour, startKnown: false, endReason: "open"},
                {app: "libreoffice-writer", start: beginning + 19.8 * hour, end: beginning + 22 * hour, startKnown: true, endReason: "closed"},
                {app: "mpv", start: beginning + 21.4 * hour, end: beginning + 23.2 * hour, startKnown: true, endReason: "closed"}]};
        const weekBegin = new Date(now.getFullYear(), now.getMonth(), now.getDate() - ((now.getDay() - weekStart + 7) % 7), 12);
        week = {apps: ranked, days: Array.from({length: 7}, (_, index) => {
            const date = new Date(weekBegin);
            date.setDate(weekBegin.getDate() + index);
            const key = Qt.formatDate(date, "yyyy-MM-dd");
            return Object.assign({date: key, active: 0, watching: 0, unlocked: 0}, days.find(entry => entry.date === key) || {},
                {hours: hours.map(slot => Object.assign({}, slot, {active: slot.active * (index + 2) / 8, watching: slot.watching * (index + 2) / 8, unlocked: slot.unlocked * (index + 2) / 8}))});
        })};
        appsData = {range: "week", start: Qt.formatDate(weekBegin, "yyyy-MM-dd"), end: Qt.formatDate(new Date(weekBegin.getTime() + 6 * 86400000), "yyyy-MM-dd"), apps: ranked, total: 46800, previousTotal: 41000, days: []};
        appData = {app: "firefox", total: 412000, active: 330000, watching: 82000, daysUsed: 61, firstDay: days[0].date, averagePerDay: 6754,
            days: Array.from({length: 30}, (_, index) => ({date: Qt.formatDate(new Date(now.getTime() - (29 - index) * 86400000), "yyyy-MM-dd"), total: index % 7 === 3 ? 0 : 3600 + ((index * 37) % 11) * 900})),
            hours: Array.from({length: 24}, (_, h) => h < 8 ? 0 : 1800 + Math.sin(h / 3) * 1500 + (h > 19 ? 2600 : 0))};
        const detail = Quickshell.env("SHALE_DETAIL");
        mode = detail === "week" ? "day" : detail === "app" ? "apps" : ["day", "apps"].indexOf(detail) >= 0 ? detail : "overview";
        weekly = detail === "week";
        if (detail === "app") appDetail = "firefox";
        if (detail === "day") caption = "Firefox  ·  14:12–15:00  ·  48m active";
    }
    Component.onCompleted: {
        if (previewMode) previewSample();
        else refresh();
    }
    Component.onDestruction: alive = false
    Connections {
        target: Backend
        function onReadyChanged() { if (Backend.ready) root.refresh(); }
    }
    Timer { interval: 30000; running: Quickshell.env("SHALE_PREVIEW") !== "activity" && root.tracking === "on"; repeat: true; onTriggered: root.refresh() }

    // Reusable pieces ----------------------------------------------------------
    component AppGlyph: Item {
        id: glyph
        property string source: ""
        property int size: 16
        implicitWidth: size
        implicitHeight: size
        Image {
            id: appImage
            anchors.fill: parent
            source: glyph.source
            visible: status === Image.Ready
            sourceSize.width: glyph.size
            sourceSize.height: glyph.size
        }
        C.Icon { anchors.fill: parent; visible: appImage.status !== Image.Ready; name: "window"; size: glyph.size }
    }
    component Swatch: Rectangle {
        Layout.preferredWidth: 9
        Layout.preferredHeight: 9
        radius: 2
    }
    component ColumnChart: Item {
        id: chart
        // values: [{a, b}] stacked from the bottom; a uses the accent, b the watching color.
        property var values: []
        property real maximum: 1
        property int selectedIndex: -1
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
                    Rectangle { anchors.fill: parent; radius: 2; color: Theme.raised; opacity: column.index === chart.selectedIndex ? 1 : 0.55 }
                    Rectangle {
                        id: lower
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Math.min(1, (column.modelData.a || 0) / chart.maximum) * parent.height
                        radius: 2
                        color: Theme.accent
                        Behavior on height { NumberAnimation { duration: Theme.enter; easing.type: Easing.OutCubic } }
                    }
                    Rectangle {
                        anchors.bottom: lower.top
                        width: parent.width
                        height: Math.min(1, (column.modelData.b || 0) / chart.maximum) * parent.height
                        radius: 2
                        color: Theme.activityWatching
                        Behavior on height { NumberAnimation { duration: Theme.enter; easing.type: Easing.OutCubic } }
                    }
                    MouseArea { anchors.fill: parent; onClicked: chart.picked(column.index) }
                }
            }
        }
    }
    component AppBar: Item {
        id: bar
        property real active: 0
        property real watching: 0
        property real maximum: 1
        implicitHeight: 6
        Rectangle { anchors.fill: parent; radius: height / 2; color: Theme.raised }
        Rectangle {
            id: activePart
            width: Math.max(bar.active > 0 ? 3 : 0, bar.width * Math.min(1, bar.active / Math.max(1, bar.maximum)))
            height: parent.height
            radius: height / 2
            color: Theme.accent
            Behavior on width { NumberAnimation { duration: Theme.enter; easing.type: Easing.OutCubic } }
        }
        Rectangle {
            x: activePart.width
            width: bar.width * Math.min(1, bar.watching / Math.max(1, bar.maximum))
            height: parent.height
            radius: height / 2
            color: Theme.activityWatching
            Behavior on width { NumberAnimation { duration: Theme.enter; easing.type: Easing.OutCubic } }
        }
    }
    component HourAxis: RowLayout {
        spacing: 0
        Repeater {
            model: ["00", "06", "12", "18", "24"]
            C.Caption {
                required property string modelData
                required property int index
                text: modelData
                font.family: Theme.mono
                color: Theme.disabled
                Layout.fillWidth: index > 0 && index < 4
                Layout.preferredWidth: index > 0 && index < 4 ? 2 : 1
                horizontalAlignment: index === 0 ? Text.AlignLeft : index === 4 ? Text.AlignRight : Text.AlignHCenter
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.gapM
        RowLayout {
            visible: root.tracking === "on"
            Layout.fillWidth: true
            spacing: Theme.gapS
            C.Segmented {
                fill: false
                Layout.preferredWidth: 300
                model: [{key: "overview", text: "Overview"}, {key: "day", text: "Day"}, {key: "apps", text: "Apps"}]
                current: root.mode
                onActivated: key => { root.mode = key; if (key !== "apps") root.appDetail = ""; }
            }
            Item { Layout.fillWidth: true }
            C.Label {
                readonly property string phase: root.overview.paused ? "paused" : root.overview.state || "away"
                text: "●  " + ({paused: "Paused", active: "Active now", watching: "Watching", idle: "Idle", away: "Tracking"})[phase]
                font.pixelSize: Theme.small
                font.weight: Font.DemiBold
                color: phase === "paused" || phase === "away" || phase === "idle" ? Theme.muted : phase === "watching" ? Theme.warning : Theme.accent
                Layout.rightMargin: 4
            }
            C.Button { text: root.overview.paused ? "Resume" : "Pause"; glyph: root.overview.paused ? "play" : "pause"; enabled: !root.busy && Backend.ready; onClicked: root.pause() }
        }
        C.Label { visible: root.error !== ""; text: root.error; color: Theme.danger; Layout.fillWidth: true; wrapMode: Text.WordWrap }

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
                                C.Icon { name: parent.modelData.glyph; size: 16; color: Theme.muted; Layout.alignment: Qt.AlignTop }
                                C.Label { text: parent.modelData.text; font.pixelSize: Theme.small; wrapMode: Text.WordWrap; Layout.fillWidth: true }
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
                        implicitHeight: 40
                        onClicked: ShellState.setSetting("activityTracking", "off")
                    }
                    C.Button {
                        text: "Turn on"
                        accent: true
                        implicitHeight: 40
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
            ColumnLayout {
                anchors.fill: parent
                visible: root.mode === "overview"
                spacing: Theme.gapS
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.gapS
                    C.Stat {
                        label: "Today"
                        value: root.formatTime(root.insights.today)
                        note: root.insights.average7 ? root.delta(root.insights.today, root.insights.average7) + " vs 7-day average" : "Active time so far"
                    }
                    C.Stat {
                        label: "This week"
                        value: root.formatTime(root.insights.thisWeek)
                        note: root.insights.lastWeek ? root.delta(root.insights.thisWeek, root.insights.lastWeek) + " vs last week" : "Since " + Qt.locale().dayName(root.weekStart || 7, Locale.LongFormat)
                    }
                    C.Stat {
                        label: "Daily average"
                        value: root.insights.average30 === null || root.insights.average30 === undefined ? "–" : root.formatTime(root.insights.average30)
                        note: "Last 30 days"
                    }
                    C.Stat {
                        label: "Streak"
                        value: (root.insights.streak || 0) + ((root.insights.streak || 0) === 1 ? " day" : " days")
                        note: "Best " + (root.insights.longestStreak || 0) + " · 15m+ a day"
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.gapXs
                    C.Label { text: "Your year, in moments"; font.pixelSize: Theme.small; font.weight: Font.Medium; color: Theme.muted; Layout.fillWidth: true }
                    C.Caption { text: root.heatRange; color: Theme.disabled; Layout.rightMargin: 4 }
                    C.Button { glyph: "back"; flat: true; implicitWidth: 28; implicitHeight: 24; enabled: root.heatHasEarlier; hint: "Earlier"; onClicked: root.heatPage++ }
                    C.Button { glyph: "chevron"; flat: true; implicitWidth: 28; implicitHeight: 24; enabled: root.heatPage > 0; hint: "Later"; onClicked: root.heatPage-- }
                }
                C.Card {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 106
                    border.width: heatmap.activeFocus ? 1.5 : 0
                    border.color: Theme.accent
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: Theme.gapS
                        ColumnLayout {
                            Layout.preferredWidth: 14
                            spacing: Theme.gapXs
                            Repeater {
                                model: [0, 1, 2, 3, 4, 5, 6].map(row => row % 2 === 0 && row < 6 ? Qt.locale().dayName(((root.weekStart + row) % 7) || 7, Locale.NarrowFormat) : "")
                                C.Caption { required property string modelData; text: modelData; font.family: Theme.mono; color: Theme.disabled; Layout.preferredHeight: 10; verticalAlignment: Text.AlignVCenter }
                            }
                        }
                        GridLayout {
                            id: heatmap
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            columns: root.graphWeeks
                            rows: 7
                            flow: GridLayout.TopToBottom
                            columnSpacing: Theme.gapXs
                            rowSpacing: Theme.gapXs
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
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 10
                                    radius: 2
                                    color: modelData.future || modelData.before ? "transparent" : root.heatColor(modelData.active)
                                    border.width: modelData.date === root.selectedDate ? 2 : 0
                                    border.color: heatmap.activeFocus ? Theme.accent : Theme.text
                                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: !parent.modelData.future && !parent.modelData.before
                                        onClicked: root.setDate(parent.modelData.date)
                                        onDoubleClicked: root.mode = "day"
                                    }
                                    Accessible.role: Accessible.Button
                                    Accessible.name: modelData.date + (modelData.before ? ", before tracking began" : ", " + root.formatTime(modelData.active))
                                }
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.gapXs
                    C.Caption { text: "Less"; color: Theme.disabled }
                    Repeater {
                        model: [Theme.raised, Theme.activityLevel1, Theme.activityLevel2, Theme.activityLevel3, Theme.accent]
                        Rectangle { required property color modelData; width: 10; height: 10; radius: 2; color: modelData }
                    }
                    C.Caption { text: "More"; color: Theme.disabled; Layout.fillWidth: true }
                    C.Caption {
                        readonly property var entry: root.dayMap[root.selectedDate] || ({})
                        text: Qt.formatDate(root.selected, "ddd d MMM") + "  ·  " + root.formatTime(entry.active) + " active" + (entry.watching >= 60 ? "  ·  " + root.formatTime(entry.watching) + " watching" : "")
                    }
                    C.Button { text: "Open day"; flat: true; implicitHeight: 24; onClicked: root.mode = "day" }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Theme.gapS
                    C.Card {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 3
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 11
                            spacing: Theme.gapXs
                            RowLayout {
                                Layout.fillWidth: true
                                C.Label { text: "Top apps this week"; font.pixelSize: Theme.small; font.weight: Font.Medium; color: Theme.muted; Layout.fillWidth: true }
                                C.Button { text: "All apps"; flat: true; implicitHeight: 22; onClicked: { root.appsRange = "week"; root.setDate(root.today()); root.mode = "apps"; } }
                            }
                            Repeater {
                                model: root.overview.topApps || []
                                RowLayout {
                                    id: topApp
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: Theme.gapS
                                    AppGlyph { source: root.appIcon(topApp.modelData.app) }
                                    C.Label { text: root.appLabel(topApp.modelData.app); Layout.preferredWidth: 120; elide: Text.ElideRight; font.pixelSize: Theme.small }
                                    AppBar {
                                        Layout.fillWidth: true
                                        active: topApp.modelData.active
                                        watching: topApp.modelData.watching
                                        maximum: (root.overview.topApps[0] || {}).total || 1
                                    }
                                    C.Caption { text: root.formatTime(topApp.modelData.total); font.family: Theme.mono; Layout.preferredWidth: 58; horizontalAlignment: Text.AlignRight }
                                }
                            }
                            C.Caption { visible: (root.overview.topApps || []).length === 0; text: "Apps appear here once you use them this week."; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                            Item { Layout.fillHeight: true }
                        }
                    }
                    C.Card {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 2
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 11
                            spacing: Theme.gapXs
                            C.Label { text: "Your rhythm"; font.pixelSize: Theme.small; font.weight: Font.Medium; color: Theme.muted; Layout.fillWidth: true }
                            Repeater {
                                model: [
                                    {label: "Usually starts", value: root.minuteClock(root.insights.typicalStart)},
                                    {label: "Usually ends", value: root.minuteClock(root.insights.typicalEnd)},
                                    {label: "Busiest hour", value: root.insights.busiestHour === null || root.insights.busiestHour === undefined ? "–" : String(root.insights.busiestHour).padStart(2, "0") + ":00"},
                                    {label: "Tracking since", value: root.overview.firstDay ? Qt.formatDate(new Date(root.overview.firstDay + "T12:00:00"), "d MMM yyyy") : "today"}
                                ]
                                RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    C.Caption { text: parent.modelData.label; Layout.fillWidth: true }
                                    C.Label { text: parent.modelData.value; font.family: Theme.mono; font.pixelSize: Theme.small }
                                }
                            }
                            Item { Layout.fillHeight: true }
                            C.Caption { text: "From the last 30 days"; color: Theme.disabled; Layout.fillWidth: true; elide: Text.ElideRight }
                        }
                    }
                }
            }

            // Day --------------------------------------------------------------
            RowLayout {
                anchors.fill: parent
                visible: root.mode === "day"
                spacing: Theme.gapM
                ColumnLayout {
                    Layout.preferredWidth: 236
                    Layout.maximumWidth: 236
                    Layout.fillHeight: true
                    spacing: Theme.gapS
                    RowLayout {
                        Layout.fillWidth: true
                        C.Button { glyph: "back"; implicitWidth: 30; flat: true; hint: "Previous month"; onClicked: root.shiftMonth(-1) }
                        C.Label { text: Qt.formatDate(root.selected, "MMMM yyyy"); font.weight: Font.DemiBold; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
                        C.Button { glyph: "chevron"; implicitWidth: 30; flat: true; hint: "Next month"; onClicked: root.shiftMonth(1) }
                    }
                    C.Card {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 232
                        border.width: monthGrid.activeFocus ? 1.5 : 0
                        border.color: Theme.accent
                        GridLayout {
                            id: monthGrid
                            anchors.fill: parent
                            anchors.margins: 8
                            columns: 7
                            rowSpacing: Theme.gapXs
                            columnSpacing: Theme.gapXs
                            activeFocusOnTab: true
                            Accessible.role: Accessible.Table
                            Accessible.name: "Calendar, " + Qt.formatDate(root.selected, "d MMMM yyyy") + " selected"
                            Keys.onPressed: event => {
                                const days = root.arrowDays(event.key, 1, 7);
                                if (days)
                                    root.stepDay(days, "");
                                else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown)
                                    root.shiftMonth(event.key === Qt.Key_PageUp ? -1 : 1);
                                else
                                    return;
                                event.accepted = true;
                            }
                            Repeater {
                                model: [0, 1, 2, 3, 4, 5, 6].map(index => Qt.locale().dayName(((root.weekStart + index) % 7) || 7, Locale.NarrowFormat))
                                C.Caption { required property string modelData; text: modelData; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true; Layout.preferredWidth: 1; font.family: Theme.mono }
                            }
                            Repeater {
                                model: root.monthCells
                                Rectangle {
                                    id: cell
                                    required property var modelData
                                    readonly property bool future: modelData.date > root.today()
                                    readonly property real active: (root.dayMap[modelData.date] || {}).active || 0
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    Layout.fillHeight: true
                                    radius: 6
                                    opacity: future ? 0.25 : modelData.current ? 1 : 0.4
                                    color: cellArea.containsMouse && !future ? Theme.hover : active >= 60 ? root.heatColor(active) : "transparent"
                                    border.width: modelData.date === root.selectedDate ? 2 : 0
                                    border.color: monthGrid.activeFocus ? Theme.accent : Theme.text
                                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                                    C.Label {
                                        anchors.centerIn: parent
                                        text: String(cell.modelData.number)
                                        font.pixelSize: Theme.small
                                        font.weight: cell.modelData.date === root.today() ? Font.Bold : Font.Normal
                                        color: root.heatLevel(cell.active) >= 3 ? Theme.surface : Theme.text
                                    }
                                    MouseArea { id: cellArea; anchors.fill: parent; hoverEnabled: true; enabled: !cell.future; onClicked: root.setDate(cell.modelData.date) }
                                    Accessible.role: Accessible.Button
                                    Accessible.name: modelData.date + ", " + root.formatTime(active)
                                }
                            }
                        }
                    }
                    C.Card {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: Theme.gapS
                            C.Label { text: root.weekly ? "Week total" : Qt.formatDate(root.selected, "dddd"); font.pixelSize: Theme.small; font.weight: Font.Medium; color: Theme.muted }
                            Repeater {
                                model: {
                                    const source = root.weekly ? (root.week.days || []).reduce((sum, entry) => ({active: sum.active + entry.active, watching: sum.watching + (entry.watching || 0), unlocked: sum.unlocked + entry.unlocked, focused: sum.focused + (entry.focused || 0)}), {active: 0, watching: 0, unlocked: 0, focused: 0}) : root.day;
                                    const rows = [
                                        {label: "Active", value: root.formatTime(source.active), color: Theme.accent},
                                        {label: "Watching", value: root.formatTime(source.watching), color: Theme.activityWatching},
                                        {label: "Idle", value: root.formatTime(Math.max(0, source.unlocked - source.active - (source.watching || 0))), color: Theme.activityIdle}
                                    ];
                                    if (source.focused >= 60) rows.push({label: "Focused", value: root.formatTime(source.focused), color: Theme.text});
                                    if (!root.weekly && root.day.firstActive) rows.push({label: "First – last", value: root.clockTime(root.day.firstActive) + "–" + root.clockTime(root.day.lastActive), color: "transparent"});
                                    return rows;
                                }
                                RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: Theme.gapS
                                    Swatch { color: parent.modelData.color }
                                    C.Caption { text: parent.modelData.label; Layout.fillWidth: true }
                                    C.Label { text: parent.modelData.value; font.family: Theme.mono; font.pixelSize: Theme.small }
                                }
                            }
                            Item { Layout.fillHeight: true }
                        }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Theme.gapS
                    RowLayout {
                        Layout.fillWidth: true
                        C.Button { glyph: "back"; flat: true; implicitWidth: 30; hint: root.weekly ? "Previous week" : "Previous day"; onClicked: root.shiftDate(root.weekly ? -7 : -1) }
                        C.Label {
                            text: root.weekly ? "Week of " + Qt.formatDate(new Date((root.week.start || root.selectedDate) + "T12:00:00"), "d MMM") : Qt.formatDate(root.selected, "ddd, d MMMM")
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            font.weight: Font.DemiBold
                        }
                        C.Button { glyph: "chevron"; flat: true; implicitWidth: 30; enabled: root.selectedDate < root.today(); hint: root.weekly ? "Next week" : "Next day"; onClicked: root.shiftDate(root.weekly ? 7 : 1) }
                        C.Segmented {
                            fill: false
                            Layout.preferredWidth: 130
                            segmentHeight: 32
                            model: [{key: false, text: "Day"}, {key: true, text: "Week"}]
                            current: root.weekly
                            onActivated: key => root.weekly = key
                        }
                    }
                    // Day timeline
                    C.Card {
                        visible: !root.weekly
                        Layout.fillWidth: true
                        Layout.preferredHeight: timelineColumn.implicitHeight + 22
                        ColumnLayout {
                            id: timelineColumn
                            anchors.fill: parent
                            anchors.margins: 11
                            spacing: Theme.gapXs
                            Item {
                                id: presence
                                Layout.fillWidth: true
                                Layout.preferredHeight: 10
                                Rectangle { anchors.fill: parent; radius: 3; color: Theme.raised }
                                Repeater {
                                    model: root.day.segments || []
                                    Rectangle {
                                        required property var modelData
                                        x: root.timeX(modelData.start, presence.width)
                                        width: Math.max(1, root.timeX(modelData.end, presence.width) - x)
                                        height: presence.height
                                        color: root.stateColor(modelData.state)
                                    }
                                }
                                // Focus sessions underline the time they covered.
                                Repeater {
                                    model: root.day.focus || []
                                    Rectangle {
                                        required property var modelData
                                        x: root.timeX(modelData.start, presence.width)
                                        y: presence.height - 2
                                        width: Math.max(2, root.timeX(modelData.end, presence.width) - x)
                                        height: 2
                                        color: Theme.text
                                    }
                                }
                            }
                            Item {
                                id: strip
                                Layout.fillWidth: true
                                Layout.preferredHeight: 26
                                Rectangle { anchors.fill: parent; radius: 4; color: Theme.raised; opacity: 0.6 }
                                Repeater {
                                    model: (root.day.segments || []).filter(segment => segment.app && segment.state !== "idle")
                                    Rectangle {
                                        required property var modelData
                                        x: root.timeX(modelData.start, strip.width)
                                        width: Math.max(2, root.timeX(modelData.end, strip.width) - x)
                                        height: strip.height
                                        radius: 2
                                        color: root.appColor(modelData.app)
                                        opacity: modelData.state === "watching" ? 0.6 : 1
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                const segment = parent.modelData;
                                                root.caption = root.appLabel(segment.app) + "  ·  " + root.clockTime(segment.start) + "–" + root.clockTime(segment.end) + "  ·  " + root.formatTime((segment.end - segment.start) / 1000) + " " + segment.state;
                                            }
                                        }
                                    }
                                }
                                C.Caption {
                                    anchors.centerIn: parent
                                    visible: (root.day.segments || []).length === 0
                                    text: root.day.legacy ? "Only the daily total was kept for this day" : "Nothing recorded"
                                    color: Theme.disabled
                                }
                            }
                            HourAxis { Layout.fillWidth: true }
                            Flow {
                                Layout.fillWidth: true
                                spacing: Theme.gapM
                                Repeater {
                                    model: root.dayRanking.concat((root.day.apps || []).length > 6 ? ["other"] : [])
                                    RowLayout {
                                        required property string modelData
                                        spacing: Theme.gapXs
                                        Swatch { color: root.appColor(parent.modelData === "other" ? "" : parent.modelData) }
                                        C.Caption { text: parent.modelData === "other" ? "Other" : root.appLabel(parent.modelData) }
                                    }
                                }
                                RowLayout {
                                    spacing: Theme.gapXs
                                    visible: root.day.watching >= 60
                                    Swatch { color: Theme.activityWatching }
                                    C.Caption { text: "Watching" }
                                }
                            }
                        }
                    }
                    C.Caption {
                        visible: !root.weekly
                        text: root.caption !== "" ? root.caption : "Select a block on the timeline for exact times."
                        color: root.caption !== "" ? Theme.muted : Theme.disabled
                        font.family: root.caption !== "" ? Theme.mono : Theme.font
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    C.Card {
                        visible: !root.weekly
                        Layout.fillWidth: true
                        Layout.preferredHeight: 74
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: Theme.gapXs
                            ColumnChart {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                values: (root.day.hours || []).map(slot => ({a: slot.active, b: slot.watching || 0}))
                                maximum: 3600
                                onPicked: index => {
                                    const slot = root.day.hours[index];
                                    root.caption = slot.label + "  ·  " + root.formatTime(slot.active) + " active  ·  " + root.formatTime(slot.watching || 0) + " watching";
                                }
                            }
                            HourAxis { Layout.fillWidth: true }
                        }
                    }
                    C.Card {
                        visible: !root.weekly
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ScrollView {
                            anchors.fill: parent
                            anchors.margins: 11
                            clip: true
                            contentWidth: availableWidth
                            ColumnLayout {
                                width: parent.width
                                spacing: Theme.gapS
                                Repeater {
                                    model: root.dayAppRows
                                    ColumnLayout {
                                        id: appLine
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: Theme.gapXs
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.gapS
                                            AppGlyph { source: root.appIcon(appLine.modelData.app); size: 14 }
                                            C.Label { text: root.appLabel(appLine.modelData.app); font.pixelSize: Theme.small; font.weight: Font.Medium; Layout.fillWidth: true; elide: Text.ElideRight }
                                            C.Caption {
                                                text: (appLine.modelData.windows.some(window => !window.startKnown || window.endReason === "gap") ? "partial  ·  " : "") + root.formatTime(appLine.modelData.total)
                                                font.family: Theme.mono
                                            }
                                        }
                                        Item {
                                            id: lane
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 8
                                            Rectangle { anchors.fill: parent; radius: 2; color: Theme.raised }
                                            Repeater {
                                                model: appLine.modelData.windows
                                                Rectangle {
                                                    required property var modelData
                                                    x: root.timeX(modelData.start, lane.width)
                                                    width: Math.max(2, root.timeX(modelData.end, lane.width) - x)
                                                    height: lane.height
                                                    radius: 2
                                                    color: Theme.activityWindow
                                                    opacity: 0.55
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        onClicked: {
                                                            const window = parent.modelData;
                                                            root.caption = root.appLabel(window.app) + "  ·  " + (window.startKnown ? "opened " : "already open at ") + root.clockTime(window.start) + "  ·  "
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
                                                    radius: 2
                                                    color: root.appColor(appLine.modelData.app)
                                                    opacity: modelData.state === "watching" ? 0.6 : 1
                                                }
                                            }
                                        }
                                    }
                                }
                                C.Caption {
                                    visible: root.dayAppRows.length === 0
                                    text: root.day.detailAvailable ? "No app windows recorded on this day." : "This day was recorded before app detail was kept; only its total remains."
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                    // Week view
                    C.Card {
                        visible: root.weekly
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ScrollView {
                            anchors.fill: parent
                            anchors.margins: 11
                            clip: true
                            contentWidth: availableWidth
                            ColumnLayout {
                                width: parent.width
                                spacing: Theme.gapXs
                                Repeater {
                                    model: root.week.days || []
                                    RowLayout {
                                        id: weekDay
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: Theme.gapS
                                        C.Label {
                                            text: Qt.formatDate(new Date(weekDay.modelData.date + "T12:00:00"), "ddd")
                                            font.family: Theme.mono
                                            font.pixelSize: Theme.caption
                                            font.weight: weekDay.modelData.date === root.selectedDate ? Font.Bold : Font.Normal
                                            color: weekDay.modelData.date === root.selectedDate ? Theme.text : Theme.muted
                                            Layout.preferredWidth: Math.ceil(Theme.caption * 2.6)
                                        }
                                        AppBar {
                                            Layout.fillWidth: true
                                            implicitHeight: 9
                                            active: weekDay.modelData.active
                                            watching: weekDay.modelData.watching || 0
                                            maximum: Math.max(14400, ...(root.week.days || []).map(entry => entry.active + (entry.watching || 0)))
                                        }
                                        C.Caption { text: root.formatTime(weekDay.modelData.active); font.family: Theme.mono; Layout.preferredWidth: Math.ceil(Theme.caption * 4.4); horizontalAlignment: Text.AlignRight }
                                    }
                                }
                                Item { Layout.preferredHeight: 8 }
                                RowLayout {
                                    visible: root.weekHasHours
                                    Layout.fillWidth: true
                                    spacing: Theme.gapXs
                                    Item { Layout.preferredWidth: Math.ceil(Theme.caption * 2.4); Layout.preferredHeight: 14 }
                                    Repeater {
                                        model: root.week.days || []
                                        C.Caption {
                                            required property var modelData
                                            text: Qt.formatDate(new Date(modelData.date + "T12:00:00"), "ddd").slice(0, 2)
                                            font.family: Theme.mono
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 1
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                    }
                                }
                                Repeater {
                                    model: root.weekHasHours ? root.weekHourLabels : []
                                    RowLayout {
                                        id: hourLine
                                        required property string modelData
                                        Layout.fillWidth: true
                                        spacing: Theme.gapXs
                                        C.Caption { text: hourLine.modelData.slice(0, 2); font.family: Theme.mono; color: Theme.disabled; Layout.preferredWidth: Math.ceil(Theme.caption * 2.4) }
                                        Repeater {
                                            model: root.week.days || []
                                            Rectangle {
                                                required property var modelData
                                                readonly property var slot: {
                                                    const slots = modelData.hours || [];
                                                    const label = hourLine.modelData;
                                                    return slots.find(entry => entry.label === label) || (label.endsWith("a") ? slots.find(entry => entry.label === label.slice(0, 2) + ":00") : null);
                                                }
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 1
                                                Layout.preferredHeight: 9
                                                radius: 2
                                                color: !slot ? "transparent" : slot.active >= 2400 ? Theme.accent : slot.active >= 1200 ? Theme.activityLevel3 : slot.active >= 60 ? Theme.activityLevel2 : (slot.watching || 0) >= 60 ? Theme.activityWatching : slot.unlocked >= 60 ? Theme.activityIdle : Theme.raised
                                                Behavior on color { ColorAnimation { duration: Theme.fast } }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Apps -------------------------------------------------------------
            ColumnLayout {
                anchors.fill: parent
                visible: root.mode === "apps" && root.appDetail === ""
                spacing: Theme.gapM
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.gapXs
                    C.Segmented {
                        fill: false
                        Layout.preferredWidth: 220
                        model: [{key: "day", text: "Day"}, {key: "week", text: "Week"}, {key: "month", text: "Month"}]
                        current: root.appsRange
                        onActivated: key => root.appsRange = key
                    }
                    C.Button { glyph: "back"; flat: true; implicitWidth: 30; Layout.leftMargin: 8; hint: "Earlier"; onClicked: root.shiftPeriod(-1) }
                    C.Label { text: root.periodLabel(); font.weight: Font.DemiBold; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
                    C.Button { glyph: "chevron"; flat: true; implicitWidth: 30; enabled: root.appsData.end < root.today(); hint: "Later"; onClicked: root.shiftPeriod(1) }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.gapS
                    C.Label { text: root.formatTime(root.appsData.total); font.family: Theme.mono; font.pixelSize: Theme.body + 4; font.weight: Font.DemiBold }
                    C.Caption { text: "in apps" + (root.delta(root.appsData.total, root.appsData.previousTotal) ? "  ·  " + root.delta(root.appsData.total, root.appsData.previousTotal) + " vs previous " + root.appsRange : ""); Layout.fillWidth: true }
                    Swatch { color: Theme.accent }
                    C.Caption { text: "Active" }
                    Swatch { color: Theme.activityWatching; Layout.leftMargin: 6 }
                    C.Caption { text: "Watching" }
                }
                C.Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    ScrollView {
                        id: appsScroll
                        anchors.fill: parent
                        anchors.margins: 6
                        clip: true
                        contentWidth: availableWidth
                        ColumnLayout {
                            width: parent.width
                            spacing: 2
                            Repeater {
                                id: appRows
                                model: root.appsData.apps || []
                                Rectangle {
                                    id: appRow
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: Theme.radiusSmall
                                    color: rowArea.containsMouse || activeFocus ? Theme.hover : "transparent"
                                    border.width: activeFocus ? 1.5 : 0
                                    border.color: Theme.accent
                                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                                    activeFocusOnTab: true
                                    onActiveFocusChanged: if (activeFocus) {
                                        const view = appsScroll.contentItem;
                                        if (y < view.contentY)
                                            view.contentY = y;
                                        else if (y + height > view.contentY + view.height)
                                            view.contentY = y + height - view.height;
                                    }
                                    Keys.onPressed: event => {
                                        const next = event.key === Qt.Key_Down ? appRows.itemAt(index + 1) : event.key === Qt.Key_Up ? appRows.itemAt(index - 1) : null;
                                        if (next)
                                            next.forceActiveFocus(Qt.TabFocusReason);
                                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
                                            root.openApp(modelData.app);
                                        else if (event.key !== Qt.Key_Down && event.key !== Qt.Key_Up)
                                            return;
                                        event.accepted = true;
                                    }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 10
                                        spacing: Theme.gapS
                                        C.Caption { text: String(appRow.index + 1); font.family: Theme.mono; color: Theme.disabled; Layout.preferredWidth: 16; horizontalAlignment: Text.AlignRight }
                                        AppGlyph { source: root.appIcon(appRow.modelData.app); size: 18 }
                                        C.Label { text: root.appLabel(appRow.modelData.app); Layout.preferredWidth: 150; elide: Text.ElideRight }
                                        AppBar {
                                            Layout.fillWidth: true
                                            active: appRow.modelData.active
                                            watching: appRow.modelData.watching
                                            maximum: ((root.appsData.apps || [])[0] || {}).total || 1
                                        }
                                        C.Label { text: root.formatTime(appRow.modelData.total); font.family: Theme.mono; font.pixelSize: Theme.small; Layout.preferredWidth: 62; horizontalAlignment: Text.AlignRight }
                                        C.Caption { text: Math.round(appRow.modelData.share * 100) + "%"; font.family: Theme.mono; color: Theme.disabled; Layout.preferredWidth: 34; horizontalAlignment: Text.AlignRight }
                                        C.Caption {
                                            text: appRow.modelData.previous >= 60 ? root.delta(appRow.modelData.total, appRow.modelData.previous) : "new"
                                            font.family: Theme.mono
                                            Layout.preferredWidth: 58
                                            horizontalAlignment: Text.AlignRight
                                        }
                                        C.Icon { name: "chevron"; size: 12; color: Theme.disabled }
                                    }
                                    MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openApp(appRow.modelData.app) }
                                    Accessible.role: Accessible.Button
                                    Accessible.name: root.appLabel(modelData.app) + ", " + root.formatTime(modelData.total)
                                }
                            }
                            C.EmptyState {
                                visible: (root.appsData.apps || []).length === 0
                                Layout.fillWidth: true
                                Layout.topMargin: 40
                                glyph: "activity"
                                title: "No app time in this " + root.appsRange
                                description: "Focused apps are counted while you are active or watching."
                            }
                        }
                    }
                }
            }

            // App detail -------------------------------------------------------
            ColumnLayout {
                anchors.fill: parent
                visible: root.mode === "apps" && root.appDetail !== ""
                spacing: Theme.gapM
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.gapS
                    C.Button { glyph: "back"; flat: true; implicitWidth: 30; hint: "All apps"; onClicked: root.appDetail = "" }
                    AppGlyph { source: root.appIcon(root.appDetail); size: 22 }
                    C.Label { text: root.appLabel(root.appDetail); font.pixelSize: Theme.body + 2; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                    C.Caption { text: root.appDetail; font.family: Theme.mono; color: Theme.disabled; elide: Text.ElideMiddle; Layout.maximumWidth: 220 }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.gapS
                    C.Stat { label: "All time"; value: root.formatTime(root.appData.total); note: root.formatTime(root.appData.watching) + " watching" }
                    C.Stat { label: "Last 30 days"; value: root.formatTime((root.appData.days || []).reduce((sum, entry) => sum + entry.total, 0)); note: (root.appData.days || []).filter(entry => entry.total >= 60).length + " days used" }
                    C.Stat { label: "Per day used"; value: root.formatTime(root.appData.averagePerDay); note: root.appData.daysUsed + " days in total" }
                    C.Stat { label: "First seen"; value: root.appData.firstDay ? Qt.formatDate(new Date(root.appData.firstDay + "T12:00:00"), "d MMM") : "–"; note: root.appData.firstDay ? Qt.formatDate(new Date(root.appData.firstDay + "T12:00:00"), "yyyy") : "" }
                }
                C.Label { text: "Last 30 days"; font.pixelSize: Theme.small; font.weight: Font.Medium; color: Theme.muted }
                C.Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 3
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 11
                        spacing: Theme.gapXs
                        ColumnChart {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            values: (root.appData.days || []).map(entry => ({a: entry.total}))
                            maximum: Math.max(3600, ...(root.appData.days || []).map(entry => entry.total))
                            onPicked: index => {
                                selectedIndex = index;
                                const entry = root.appData.days[index];
                                monthCaption.text = Qt.formatDate(new Date(entry.date + "T12:00:00"), "ddd d MMM") + "  ·  " + root.formatTime(entry.total);
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            C.Caption { text: (root.appData.days || []).length ? Qt.formatDate(new Date(root.appData.days[0].date + "T12:00:00"), "d MMM") : ""; font.family: Theme.mono; color: Theme.disabled }
                            C.Caption { id: monthCaption; text: "Select a day"; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; font.family: Theme.mono }
                            C.Caption { text: "Today"; font.family: Theme.mono; color: Theme.disabled }
                        }
                    }
                }
                C.Label { text: "When you use it"; font.pixelSize: Theme.small; font.weight: Font.Medium; color: Theme.muted }
                C.Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 2
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 11
                        spacing: Theme.gapXs
                        ColumnChart {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            values: (root.appData.hours || []).map(seconds => ({a: seconds}))
                            maximum: Math.max(60, ...(root.appData.hours || []))
                            onPicked: index => {
                                selectedIndex = index;
                                hourCaption.text = String(index).padStart(2, "0") + ":00  ·  " + root.formatTime(root.appData.hours[index]) + " over 30 days";
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            HourAxis { Layout.fillWidth: true }
                        }
                        C.Caption { id: hourCaption; text: "Hour of day, last 30 days"; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; font.family: Theme.mono }
                    }
                }
            }
        }
        RowLayout {
            visible: root.tracking !== "ask"
            Layout.fillWidth: true
            spacing: Theme.gapM
            C.Caption { text: root.width < 520 ? "Private · local only" : "Private · local only · kept until you clear it"; color: Theme.disabled; Layout.fillWidth: true }
            C.HoldButton {
                id: clearHistoryButton
                text: "Clear history"
                glyph: "close"
                destructive: true
                // Measured: an eliding label reports its constrained width, not its natural one.
                implicitWidth: Math.max(150, Math.ceil(clearMetrics.advanceWidth) + 20 + 14 + leftPadding + rightPadding + 8)
                TextMetrics {
                    id: clearMetrics
                    text: clearHistoryButton.text
                    font.family: Theme.font
                    font.pixelSize: Theme.body
                    font.weight: Font.DemiBold
                }
                implicitHeight: 40
                padding: 7
                topPadding: 5
                bottomPadding: 9
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
            else shiftDate(weekly ? step * 7 : step);
            event.accepted = true;
        } else if (event.key === Qt.Key_Home && mode !== "overview") { setDate(today()); event.accepted = true; }
    }
}
