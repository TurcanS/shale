pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import "../core"
import "../core/day.js" as DayText
import "../core/station.js" as Station
import "../services"
import "../components" as C

// The Day hub: the bar's Day pill grows into it. Every part of the shape is a function of one number, progress
// (0: the pill, 1: the open hub), so a reversal at any moment needs no special case.
// It is drawn as a field station's recorder: instrument plates, a drum that traces today, expected events and work
// orders.
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
    // Today's activity (activity.day), traced on the drum.
    property var activity: null
    readonly property bool recording: ShellState.setting("activityTracking", "ask") === "on"
    // The last deleted item and where it stood, for Undo.
    property var lastDeleted: null
    // The to-do list's row to select once the list has reloaded after a change.
    property int pendingRow: -1
    readonly property int headerHeight: 84
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
    // An instrument plate: a screwed-on panel with its name stamped in the top left.
    component Plate: Piece {
        id: plate
        property string label: ""
        property string note: ""
        property color noteColor: Theme.muted
        default property alias content: body.data
        Rectangle {
            anchors.fill: parent
            radius: 6
            color: Theme.panel
            border.width: 1
            border.color: Theme.border
            // A lighter top edge, as on a machined plate.
            Rectangle {
                x: 6
                y: 1
                width: parent.width - 12
                height: 1
                color: Qt.rgba(1, 1, 1, 0.04)
            }
            Repeater {
                model: 2
                Rectangle {
                    required property int index
                    x: index ? parent.width - 11 : 6
                    y: 6
                    width: 5
                    height: 5
                    radius: 2.5
                    color: Theme.raised
                }
            }
        }
        StationText {
            x: 16
            y: 11
            text: plate.label
        }
        StationText {
            anchors.right: parent.right
            anchors.rightMargin: 16
            y: 11
            text: plate.note
            color: plate.noteColor
        }
        Item {
            id: body
            anchors.fill: parent
            anchors.topMargin: 28
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.bottomMargin: 10
        }
    }
    // The small stamped capitals that name every instrument and reading.
    component StationText: Text {
        font.family: Theme.instrument
        font.pixelSize: Theme.caption
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1.6
        color: Theme.muted
    }
    // A hardware key: raised, pressed in when chosen; the accent edge shows keyboard focus.
    component StationKey: AbstractButton {
        id: key
        property bool lit: false
        implicitHeight: 30
        implicitWidth: Math.max(40, keyText.implicitWidth + 20)
        Layout.fillWidth: true
        focusPolicy: Qt.StrongFocus
        hoverEnabled: true
        Accessible.role: Accessible.Button
        Accessible.name: text
        contentItem: Text {
            id: keyText
            text: key.text
            font.family: Theme.instrument
            font.pixelSize: Theme.label
            color: key.lit ? Theme.accent : Theme.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 4
            color: key.down ? Theme.background : key.hovered ? Theme.hover : Theme.raised
            border.width: key.activeFocus ? 1.5 : 1
            border.color: key.activeFocus ? Theme.accent : Theme.border
            // The key's lower lip; it disappears while pressed.
            Rectangle {
                visible: !key.down
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 1
                height: 2
                radius: 2
                color: Theme.background
            }
        }
    }
    readonly property real grow: clamp((progress - 0.2) / 0.8)
    component FocusLength: StationKey {
        id: length
        required property int minutes
        visible: !Focus.active
        text: String(minutes)
        Accessible.name: "Quiet period, focus for " + minutes + " minutes"
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
    // Today runs from local midnight to the next one (23 or 25 hours on the days the clocks change).
    readonly property real dayStart: new Date(new Date(now).getFullYear(), new Date(now).getMonth(), new Date(now).getDate()).getTime()
    readonly property real dayEnd: new Date(new Date(now).getFullYear(), new Date(now).getMonth(), new Date(now).getDate() + 1).getTime()
    readonly property int dayOfYear: Math.round((dayStart - new Date(new Date(now).getFullYear(), 0, 1).getTime()) / 86400000) + 1
    readonly property real recordedSeconds: activity ? activity.active + activity.watching : 0

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
            ShellState.message((removed.kind === "todo" ? "Work order" : "Event") + " deleted · " + removed.text, "info", {label: "Undo", run: () => hub.undo()});
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
    function loadActivity() {
        Backend.request("activity.day", {date: Day.today()}, (result, error) => hub.activityLoaded(result, error));
    }
    function activityLoaded(result, error) {
        if (!error)
            activity = result;
    }
    onOpeningChanged: {
        if (opening) {
            now = Date.now();
            Day.refresh();
            loadWeather();
            loadActivity();
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
    // The drum moves on once a minute while the hub is open.
    Timer {
        interval: 60000
        repeat: true
        running: hub.opening && !hub.peek
        onTriggered: hub.loadActivity()
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
        // The station's floor; the plates sit on it.
        color: hub.peek ? Theme.panel : Theme.background
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
                    placeholderText: "New work order, or \"in 20m stretch\""
                    Keys.onEscapePressed: hub.stepBack()
                    Keys.onReturnPressed: hub.submit(peekField)
                    Keys.onEnterPressed: hub.submit(peekField)
                    onTextChanged: hub.now = Date.now()
                }
                C.Label {
                    readonly property var parsed: DayText.parse(peekField.text, hub.now)
                    text: parsed ? DayText.describe(parsed, hub.now) : "Enter files it · Escape closes"
                    color: parsed && parsed.error ? Theme.warning : Theme.muted
                    font.pixelSize: Theme.small
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }
        ColumnLayout {
            visible: !hub.peek
            x: Theme.gapM
            y: Theme.gapM
            width: hub.openWidth - 2 * Theme.gapM
            height: hub.openHeight - 2 * Theme.gapM
            spacing: Theme.gapS
            RowLayout {
                Layout.fillWidth: true
                // A layout inside a layout fills the height by default; the header keeps its own.
                Layout.fillHeight: false
                Layout.preferredHeight: hub.headerHeight
                spacing: Theme.gapS
                Plate {
                    order: 0
                    label: "Station · local"
                    Layout.fillWidth: false
                    Layout.preferredWidth: 236
                    Layout.fillHeight: true
                    // Phosphor glow: a blurred copy under the sharp digits; trimmed with the other effects.
                    MultiEffect {
                        visible: !Theme.lowPower
                        source: readout
                        anchors.fill: readout
                        autoPaddingEnabled: true
                        blurEnabled: true
                        blur: 0.7
                        blurMax: 16
                        opacity: 0.8
                    }
                    Row {
                        id: readout
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -2
                        spacing: 5
                        Accessible.role: Accessible.StaticText
                        Accessible.name: Qt.formatDateTime(new Date(hub.now), ShellState.timeFormat)
                        Repeater {
                            model: Qt.formatDateTime(new Date(hub.now), ShellState.timeFormat).split(":")
                            Row {
                                id: part
                                required property string modelData
                                required property int index
                                spacing: 5
                                // Doto's own colon reads as a dagger at this size; two dots on its grid replace it.
                                Column {
                                    visible: part.index > 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 9
                                    Repeater {
                                        model: 2
                                        Rectangle {
                                            width: 4
                                            height: 4
                                            color: Theme.accent
                                        }
                                    }
                                }
                                Text {
                                    text: part.modelData
                                    font.family: Theme.readout
                                    font.pixelSize: 36
                                    color: Theme.accent
                                }
                            }
                        }
                    }
                }
                Plate {
                    order: 0
                    Layout.fillHeight: true
                    RowLayout {
                        anchors.fill: parent
                        anchors.topMargin: -17
                        spacing: Theme.gapM
                        // The day of the year opens the calendar drawer.
                        AbstractButton {
                            id: dateButton
                            padding: 0
                            Layout.fillHeight: true
                            Layout.preferredWidth: 112
                            focusPolicy: Qt.StrongFocus
                            hoverEnabled: true
                            // Tab cycles inside the hub; it would otherwise move on to the bar's buttons underneath.
                            KeyNavigation.tab: nextList
                            KeyNavigation.backtab: capture
                            Accessible.role: Accessible.Button
                            Accessible.name: "Calendar, layer " + hub.dayOfYear + ", " + Qt.formatDateTime(new Date(hub.now), "dddd d MMMM")
                            onClicked: hub.toggleDrawer()
                            background: Rectangle {
                                anchors.fill: parent
                                anchors.margins: -4
                                radius: 4
                                color: hub.drawer ? Theme.selection : dateButton.hovered ? Theme.hover : "transparent"
                                border.width: dateButton.activeFocus ? 1.5 : 0
                                border.color: Theme.accent
                            }
                            // Columns, not layouts: a layout spreads its spare height, which set the three readings at
                            // different heights.
                            contentItem: Column {
                                topPadding: 6
                                spacing: 8
                                StationText {
                                    text: "Layer"
                                }
                                Text {
                                    text: hub.dayOfYear + "  <font color=\"" + Theme.muted + "\" size=\"2\">" + Qt.formatDateTime(new Date(hub.now), "ddd d") + "</font>"
                                    textFormat: Text.StyledText
                                    font.family: Theme.instrument
                                    font.pixelSize: Theme.heading - 4
                                    color: Theme.text
                                }
                            }
                        }
                        Column {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            topPadding: 6
                            spacing: 8
                            StationText {
                                text: "Atmos"
                            }
                            Row {
                                spacing: Theme.gapXs
                                C.Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !!hub.weather
                                    name: hub.weather ? hub.weather.current.icon : "cloud"
                                    color: Theme.muted
                                }
                                Text {
                                    text: hub.weather && hub.weather.current.temperature !== null ? hub.weather.current.temperature + "°" : "—"
                                    font.family: Theme.instrument
                                    font.pixelSize: Theme.heading - 4
                                    color: Theme.text
                                }
                            }
                        }
                        Column {
                            Layout.preferredWidth: 104
                            Layout.alignment: Qt.AlignTop
                            topPadding: 6
                            spacing: 8
                            StationText {
                                text: "Recorded"
                            }
                            Text {
                                text: hub.recording && hub.activity ? Station.duration(hub.recordedSeconds) : "—"
                                font.family: Theme.instrument
                                font.pixelSize: Theme.heading - 4
                                color: Theme.text
                            }
                        }
                    }
                }
            }
            // The drum: today from 00 to 24, traced from what was recorded, with the stylus at now and the events
            // still to come marked ahead of it.
            Plate {
                id: drumPlate
                order: 1
                Layout.preferredHeight: 128
                label: "Drum · 00 – 24"
                note: !hub.recording ? "Recorder off" : "● Recording"
                noteColor: hub.recording ? Theme.accent : Theme.muted
                Canvas {
                    id: drum
                    anchors.fill: parent
                    anchors.bottomMargin: 14
                    readonly property var inputs: [hub.activity, hub.now, hub.nextRows, hub.recording, Theme.accent, Theme.lowPower, width, height]
                    onInputsChanged: requestPaint()
                    onPaint: Station.paint(getContext("2d"), {
                        width: width,
                        height: height,
                        segments: hub.recording && hub.activity ? hub.activity.segments : [],
                        dayStart: hub.dayStart,
                        dayEnd: hub.dayEnd,
                        now: hub.now,
                        items: hub.nextRows,
                        accent: Theme.accent,
                        grid: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.08),
                        ahead: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25),
                        event: Theme.accent2,
                        stylus: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.45),
                        glow: !Theme.lowPower,
                        font: "10px \"" + Theme.instrument + "\""
                    })
                }
                Repeater {
                    model: 9
                    Text {
                        required property int index
                        x: Math.round(index / 8 * drum.width) - (index === 8 ? implicitWidth : index ? implicitWidth / 2 : 0)
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: -4
                        text: String(index * 3).padStart(2, "0")
                        font.family: Theme.instrument
                        font.pixelSize: Theme.caption - 1
                        color: Theme.disabled
                    }
                }
                // Tracking is off: say so where the trace would be, with the way to turn it on. The backing keeps the
                // flat line from running through the words.
                Rectangle {
                    visible: !hub.recording
                    anchors.centerIn: drum
                    width: offRow.implicitWidth + 2 * Theme.gapM
                    height: offRow.implicitHeight + Theme.gapS
                    radius: 4
                    color: Theme.panel
                    RowLayout {
                        id: offRow
                        anchors.centerIn: parent
                        spacing: Theme.gapM
                        C.Label {
                            text: "Nothing is being recorded."
                            color: Theme.muted
                        }
                        StationKey {
                            text: "Open Activity"
                            Layout.fillWidth: false
                            onClicked: ShellState.open("activity")
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.gapS
                Plate {
                    order: 2
                    label: "Expected events"
                    Layout.fillWidth: false
                    Layout.preferredWidth: 236
                    Layout.fillHeight: true
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: Theme.gapS
                        ListView {
                            id: nextList
                            KeyNavigation.tab: Focus.active ? endFocus : focus25
                            KeyNavigation.backtab: dateButton
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 0
                            activeFocusOnTab: true
                            keyNavigationEnabled: true
                            model: hub.nextRows
                            Accessible.name: "Expected events"
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
                                height: 38
                                radius: 3
                                color: ListView.isCurrentItem && nextList.activeFocus ? Theme.selection : "transparent"
                                Accessible.role: Accessible.ListItem
                                Accessible.name: hub.timeText(modelData.at) + " " + modelData.text
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: 1
                                    color: Theme.surface
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.gapXs
                                    anchors.rightMargin: Theme.gapXs
                                    spacing: Theme.gapS
                                    Text {
                                        text: nextRow.modelData.kind === "timer" ? Focus.clockText(Math.max(0, Math.ceil((nextRow.modelData.at - Focus.now) / 1000)))
                                                                                  : (Station.countdown(nextRow.modelData.at, hub.now) || Qt.formatDateTime(new Date(nextRow.modelData.at), "ddd"))
                                        font.family: Theme.instrument
                                        font.pixelSize: Theme.body
                                        color: Theme.accent2
                                        Layout.preferredWidth: 52
                                    }
                                    ColumnLayout {
                                        spacing: 0
                                        Layout.fillWidth: true
                                        C.Label {
                                            text: nextRow.modelData.text
                                            elide: Text.ElideRight
                                            font.pixelSize: Theme.label
                                            Layout.fillWidth: true
                                        }
                                        StationText {
                                            text: nextRow.modelData.kind === "timer" ? "Timer" : (nextRow.modelData.repeat ? "Repeats · " : "") + hub.timeText(nextRow.modelData.at)
                                            font.letterSpacing: 0.8
                                        }
                                    }
                                }
                            }
                        }
                        C.Label {
                            visible: hub.nextRows.length === 0
                            text: "No events expected. Start one with a time, like \"in 20m stretch\"."
                            color: Theme.muted
                            font.pixelSize: Theme.small
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            verticalAlignment: Text.AlignTop
                        }
                        // Focus as a quiet period: no events reach you while it runs.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.gapXs
                            StationText {
                                text: "Quiet"
                                Layout.rightMargin: Theme.gapXs
                            }
                            // In the Tab cycle after the events; Left and Right move between the lengths.
                            StationKey {
                                id: endFocus
                                visible: Focus.active
                                lit: true
                                text: "End · " + Focus.minutesText(Focus.remainingSeconds) + " left"
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
                }
                Plate {
                    order: 3
                    label: "Work orders"
                    note: hub.todoRows.length ? Day.todos.length + " open" : ""
                    Layout.fillHeight: true
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: Theme.gapXs
                        ListView {
                            id: todoList
                            KeyNavigation.tab: capture
                            KeyNavigation.backtab: Focus.active ? endFocus : focus25
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 1
                            activeFocusOnTab: true
                            keyNavigationEnabled: true
                            model: hub.todoRows
                            Accessible.name: "Work orders"
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
                                height: 27
                                radius: 3
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
                                    spacing: Theme.gapS + 2
                                    // A status lamp: an empty ring while open, lit once cleared. Done also reads from
                                    // the strike and the CLEARED stamp, not from colour alone.
                                    Rectangle {
                                        Layout.preferredWidth: 10
                                        Layout.preferredHeight: 10
                                        radius: 5
                                        color: todoRow.done ? Theme.success : "transparent"
                                        border.width: todoRow.done ? 0 : 1.5
                                        border.color: Theme.muted
                                        TapHandler {
                                            margin: 8
                                            onTapped: hub.toggle(todoRow.modelData, todoRow.index)
                                        }
                                    }
                                    C.Label {
                                        text: todoRow.modelData.text
                                        color: todoRow.done ? Theme.muted : Theme.text
                                        font.strikeout: todoRow.done
                                        font.pixelSize: Theme.label
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    StationText {
                                        visible: todoRow.done
                                        text: "Cleared " + Qt.formatDateTime(new Date(todoRow.modelData.doneAt || 0), ShellState.timeFormat)
                                        color: Theme.success
                                        font.letterSpacing: 1.2
                                    }
                                }
                            }
                        }
                        C.Label {
                            visible: hub.todoRows.length === 0
                            text: "No work orders. The station is calm."
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
                            implicitHeight: 32
                            leftPadding: 26
                            font.family: Theme.mono
                            font.pixelSize: Theme.label
                            placeholderText: "new work order, or \"in 20m stretch\""
                            Keys.onEscapePressed: hub.stepBack()
                            Keys.onReturnPressed: hub.submit(capture)
                            Keys.onEnterPressed: hub.submit(capture)
                            onTextChanged: hub.now = Date.now()
                            background: Rectangle {
                                radius: 4
                                color: Theme.background
                                border.width: 1
                                border.color: capture.activeFocus ? Theme.accent : Theme.border
                                Text {
                                    x: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: ">"
                                    font.family: Theme.mono
                                    font.pixelSize: Theme.label
                                    color: Theme.accent
                                }
                            }
                        }
                        // How the text was understood, before Enter adds it; a refusal says why.
                        C.Label {
                            text: hub.parsed ? DayText.describe(hub.parsed, hub.now) : "Enter files · Tab moves · Space clears · Delete removes"
                            color: hub.parsed && hub.parsed.error ? Theme.warning : Theme.muted
                            font.pixelSize: Theme.caption
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }
        // The calendar drawer slides in over the lower plates and leaves the header in view.
        Rectangle {
            id: drawerPanel
            readonly property int below: Theme.gapM + hub.headerHeight + Theme.gapS
            y: below
            width: 320
            height: hub.openHeight - below - Theme.gapM
            x: hub.drawer ? hub.openWidth - width - Theme.gapM : hub.openWidth + 8
            visible: x < hub.openWidth
            radius: 6
            color: Theme.panel
            border.width: 1
            border.color: Theme.border
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
                anchors.margins: Theme.gapS
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
