pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../core/day.js" as DayText
import "../core/filters.js" as Filters
import "../core/logbook.js" as Book
import "../services"
import "../components" as C

// The Logbook: the island's third stage. Every view of the work orders, the detail sheet and the keys of
// docs 15 section 12. It sits inside the hub's shape; the hub fades its own plates out as this fades in.
FocusScope {
    id: book
    property bool opening: false
    property real now: Date.now()
    // The current view: today, ahead, intake, site, tag, filter, search or cleared, with a site row, a tag name or a
    // filter row as its argument.
    property string kind: "today"
    property var argument: null
    property bool board: false
    // Orders the search or a filter query selected.
    property var found: []
    property string problem: ""
    // The row the cursor is on, by id, and the rows marked with Shift.
    property int cursorId: -1
    property var marked: ({})
    // What the prompt row is asking: "", "due", "site", "tag" or "ask" (clear open sub-orders too?).
    property string prompt: ""
    property var asking: null
    property bool goPending: false
    readonly property bool typing: capture.activeFocus || searchField.activeFocus || promptField.activeFocus || sheet.editing || (!!routinesPage && routinesPage.typing)
    signal dismissed()

    // The routines view while it is shown (a plain var: a Loader's item is only known as an object).
    readonly property var routinesPage: routinesView.item
    readonly property var source: kind === "filter" || kind === "search" ? found : Day.orders
    readonly property var groups: Book.view(kind, argument, source, now)
    readonly property var flat: Book.flat(groups)
    readonly property int cursor: flat.findIndex(order => order.id === cursorId)
    readonly property var current: cursor >= 0 ? flat[cursor] : null
    readonly property var counts: Book.counts(Day.orders, now)
    readonly property var parsed: DayText.capture(capture.text, now, {sites: Day.sites.map(site => site.name)})
    readonly property var rows: {
        const list = [];
        groups.forEach(group => {
            if (group.label)
                list.push({header: true, label: group.label, count: group.orders.length, order: null});
            group.orders.forEach(order => list.push({header: false, label: "", count: 0, order: order}));
        });
        return list;
    }
    readonly property var navigation: {
        const list = [{label: "Intake", kind: "intake", argument: null, count: counts.intake}, {label: "Today", kind: "today", argument: null, count: counts.today},
                      {label: "Ahead", kind: "ahead", argument: null, count: 0}];
        if (Day.filters.length)
            list.push({header: true, label: "Filters"});
        Day.filters.forEach(filter => list.push({label: filter.name, kind: "filter", argument: filter, count: 0}));
        if (Day.sites.length)
            list.push({header: true, label: "Sites"});
        Day.sites.filter(site => !site.archived).forEach(site => list.push({label: site.name, kind: "site", argument: site, count: 0,
                                                                          note: Book.progress(Day.orders, site.id, now)}));
        if (Day.tags.length)
            list.push({header: true, label: "Tags"});
        Day.tags.forEach(tag => list.push({label: "@" + tag.name, kind: "tag", argument: tag.name, count: tag.count}));
        list.push({header: true, label: ""}, {label: "Routines", kind: "routines", argument: null, count: Day.routinesDue.filter(routine => routine.checkedToday).length + "/" + Day.routinesDue.length}, {label: "Shift report", kind: "report", argument: null, count: 0}, {label: "Cleared", kind: "cleared", argument: null, count: 0});
        return list;
    }
    readonly property string title: {
        switch (kind) {
        case "today":
            return "Today · " + Qt.formatDateTime(new Date(now), "ddd d MMM");
        case "ahead":
            return "Ahead · the next 7 days";
        case "intake":
            return "Intake · no site yet";
        case "site":
            return argument ? argument.name : "";
        case "tag":
            return "@" + argument;
        case "filter":
            return (argument ? argument.name : "") + (argument ? " · " + argument.query : "");
        case "search":
            return "Search · " + searchField.text;
        case "report":
            return "Shift report";
        case "routines":
            return "Instrument checks";
        }
        return "Cleared";
    }

    // Five segments filled by the share of the day's target cleared.
    function meter(m) {
        const lit = m.target > 0 ? Math.floor(Math.min(m.cleared, m.target) * 5 / m.target) : 0;
        return "▮".repeat(lit) + "▯".repeat(5 - lit);
    }
    function open(view, argument) {
        book.argument = argument === undefined ? null : argument;
        kind = view;
        board = false;
        problem = "";
        marked = ({});
        if (view === "filter")
            runFilter();
        // The bindings are current already, so the first row is known now; a later callLater would land on a key press.
        selectFirst();
    }
    function runFilter() {
        if (kind !== "filter" || !argument)
            return;
        const result = Filters.run(argument.query, Day.orders, now);
        problem = result.error || "";
        found = result.orders || [];
    }
    function selectFirst() {
        cursorId = flat.length ? flat[0].id : -1;
    }
    function go(delta, extend) {
        if (!flat.length)
            return;
        const next = Math.max(0, Math.min(flat.length - 1, (cursor < 0 ? (delta > 0 ? -1 : flat.length) : cursor) + delta));
        if (extend) {
            const copy = Object.assign({}, marked);
            copy[flat[cursor < 0 ? next : cursor].id] = true;
            copy[flat[next].id] = true;
            marked = copy;
        } else {
            marked = ({});
        }
        cursorId = flat[next].id;
    }
    // The orders an action applies to: the marked ones, or the one under the cursor.
    function targets() {
        const ids = Object.keys(marked).map(Number);
        const list = ids.length ? flat.filter(order => marked[order.id]) : current ? [current] : [];
        return list;
    }
    function toggle(order) {
        if (order.doneAt) {
            Day.undone(order.id);
        } else {
            Day.complete(order.id, undefined, (result, error) => book.completed(order, result, error));
        }
    }
    // A named function: qmllint skips a file whose callbacks declare constants (as in DayHub.qml).
    function completed(order, result, error) {
        if (error || result.ask === 0)
            return;
        asking = order;
        prompt = "ask";
        promptField.text = "";
    }
    function answer(clearThem) {
        const order = asking;
        asking = null;
        prompt = "";
        book.release();
        if (order)
            Day.complete(order.id, clearThem);
    }
    function clearSelected() {
        targets().forEach(order => toggle(order));
    }
    function setPriority(value) {
        targets().forEach(order => Day.update(order.id, {priority: value}));
    }
    function remove() {
        const list = targets();
        const next = flat.find((order, index) => index > cursor && !list.some(item => item.id === order.id)) || flat[Math.max(0, cursor - 1)];
        // The helper removes one order per call; each is its own step in the history, so Undo brings back the last.
        list.forEach(order => Day.remove(order.id, (removed, error) => book.removed(removed, error)));
        marked = ({});
        cursorId = next && !list.some(item => item.id === next.id) ? next.id : -1;
    }
    function removed(order, error) {
        if (!error)
            ShellState.message("Work order deleted · " + order.text, "info", {label: "Undo", run: () => Day.undo()});
    }
    function reorder(delta) {
        if (!current || current.doneAt)
            return;
        const ids = Day.todos.map(order => order.id);
        // The neighbour in this list, not in the whole set of orders.
        const same = flat.filter(order => !order.doneAt && ids.indexOf(order.id) >= 0);
        const other = same[same.findIndex(order => order.id === current.id) + delta];
        if (!other || ids.indexOf(current.id) < 0)
            return;
        ids.splice(ids.indexOf(current.id), 1);
        ids.splice(ids.indexOf(other.id) + (delta > 0 ? 1 : 0), 0, current.id);
        Day.reorder(ids);
    }
    // Alt+Up/Down move a block by 15 minutes, Alt+Left/Right by a day (also by drag in Ahead).
    function moveCurrent(minutes, days) {
        if (!current || current.dueAt === null || current.dueAt === undefined)
            return;
        Day.update(current.id, {dueAt: Book.moveBlock(current.dueAt, minutes, days)});
    }
    function dragBlock(id, fromColumn, dx, columnWidth) {
        const order = Day.orders.find(item => item.id === id);
        const to = Book.dropColumn(fromColumn, dx, columnWidth, 7);
        if (order && to !== fromColumn)
            Day.update(id, {dueAt: Book.moveBlock(order.dueAt, 0, to - fromColumn)});
    }
    // Starts Quiet on the order under the cursor (25 minutes, the minutes are logged on it), or ends the Quiet that runs.
    function quiet() {
        if (Focus.active) {
            Focus.end(true);
            return;
        }
        if (current)
            Focus.start(25, current.id, current.text);
    }
    // Shift+Right in Ahead moves an order to the next day (Shift+Left to the one before), keeping its time.
    function shiftDay(delta) {
        if (kind !== "ahead" || !current || current.dueAt === null)
            return;
        const date = new Date(current.dueAt);
        date.setDate(date.getDate() + delta);
        Day.update(current.id, {dueAt: date.getTime()});
    }
    function startPrompt(mode, placeholder) {
        if (!current)
            return;
        prompt = mode;
        promptField.text = "";
        promptField.placeholderText = placeholder;
        promptField.forceActiveFocus();
    }
    function endPrompt() {
        prompt = "";
        asking = null;
        promptField.text = "";
        book.release();
    }
    // The prompt's suggestions for # and @: names containing what is typed.
    readonly property var suggestions: {
        const text = promptField.text.replace(/^[#@]/, "").toLowerCase();
        const names = prompt === "site" ? Day.sites.map(site => site.name) : prompt === "tag" ? Day.tags.map(tag => tag.name) : [];
        return names.filter(name => name.toLowerCase().indexOf(text) >= 0).slice(0, 5);
    }
    function submitPrompt() {
        const text = promptField.text.trim();
        const targetsNow = targets();
        if (prompt === "ask") {
            answer(text.toLowerCase() === "y");
            return;
        }
        if (!text || !targetsNow.length)
            return endPrompt();
        if (prompt === "due") {
            const result = DayText.capture("x " + text, Date.now(), {});
            if (!result || result.dueAt === null) {
                ShellState.message(result && result.error ? result.error : "That is not a date.", "error");
                return;
            }
            targetsNow.forEach(order => Day.update(order.id, {dueAt: result.dueAt, allDay: result.allDay}));
        } else if (prompt === "site") {
            const name = (suggestions[0] || text.replace(/^#/, ""));
            const parts = name.split("/");
            targetsNow.forEach(order => Day.update(order.id, parts.length > 1 ? {site: parts[0], section: parts[1]} : {site: parts[0]}));
        } else if (prompt === "tag") {
            const name = (suggestions[0] || text.replace(/^@/, ""));
            targetsNow.forEach(order => Day.update(order.id, {tags: (order.tags.indexOf(name) >= 0 ? order.tags : order.tags.concat([name]))}));
        }
        endPrompt();
    }
    function submitCapture() {
        const order = parsed;
        if (!order || order.error)
            return;
        const text = capture.text;
        capture.text = "";
        const fields = {kind: "todo", text: order.text, site: order.site, section: order.section, tags: order.tags, priority: order.priority,
                        dueAt: order.dueAt, allDay: order.allDay, deadlineAt: order.deadlineAt, durationMin: order.durationMin,
                        rule: order.rule, ruleFromDone: order.ruleFromDone};
        if (order.alerts.length)
            fields.alerts = order.alerts;
        Day.addOrder(fields, (result, error) => book.added(error, text));
    }
    function added(error, text) {
        if (!error)
            return;
        capture.text = text;
        ShellState.message(error.message, "error");
    }
    function doSearch() {
        const text = searchField.text.trim();
        if (!text) {
            found = [];
            return;
        }
        Day.search(text, (result, error) => book.searched(result, error));
    }
    function searched(result, error) {
        found = error ? [] : result;
        problem = error ? error.message : "";
        if (kind === "search")
            Qt.callLater(selectFirst);
    }
    function startSearch() {
        kind = "search";
        argument = null;
        found = [];
        searchField.text = "";
        searchField.forceActiveFocus();
    }
    function openSheet() {
        if (!current)
            return;
        sheet.shown = true;
        sheet.focusTitle();
    }
    function stepBack() {
        if (prompt) {
            endPrompt();
        } else if (sheet.shown) {
            sheet.shown = false;
            book.release();
        } else if (typing) {
            if (searchField.activeFocus && !searchField.text)
                open("today");
            book.release();
        } else if (marked && Object.keys(marked).length) {
            marked = ({});
        } else {
            dismissed();
        }
    }
    // A focus scope hands focus to the field that last had it, so each field is let go first: the keys of the views
    // only work while none of them is being typed in.
    function release() {
        if (routinesPage)
            routinesPage.release();
        capture.focus = false;
        searchField.focus = false;
        promptField.focus = false;
        sheet.release();
        book.forceActiveFocus();
    }
    function focusNow() {
        release();
    }

    onOpeningChanged: {
        Day.logbook = opening;
        if (opening) {
            now = Date.now();
            open("today");
        } else {
            sheet.shown = false;
            prompt = "";
        }
    }
    Connections {
        target: Day
        function onOrdersChanged() {
            book.now = Date.now();
            book.runFilter();
            if (book.kind === "search")
                book.doSearch();
            // The cursor stays on its order when it can, else moves to the nearest row.
            if (book.cursor < 0 && book.flat.length)
                book.cursorId = book.flat[Math.min(book.flat.length - 1, Math.max(0, book.lastCursor))].id;
        }
    }
    property int lastCursor: 0
    onCursorChanged: if (cursor >= 0) lastCursor = cursor
    Timer {
        interval: 800
        running: book.goPending
        onTriggered: book.goPending = false
    }

    Keys.onEscapePressed: book.stepBack()
    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier, shift = event.modifiers & Qt.ShiftModifier;
        if (event.key === Qt.Key_Z && ctrl) {
            if (shift)
                Day.redo();
            else
                Day.undo();
            event.accepted = true;
            return;
        }
        if (book.typing)
            return;
        event.accepted = true;
        if (book.kind === "routines" && !book.goPending && event.key !== Qt.Key_G && event.key !== Qt.Key_Slash) {
            if (routinesPage && routinesPage.handle(event))
                return;
            event.accepted = false;
            return;
        }
        // The report has no rows: only the go-to and search keys apply there.
        if (book.kind === "report" && !book.goPending && event.key !== Qt.Key_G && event.key !== Qt.Key_Slash) {
            event.accepted = false;
            return;
        }
        if (book.prompt === "ask") {
            if (event.key === Qt.Key_Y || event.key === Qt.Key_N)
                book.answer(event.key === Qt.Key_Y);
            else if (event.key === Qt.Key_Escape)
                book.endPrompt();
            return;
        }
        if (book.goPending) {
            book.goPending = false;
            const view = {[Qt.Key_T]: "today", [Qt.Key_A]: "ahead", [Qt.Key_I]: "intake", [Qt.Key_C]: "cleared", [Qt.Key_S]: "report", [Qt.Key_R]: "routines"}[event.key];
            if (view)
                book.open(view);
            return;
        }
        if ((event.modifiers & Qt.AltModifier) && [Qt.Key_Up, Qt.Key_Down, Qt.Key_Left, Qt.Key_Right].indexOf(event.key) >= 0) {
            book.moveCurrent(event.key === Qt.Key_Up ? -15 : event.key === Qt.Key_Down ? 15 : 0, event.key === Qt.Key_Left ? -1 : event.key === Qt.Key_Right ? 1 : 0);
        } else if (event.key === Qt.Key_F) {
            book.quiet();
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
            const delta = event.key === Qt.Key_Up ? -1 : 1;
            if (ctrl)
                book.reorder(delta);
            else
                book.go(delta, shift);
        } else if (event.key === Qt.Key_Right && shift) {
            book.shiftDay(1);
        } else if (event.key === Qt.Key_Left && shift) {
            book.shiftDay(-1);
        } else if (event.key === Qt.Key_Space) {
            book.clearSelected();
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_E) {
            book.openSheet();
        } else if (event.key === Qt.Key_Delete) {
            book.remove();
        } else if (event.key === Qt.Key_Q || event.key === Qt.Key_Plus) {
            capture.forceActiveFocus();
        } else if (event.key === Qt.Key_Slash) {
            book.startSearch();
        } else if (event.key === Qt.Key_G) {
            book.goPending = true;
        } else if (event.key === Qt.Key_D) {
            book.startPrompt("due", "due: tomorrow, fri 10:30, in 3 days");
        } else if (event.key === Qt.Key_NumberSign) {
            book.startPrompt("site", "move to site: name or name/section");
        } else if (event.key === Qt.Key_At) {
            book.startPrompt("tag", "add tag");
        } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_4) {
            book.setPriority(event.key - Qt.Key_0);
        } else if (event.key === Qt.Key_B) {
            if (book.kind === "site")
                book.board = !book.board;
        } else {
            event.accepted = false;
        }
    }

    // Sidebar: the views and lists, each with its count.
    Rectangle {
        id: side
        width: 184
        height: parent.height
        color: Theme.panel
        border.width: 1
        border.color: Theme.border
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.gapS
            spacing: 2
            C.StationText {
                text: "Logbook"
                Layout.leftMargin: 6
                Layout.bottomMargin: 4
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: book.navigation
                interactive: contentHeight > height
                delegate: Item {
                    id: nav
                    required property var modelData
                    readonly property bool active: !modelData.header && book.kind === modelData.kind && (modelData.kind !== "site" && modelData.kind !== "tag" && modelData.kind !== "filter" || book.argument === modelData.argument)
                    width: ListView.view.width
                    height: modelData.header ? 26 : 28
                    Accessible.role: modelData.header ? Accessible.StaticText : Accessible.Button
                    Accessible.name: modelData.label
                    C.StationText {
                        visible: !!nav.modelData.header
                        text: nav.modelData.label
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        x: 6
                    }
                    Rectangle {
                        visible: !nav.modelData.header
                        anchors.fill: parent
                        radius: 4
                        color: nav.active ? Theme.selection : navHover.hovered ? Theme.hover : "transparent"
                        HoverHandler {
                            id: navHover
                        }
                        TapHandler {
                            onTapped: book.open(nav.modelData.kind, nav.modelData.argument)
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            C.Label {
                                Layout.fillWidth: true
                                text: nav.modelData.label
                                font.pixelSize: Theme.label
                                color: nav.active ? Theme.text : Theme.muted
                            }
                            C.Label {
                                visible: (nav.modelData.count || 0) > 0
                                text: nav.modelData.count || 0
                                font.family: Theme.instrument
                                font.pixelSize: Theme.small
                                color: Theme.muted
                            }
                            C.Label {
                                visible: nav.modelData.note !== undefined && nav.modelData.note !== null
                                text: nav.modelData.note + "%"
                                font.family: Theme.instrument
                                font.pixelSize: Theme.small
                                color: Theme.muted
                            }
                        }
                    }
                }
            }
        }
    }

    // The chosen view.
    Item {
        id: main
        anchors.left: side.right
        anchors.right: parent.right
        height: parent.height
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.gapM
            spacing: Theme.gapS
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapS
                C.StationText {
                    text: book.title
                    color: Theme.text
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                // The day's target as a stamped reading; nothing of it shows when the daily target is 0.
                C.StationText {
                    objectName: "targetReading"
                    visible: Day.targets
                    readonly property var m: Day.momentum
                    color: m && m.onTarget ? Theme.accent : Theme.muted
                    text: m ? (m.dayOff ? "DAY OFF" : (m.onTarget ? "ON TARGET " : "TARGET ") + m.cleared + "/" + m.target + " " + book.meter(m)
                               + "  ·  " + m.daysOnTarget + " d on target  ·  week " + m.weekCleared + "/" + m.weekTarget) : ""
                    Accessible.name: "Daily target"
                }
                C.Field {
                    id: searchField
                    visible: book.kind === "search"
                    Layout.preferredWidth: 220
                    implicitHeight: 28
                    font.pixelSize: Theme.label
                    placeholderText: "search titles, notes, sites, tags"
                    Keys.onEscapePressed: book.stepBack()
                    onTextChanged: book.doSearch()
                    Keys.onDownPressed: book.stepBack()
                    Keys.onReturnPressed: book.stepBack()
                    Keys.onEnterPressed: book.stepBack()
                }
                C.StationKey {
                    text: "Search /"
                    Layout.fillWidth: false
                    implicitWidth: 76
                    implicitHeight: 26
                    visible: book.kind !== "search"
                    onClicked: book.startSearch()
                }
                C.StationKey {
                    visible: book.kind === "site"
                    text: book.board ? "List" : "Board"
                    lit: book.board
                    Layout.fillWidth: false
                    implicitWidth: 60
                    implicitHeight: 26
                    onClicked: book.board = !book.board
                }
            }
            // Ahead: the seven days as a strip, each with its count and its blocks as bars at their time of day; a bar
            // can be dragged to another day.
            Row {
                id: strip
                visible: book.kind === "ahead"
                Layout.fillWidth: true
                spacing: Theme.gapXs
                readonly property real columnWidth: (main.width - 2 * Theme.gapM - 6 * Theme.gapXs) / 7
                readonly property var bars: book.kind === "ahead" ? Book.blockBars(book.groups) : []
                Repeater {
                    model: book.kind === "ahead" ? book.groups : []
                    Rectangle {
                        id: day
                        required property var modelData
                        required property int index
                        width: strip.columnWidth
                        height: 64
                        radius: 4
                        color: Theme.panel
                        border.width: 1
                        border.color: Theme.border
                        Column {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 4
                            C.StationText {
                                text: day.modelData.label
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            C.Label {
                                text: day.modelData.orders.length
                                font.family: Theme.instrument
                                anchors.horizontalCenter: parent.horizontalCenter
                                color: day.modelData.orders.length ? Theme.text : Theme.disabled
                            }
                        }
                        // Blocks: x is the time of day, the width the duration (at least 4 px).
                        Repeater {
                            model: strip.bars[day.index] || []
                            Rectangle {
                                id: bar
                                required property var modelData
                                required property int index
                                x: 3 + (day.width - 6) * modelData.from / 1440
                                y: 42 + bar.index * 5
                                width: Math.max(4, (day.width - 6) * modelData.minutes / 1440)
                                height: 4
                                radius: 1
                                color: Theme.accent2
                                visible: bar.index < 4
                                Accessible.name: "Block " + modelData.text + ", " + modelData.minutes + " minutes"
                                DragHandler {
                                    id: drag
                                    yAxis.enabled: false
                                    onActiveChanged: {
                                        if (!active) {
                                            book.dragBlock(bar.modelData.id, day.index, drag.translation.x, strip.columnWidth + Theme.gapXs);
                                            bar.x = 3 + (day.width - 6) * bar.modelData.from / 1440;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            C.Label {
                visible: book.problem !== ""
                text: book.problem
                color: Theme.warning
                font.pixelSize: Theme.small
                Layout.fillWidth: true
            }
            // List view.
            ListView {
                id: list
                visible: !book.board && book.kind !== "report" && book.kind !== "routines"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: book.board ? [] : book.rows
                spacing: 1
                Accessible.name: "Work orders"
                delegate: Item {
                    id: slot
                    required property var modelData
                    width: ListView.view.width
                    height: modelData.header ? 26 : 30
                    C.StationText {
                        visible: slot.modelData.header
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        x: 4
                        text: slot.modelData.label + (slot.modelData.header && slot.modelData.count ? " · " + slot.modelData.count : "")
                    }
                    Loader {
                        anchors.fill: parent
                        active: !slot.modelData.header
                        sourceComponent: LogbookRow {
                            order: slot.modelData.order
                            now: book.now
                            current: slot.modelData.order.id === book.cursorId
                            marked: !!book.marked[slot.modelData.order.id]
                            listFocus: !book.typing || book.activeFocus
                            onClicked: extend => {
                                if (extend) {
                                    const copy = Object.assign({}, book.marked);
                                    copy[book.cursorId] = true;
                                    copy[slot.modelData.order.id] = true;
                                    book.marked = copy;
                                } else {
                                    book.marked = ({});
                                }
                                book.cursorId = slot.modelData.order.id;
                                book.release();
                            }
                            onDoubleClicked: {
                                book.cursorId = slot.modelData.order.id;
                                book.openSheet();
                            }
                            onToggled: book.toggle(slot.modelData.order)
                        }
                    }
                }
                ScrollBar.vertical: C.ScrollBar {
                }
                onCountChanged: positionViewAtIndex(Math.max(0, book.rows.findIndex(row => !row.header && row.order.id === book.cursorId)), ListView.Contain)
            }
            Loader {
                active: book.kind === "report"
                visible: active
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: LogbookReport {
                    now: book.now
                    onChanged: Day.refresh()
                }
            }
            Loader {
                id: routinesView
                active: book.kind === "routines"
                visible: active
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: LogbookRoutines {
                    now: book.now
                }
            }
            // Board view of a site: the sections as columns.
            Row {
                id: boardRow
                visible: book.board
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.gapS
                Repeater {
                    model: book.board ? book.groups : []
                    Rectangle {
                        id: column
                        required property var modelData
                        width: Math.max(150, (boardRow.width - (book.groups.length - 1) * Theme.gapS) / Math.max(1, book.groups.length))
                        height: boardRow.height
                        radius: 6
                        color: Theme.panel
                        border.width: 1
                        border.color: Theme.border
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 2
                            C.StationText {
                                text: column.modelData.label + " · " + column.modelData.orders.length
                            }
                            Repeater {
                                model: column.modelData.orders
                                LogbookRow {
                                    id: card
                                    required property var modelData
                                    Layout.fillWidth: true
                                    order: modelData
                                    now: book.now
                                    current: modelData.id === book.cursorId
                                    marked: !!book.marked[modelData.id]
                                    listFocus: true
                                    onClicked: {
                                        book.cursorId = card.modelData.id;
                                        book.release();
                                    }
                                    onDoubleClicked: book.openSheet()
                                    onToggled: book.toggle(card.modelData)
                                }
                            }
                            Item {
                                Layout.fillHeight: true
                            }
                        }
                    }
                }
            }
            C.Label {
                visible: book.rows.length === 0 && !book.board && book.kind !== "report" && book.kind !== "routines"
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                horizontalAlignment: Text.AlignHCenter
                text: book.kind === "search" && !searchField.text ? "Type to search." : "Nothing here. The station is calm."
                color: Theme.muted
            }
            // The prompt for D, # and @, and the question about sub-orders.
            RowLayout {
                visible: book.prompt !== ""
                Layout.fillWidth: true
                spacing: Theme.gapS
                C.StationText {
                    text: book.prompt === "ask" ? "Clear " + (book.asking ? book.asking.openSubOrders : 0) + " open sub-orders too? y / n" : book.prompt
                }
                C.Field {
                    id: promptField
                    visible: book.prompt !== "ask"
                    Layout.fillWidth: true
                    implicitHeight: 28
                    font.pixelSize: Theme.label
                    Keys.onEscapePressed: book.endPrompt()
                    // Handled here, so the key does not go on to the views and open the sheet.
                    Keys.onReturnPressed: book.submitPrompt()
                    Keys.onEnterPressed: book.submitPrompt()
                }
                C.Label {
                    visible: book.prompt === "site" || book.prompt === "tag"
                    text: book.suggestions.join(" · ")
                    color: Theme.muted
                    font.pixelSize: Theme.small
                }
            }
            // Capture, with the recognised tokens highlighted.
            C.Field {
                id: capture
                visible: book.kind !== "report" && book.kind !== "routines"
                Layout.fillWidth: true
                implicitHeight: 32
                font.family: Theme.mono
                font.pixelSize: Theme.label
                placeholderText: "new order: \"call bank fri 10 #Work p2 for 15m\""
                Keys.onEscapePressed: book.stepBack()
                Keys.onReturnPressed: book.submitCapture()
                Keys.onEnterPressed: book.submitCapture()
                background: Rectangle {
                    radius: 4
                    color: Theme.background
                    border.width: 1
                    border.color: capture.activeFocus ? Theme.accent : Theme.border
                }
            }
            Text {
                Layout.fillWidth: true
                visible: capture.text !== "" && book.kind !== "report" && book.kind !== "routines"
                textFormat: Text.StyledText
                elide: Text.ElideRight
                font.family: Theme.mono
                font.pixelSize: Theme.small
                color: Theme.muted
                text: DayText.highlight(capture.text, book.parsed).map(run => {
                    const safe = run.text.replace(/&/g, "&amp;").replace(/</g, "&lt;");
                    return run.kind === "title" ? safe : "<font color=\"" + (run.kind === "error" ? Theme.warning : Theme.accent) + "\">" + safe + "</font>";
                }).join("") + "  —  " + DayText.summary(book.parsed, book.now)
            }
            // The keys, always visible.
            Flow {
                Layout.fillWidth: true
                spacing: Theme.gapM
                Repeater {
                    model: ["Q new", "/ search", "G then T A I C S R go", "↑↓ move", "Space clear", "E sheet", "D due", "1-4 magnitude", "# site", "@ tag", "Ctrl+↑↓ reorder", "Alt+arrows move a block", "F quiet", "Ctrl+Z undo", "Del delete", "B board", "Esc back"]
                    C.Label {
                        required property string modelData
                        text: modelData
                        color: Theme.disabled
                        font.family: Theme.instrument
                        font.pixelSize: Theme.caption
                    }
                }
            }
        }
        LogbookSheet {
            id: sheet
            order: book.current
            now: book.now
            onClosed: {
                sheet.shown = false;
                book.release();
            }
            onReleased: book.release()
            onConfirmed: {
                if (book.current)
                    book.toggle(book.current);
            }
        }
    }
}
