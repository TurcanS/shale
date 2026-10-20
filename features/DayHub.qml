pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import "../core"
import "../core/day.js" as DayText
import "../services"
import "../components" as C

// The Day hub: the bar's Day pill grows into it. Every part of the shape is a function of one number, progress
// (0: the pill, 1: the open hub), so a reversal at any moment needs no special case.
Item {
    id: hub
    property real progress: 0
    // True while opening; closing runs the same curves backwards, without the stagger.
    property bool opening: false
    property bool edge: false
    // Where the pill sits in the bar, in this item's coordinates; the bar sets it as the hub opens and closes.
    property rect pill: Qt.rect(0, 0, 0, 0)
    // The quick-add row: only the field, Enter adds and closes.
    property bool peek: false
    readonly property int fullHeight: 460
    readonly property int openWidth: peek ? 480 : 640
    readonly property int openHeight: peek ? Theme.controlLarge + Theme.small + Theme.gapXs + 2 * Theme.gapM + 4 : fullHeight
    readonly property alias shape: shape
    // Space under the open hub for its shadow, inside the window so the shadow is not cut off.
    readonly property int shadowRoom: 40
    // The calendar drawer over the right of the hub.
    property bool drawer: false
    property date drawerMonth: new Date()
    property real now: Date.now()
    property var weather: null
    // The last deleted item and where it stood, for Undo.
    property var lastDeleted: null
    // The to-do list's row to select once the list has reloaded after a change.
    property int pendingRow: -1
    signal dismissed()
    signal pillClicked()
    function settle(from, to, t) {
        return from + (to - from) * t;
    }
    function clamp(t) {
        return Math.max(0, Math.min(1, t));
    }
    // A small overshoot on the width only: on a 460 px height the same overshoot would be 9+ px and look sloppy.
    function outBack(t) {
        const s = Theme.lowPower || Theme.reduced ? 0 : 0.6;
        return 1 + (s + 1) * Math.pow(t - 1, 3) + s * Math.pow(t - 1, 2);
    }
    function outCubic(t) {
        return 1 - Math.pow(1 - t, 3);
    }
    component Piece: Item {
        id: piece
        property int order: 0
        // Each piece rises 6 px in order while opening, about 30 ms apart, and all fade together when closing. An
        // animation of its own (not a formula of progress) lets a reversal carry on from where each piece is.
        property real shown: hub.opening ? 1 : 0
        Behavior on shown {
            id: rise
            SequentialAnimation {
                PauseAnimation {
                    duration: rise.targetValue < 1 || Theme.reduced ? 0 : (Theme.lowPower ? 80 + 15 * piece.order : 160 + 30 * piece.order)
                }
                NumberAnimation {
                    duration: rise.targetValue < 1 ? Theme.fast : Theme.enter
                    easing.type: Easing.OutCubic
                }
            }
        }
        Layout.fillWidth: true
        opacity: shown
        transform: Translate { y: Theme.reduced ? 0 : (1 - piece.shown) * 6 }
    }
    readonly property real grow: clamp((progress - 0.2) / 0.8)
    component FocusLength: C.Button {
        id: length
        required property int minutes
        visible: !Focus.active
        flat: true
        text: String(minutes)
        Accessible.name: "Focus for " + minutes + " minutes"
        Layout.fillWidth: true
        KeyNavigation.tab: todoList
        KeyNavigation.backtab: nextList
        onClicked: Focus.start(length.minutes)
    }

    // Open to-dos in their order, then today's done ones, latest first.
    readonly property var doneToday: Day.items.filter(item => item.kind === "todo" && item.doneAt).sort((a, b) => b.doneAt - a.doneAt)
    readonly property var todoRows: Day.todos.concat(doneToday)
    // Reminders still to come (the next one may be on a later day) and running timers, soonest first.
    readonly property var nextRows: {
        const pending = item => item.kind === "reminder" && !item.doneAt && !(item.firedAt && item.firedAt >= item.at);
        const reminders = Day.items.filter(pending);
        const next = Day.nextItem;
        if (next && pending(next) && !reminders.some(item => item.id === next.id))
            reminders.push(next);
        const timers = Focus.timers.map(timer => ({kind: "timer", id: timer.id, at: timer.endsAt, text: timer.label || Focus.minutesText(timer.seconds) + " timer"}));
        return reminders.concat(timers).sort((a, b) => a.at - b.at).slice(0, 5);
    }
    readonly property var parsed: DayText.parse(capture.text, now)

    function focusCapture() {
        (peek ? peekField : capture).forceActiveFocus();
    }
    // Escape closes the drawer first, then the hub, as the panels do.
    function stepBack() {
        if (drawer) {
            drawer = false;
            capture.forceActiveFocus();
        } else
            dismissed();
    }
    function toggleDrawer() {
        if (!drawer)
            drawerMonth = new Date(new Date().getFullYear(), new Date().getMonth(), 1);
        drawer = !drawer;
        if (!drawer)
            capture.forceActiveFocus();
    }
    function submit(field) {
        const item = DayText.parse(field.text, Date.now());
        if (!item || item.error)
            return;
        // Cleared at once: keys typed before the helper answers belong to the next item.
        const text = field.text;
        field.text = "";
        Day.add(item, (result, error) => hub.added(error, field, text));
        if (peek)
            dismissed();
    }
    function added(error, field, text) {
        if (!error)
            return;
        if (!field.text)
            field.text = text;
        ShellState.message(error.message, "error");
    }
    function toggle(item, row) {
        pendingRow = row;
        if (item.doneAt)
            Day.undone(item.id);
        else
            Day.done(item.id);
    }
    // Ctrl+Up/Down moves an open to-do within the open ones.
    function move(row, delta) {
        const ids = Day.todos.map(item => item.id);
        const target = row + delta;
        if (row >= ids.length || target < 0 || target >= ids.length)
            return;
        ids.splice(target, 0, ids.splice(row, 1)[0]);
        pendingRow = target;
        Day.reorder(ids);
    }
    function remove(item, row) {
        pendingRow = row;
        Day.remove(item.id, (removed, error) => {
            if (error)
                return;
            hub.lastDeleted = {item: removed, row: item.kind === "todo" && !item.doneAt ? row : -1};
            ShellState.message((removed.kind === "todo" ? "To-do" : "Reminder") + " deleted · " + removed.text, "info", {label: "Undo", run: () => hub.undo()});
        });
    }
    // Adds the deleted item back: done ones stay done, open to-dos return to their place.
    function undo() {
        const deleted = lastDeleted;
        if (!deleted)
            return;
        lastDeleted = null;
        const item = deleted.item;
        Day.add({kind: item.kind, text: item.text, dueAt: item.dueAt, repeat: item.repeat}, (added, error) => hub.restored(added, error, item, deleted.row));
        ShellState.toast = "";
    }
    // A named function rather than code in the callback: qmllint skips a whole file whose callbacks declare constants.
    function restored(added, error, item, row) {
        if (error)
            return;
        if (item.doneAt) {
            Day.done(added.id);
            return;
        }
        if (row < 0)
            return;
        const ids = Day.todos.map(todo => todo.id).filter(id => id !== added.id);
        ids.splice(Math.min(row, ids.length), 0, added.id);
        Day.reorder(ids);
    }
    function timeText(at) {
        const date = new Date(at);
        const today = new Date(now).toDateString() === date.toDateString();
        return (today ? "" : Qt.formatDateTime(date, "ddd") + " ") + Qt.formatDateTime(date, ShellState.timeFormat);
    }
    function loadWeather() {
        const location = ShellState.setting("weatherLocation", {});
        if (!location || !location.name)
            return;
        Backend.request("weather.get", {location: location, units: ShellState.setting("weatherUnits", "metric"), refresh: false}, (result, error) => {
            if (!error)
                hub.weather = result;
        });
    }
    onOpeningChanged: {
        if (opening) {
            now = Date.now();
            Day.refresh();
            loadWeather();
        } else {
            drawer = false;
            capture.text = "";
            peekField.text = "";
        }
    }
    Timer {
        interval: 15000
        repeat: true
        running: hub.opening
        onTriggered: hub.now = Date.now()
    }
    Connections {
        target: Day
        function onTodosChanged() {
            Qt.callLater(hub.restoreRow);
        }
    }
    function restoreRow() {
        if (pendingRow < 0)
            return;
        todoList.currentIndex = Math.min(pendingRow, todoList.count - 1);
        pendingRow = -1;
    }

    // The same lift as the other panels; skipped when effects are trimmed.
    RectangularShadow {
        anchors.fill: shape
        visible: shape.visible && !Theme.lowPower
        opacity: hub.grow
        radius: shape.radius
        blur: 28
        offset.y: 8
        color: Qt.rgba(0, 0, 0, 0.5)
    }
    Rectangle {
        id: shape
        visible: hub.progress > 0
        // Snapped to whole pixels so the edges stay sharp at fractional scales.
        width: Math.round(hub.settle(hub.pill.width, hub.openWidth, hub.outBack(hub.grow)))
        height: Math.round(hub.settle(hub.pill.height, hub.openHeight, hub.outCubic(hub.grow)))
        x: Math.round(hub.settle(hub.pill.x + hub.pill.width / 2, hub.width / 2, hub.outCubic(hub.grow)) - width / 2)
        y: Math.round(hub.settle(hub.pill.y, 0, hub.outCubic(hub.grow)))
        // The pill's radius grows into the panel radius, staying concentric with the bar's own corners.
        radius: hub.settle(Theme.radiusSmall, Theme.panelRadius, hub.grow)
        topLeftRadius: hub.edge ? hub.settle(radius, 0, hub.grow) : radius
        topRightRadius: topLeftRadius
        color: Theme.panel
        // A hairline edge separates the hub from dark windows once it has left the bar.
        border.width: hub.grow > 0 ? 1 : 0
        border.color: Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, hub.grow)
        clip: true
        Keys.onEscapePressed: hub.stepBack()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Z && (event.modifiers & Qt.ControlModifier)) {
                hub.undo();
                event.accepted = true;
            }
        }
        // The hub lies over the middle of the bar; without this, clicks, scrolls and hovers on it would reach the
        // bar buttons underneath (the clock would open the calendar). The pill it grew from stays clickable, so a
        // second click closes the hub, or reverses it mid-way.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
            onWheel: wheel => wheel.accepted = true
            onClicked: mouse => {
                const x = mouse.x + shape.x, y = mouse.y + shape.y;
                if (mouse.button === Qt.LeftButton && x >= hub.pill.x && x < hub.pill.x + hub.pill.width && y >= hub.pill.y && y < hub.pill.y + hub.pill.height)
                    hub.pillClicked();
            }
        }
        // The quick-add row.
        Piece {
            visible: hub.peek
            x: Theme.gapM
            y: Theme.gapM
            width: hub.openWidth - 2 * Theme.gapM
            height: hub.openHeight - 2 * Theme.gapM
            ColumnLayout {
                anchors.fill: parent
                spacing: Theme.gapXs
                C.Field {
                    id: peekField
                    Layout.fillWidth: true
                    placeholderText: "Add a to-do, or \"in 20m stretch\""
                    Keys.onEscapePressed: hub.stepBack()
                    Keys.onReturnPressed: hub.submit(peekField)
                    Keys.onEnterPressed: hub.submit(peekField)
                    onTextChanged: hub.now = Date.now()
                }
                C.Label {
                    readonly property var parsed: DayText.parse(peekField.text, hub.now)
                    text: parsed ? DayText.describe(parsed, hub.now) : "Enter adds · Escape closes"
                    color: parsed && parsed.error ? Theme.warning : Theme.muted
                    font.pixelSize: Theme.small
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }
        ColumnLayout {
            visible: !hub.peek
            x: Theme.panelPadding
            y: Theme.panelPadding
            width: hub.openWidth - 2 * Theme.panelPadding
            height: hub.openHeight - 2 * Theme.panelPadding
            spacing: Theme.gapM
            Piece {
                order: 0
                Layout.preferredHeight: 40
                RowLayout {
                    anchors.fill: parent
                    spacing: Theme.gapM
                    C.Label {
                        text: Qt.formatDateTime(new Date(hub.now), ShellState.timeFormat)
                        font.family: Theme.mono
                        font.pixelSize: Theme.heading
                        Layout.fillWidth: true
                    }
                    C.Button {
                        id: dateButton
                        flat: true
                        glyph: "calendar"
                        // Tab cycles inside the hub; it would otherwise move on to the bar's buttons underneath.
                        KeyNavigation.tab: nextList
                        KeyNavigation.backtab: capture
                        text: Qt.formatDateTime(new Date(hub.now), "ddd d MMM")
                        selected: hub.drawer
                        hint: "Calendar"
                        Accessible.name: "Calendar, " + Qt.formatDateTime(new Date(hub.now), "dddd d MMMM")
                        onClicked: hub.toggleDrawer()
                    }
                    RowLayout {
                        visible: !!hub.weather
                        spacing: Theme.gapXs
                        C.Icon {
                            name: hub.weather ? hub.weather.current.icon : "cloud"
                            color: Theme.muted
                        }
                        C.Label {
                            text: hub.weather && hub.weather.current.temperature !== null ? hub.weather.current.temperature + "°" : ""
                            color: Theme.muted
                        }
                    }
                }
            }
            // The large Line comes with step 5; this keeps its place.
            Piece {
                order: 1
                Layout.preferredHeight: 16
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 10
                    radius: 5
                    color: Theme.surface
                }
            }
            Piece {
                order: 2
                Layout.fillHeight: true
                RowLayout {
                    anchors.fill: parent
                    spacing: Theme.gapL
                    ColumnLayout {
                        Layout.preferredWidth: 220
                        Layout.fillHeight: true
                        spacing: Theme.gapS
                        C.SectionHeader {
                            text: "NEXT UP"
                        }
                        ListView {
                            id: nextList
                            KeyNavigation.tab: Focus.active ? endFocus : focus25
                            KeyNavigation.backtab: dateButton
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 2
                            activeFocusOnTab: true
                            keyNavigationEnabled: true
                            model: hub.nextRows
                            Accessible.name: "Next up"
                            Accessible.role: Accessible.List
                            Keys.onDeletePressed: {
                                const item = hub.nextRows[currentIndex];
                                if (!item)
                                    return;
                                if (item.kind === "timer")
                                    Focus.cancelTimer(item.id);
                                else
                                    hub.remove(item, currentIndex);
                            }
                            delegate: Rectangle {
                                id: nextRow
                                required property var modelData
                                required property int index
                                width: ListView.view.width
                                height: 32
                                radius: Theme.radiusSmall
                                color: ListView.isCurrentItem && nextList.activeFocus ? Theme.selection : "transparent"
                                Accessible.role: Accessible.ListItem
                                Accessible.name: hub.timeText(modelData.at) + " " + modelData.text
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.gapS
                                    anchors.rightMargin: Theme.gapS
                                    spacing: Theme.gapS
                                    C.Icon {
                                        name: nextRow.modelData.kind === "timer" ? "timer" : nextRow.modelData.repeat ? "repeat" : "bell"
                                        size: Theme.iconSmall
                                        color: Theme.muted
                                    }
                                    C.Label {
                                        text: nextRow.modelData.kind === "timer" ? Focus.clockText(Math.max(0, Math.ceil((nextRow.modelData.at - Focus.now) / 1000)))
                                                                                  : hub.timeText(nextRow.modelData.at)
                                        font.family: Theme.mono
                                        font.pixelSize: Theme.small
                                        color: Theme.muted
                                    }
                                    C.Label {
                                        text: nextRow.modelData.text
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                        C.Label {
                            visible: hub.nextRows.length === 0
                            text: "No reminders. Start one with a time, like \"in 20m stretch\"."
                            color: Theme.muted
                            font.pixelSize: Theme.small
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        // Quick-start for a Focus session, or the running one.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.gapXs
                            C.Icon {
                                name: "focus"
                                color: Theme.muted
                            }
                            // In the Tab cycle after Next up; Left and Right move between the lengths.
                            C.Button {
                                id: endFocus
                                visible: Focus.active
                                flat: true
                                text: "End focus · " + Focus.minutesText(Focus.remainingSeconds)
                                Layout.fillWidth: true
                                KeyNavigation.tab: todoList
                                KeyNavigation.backtab: nextList
                                onClicked: Focus.end(true)
                            }
                            FocusLength {
                                id: focus25
                                minutes: 25
                                KeyNavigation.right: focus50
                            }
                            FocusLength {
                                id: focus50
                                minutes: 50
                                KeyNavigation.left: focus25
                                KeyNavigation.right: focus90
                            }
                            FocusLength {
                                id: focus90
                                minutes: 90
                                KeyNavigation.left: focus50
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Theme.gapS
                        C.SectionHeader {
                            text: "TO-DO"
                            C.Label {
                                visible: hub.todoRows.length > 0
                                text: hub.doneToday.length + " / " + hub.todoRows.length
                                font.family: Theme.mono
                                font.pixelSize: Theme.small
                                color: Theme.muted
                            }
                        }
                        ListView {
                            id: todoList
                            KeyNavigation.tab: capture
                            KeyNavigation.backtab: Focus.active ? endFocus : focus25
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 2
                            activeFocusOnTab: true
                            keyNavigationEnabled: true
                            model: hub.todoRows
                            Accessible.name: "To-do"
                            Accessible.role: Accessible.List
                            Keys.onPressed: event => {
                                const item = hub.todoRows[currentIndex];
                                if (!item)
                                    return;
                                if (event.key === Qt.Key_Space) {
                                    hub.toggle(item, currentIndex);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Delete) {
                                    hub.remove(item, currentIndex);
                                    event.accepted = true;
                                } else if ((event.key === Qt.Key_Up || event.key === Qt.Key_Down) && (event.modifiers & Qt.ControlModifier)) {
                                    hub.move(currentIndex, event.key === Qt.Key_Up ? -1 : 1);
                                    event.accepted = true;
                                }
                            }
                            delegate: Rectangle {
                                id: todoRow
                                required property var modelData
                                required property int index
                                readonly property bool done: !!modelData.doneAt
                                width: ListView.view.width
                                height: 34
                                radius: Theme.radiusSmall
                                color: ListView.isCurrentItem && todoList.activeFocus ? Theme.selection : rowHover.hovered ? Theme.hover : "transparent"
                                Accessible.role: Accessible.CheckBox
                                Accessible.name: modelData.text
                                Accessible.checked: done
                                HoverHandler {
                                    id: rowHover
                                }
                                TapHandler {
                                    onTapped: {
                                        todoList.currentIndex = todoRow.index;
                                        todoList.forceActiveFocus();
                                    }
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.gapS
                                    anchors.rightMargin: Theme.gapS
                                    spacing: Theme.gapS
                                    // Done is shown by the check mark and the strike, not by colour alone.
                                    Rectangle {
                                        Layout.preferredWidth: 18
                                        Layout.preferredHeight: 18
                                        radius: 5
                                        color: todoRow.done ? Theme.accent : "transparent"
                                        border.width: todoRow.done ? 0 : 1.5
                                        border.color: Theme.muted
                                        C.Icon {
                                            anchors.centerIn: parent
                                            visible: todoRow.done
                                            name: "check"
                                            size: Theme.iconSmall
                                            color: Theme.background
                                        }
                                        TapHandler {
                                            onTapped: hub.toggle(todoRow.modelData, todoRow.index)
                                        }
                                    }
                                    C.Label {
                                        text: todoRow.modelData.text
                                        color: todoRow.done ? Theme.muted : Theme.text
                                        font.strikeout: todoRow.done
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                        C.Label {
                            visible: hub.todoRows.length === 0
                            text: "Nothing planned. Type below."
                            color: Theme.muted
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        C.Field {
                            id: capture
                            KeyNavigation.tab: dateButton
                            KeyNavigation.backtab: todoList
                            Layout.fillWidth: true
                            placeholderText: "Add a to-do, or \"in 20m stretch\""
                            Keys.onEscapePressed: hub.stepBack()
                            Keys.onReturnPressed: hub.submit(capture)
                            Keys.onEnterPressed: hub.submit(capture)
                            onTextChanged: hub.now = Date.now()
                        }
                        // How the text was understood, before Enter adds it; a refusal says why.
                        C.Label {
                            text: hub.parsed ? DayText.describe(hub.parsed, hub.now) : "Enter adds · Tab moves · Space checks · Delete removes"
                            color: hub.parsed && hub.parsed.error ? Theme.warning : Theme.muted
                            font.pixelSize: Theme.small
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }
        // The calendar drawer slides in over the columns and leaves the header in view.
        Rectangle {
            id: drawerPanel
            readonly property int below: Theme.panelPadding + 40 + Theme.gapM
            y: below
            width: 320
            height: hub.openHeight - below - Theme.panelPadding
            x: hub.drawer ? hub.openWidth - width - Theme.panelPadding : hub.openWidth + 8
            visible: x < hub.openWidth
            color: Theme.panel
            Behavior on x {
                NumberAnimation {
                    duration: Theme.enter
                    easing.type: Easing.OutCubic
                }
            }
            onVisibleChanged: if (visible && hub.drawer) month.forceActiveFocus()
            MonthView {
                id: month
                anchors.fill: parent
                month: hub.drawerMonth
                today: new Date(hub.now)
                activeFocusOnTab: true
                onShiftRequested: delta => hub.drawerMonth = new Date(hub.drawerMonth.getFullYear(), hub.drawerMonth.getMonth() + delta, 1)
                onMonthChosen: chosen => hub.drawerMonth = chosen
                Keys.onLeftPressed: shiftRequested(-1)
                Keys.onRightPressed: shiftRequested(1)
            }
        }
    }
}
