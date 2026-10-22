pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../core"
import "../core/dig.js" as DigMath
import "../components" as C

// Time you can dig through: a week of days, a month, a year, one layer each, with what happened in them. Scrolling
// goes deeper (week, month, year) and back; the arrow keys move along.
FocusScope {
    id: dig
    property string level: "week"
    property string anchor: today()
    property var layers: ({days: [], start: "", end: ""})
    property string chosen: ""
    property string hoveredDay: ""
    property bool alive: true
    property real progress: 1
    readonly property int labelWidth: 64
    readonly property var days: layers.days || []
    readonly property var byDate: {
        const map = {};
        for (const entry of days)
            map[entry.date] = entry;
        return map;
    }
    readonly property real trackWidth: Math.max(1, bodyArea.width - labelWidth)
    readonly property var rowList: level === "year" ? [] : DigMath.rows(days, level, level === "week" ? Math.min(56, Math.floor((bodyArea.height - 6) / 7 - 1)) : 28, 3, bodyArea.height)
    readonly property var columnList: level === "year" ? DigMath.columns(days, bodyArea.width) : []
    readonly property string shownDay: hoveredDay || chosen
    readonly property var shownEntry: byDate[shownDay] || null
    signal openDay(string date)

    function today() { return DigMath.isoDay(new Date()); }
    function load() {
        if (!Backend.ready)
            return;
        const wanted = level + anchor;
        Backend.request("dig.range", {level: level, date: anchor, weekStart: ShellState.firstDayOfWeek}, (result, error) => {
            if (!alive || error || wanted !== level + anchor)
                return;
            layers = result;
        });
    }
    function periodLabel() {
        if (!layers.start)
            return "";
        const first = new Date(layers.start + "T12:00:00"), last = new Date(layers.end + "T12:00:00");
        if (level === "year")
            return Qt.formatDate(first, "yyyy");
        if (level === "month")
            return Qt.formatDate(first, "MMMM yyyy");
        return Qt.formatDate(first, "d MMM") + " – " + Qt.formatDate(last, "d MMM yyyy");
    }
    function move(step) {
        anchor = DigMath.shiftAnchor(level, anchor, step);
        chosen = "";
    }
    function deeper(step) {
        const next = DigMath.shiftLevel(level, step);
        if (next !== level)
            level = next;
    }
    function bandColor(band) {
        if (band.state === "idle")
            return Theme.activityIdle;
        const mineral = Theme.mineral(band.app);
        return band.state === "watching" ? Theme.mix(mineral, Theme.warning, 0.35) : mineral;
    }
    function describeDay(entry) {
        const date = new Date(entry.date + "T12:00:00");
        return Qt.formatDate(date, "ddd d MMM yyyy") + "  ·  " + DigMath.describe(entry);
    }
    function pick(point) {
        const entry = level === "year" ? (DigMath.columnAt(columnList, point.x) || {}).entry
            : (DigMath.rowAt(rowList, point.y) || {}).entry;
        return entry ? entry.date : "";
    }
    onLevelChanged: {
        progress = 0;
        fade.restart();
        chosen = "";
        load();
    }
    onAnchorChanged: load()
    Component.onCompleted: load()
    Component.onDestruction: alive = false
    Connections {
        target: Backend
        function onReadyChanged() { dig.load(); }
    }
    Timer { interval: 60000; running: dig.visible; repeat: true; onTriggered: dig.load() }
    NumberAnimation { id: fade; target: dig; property: "progress"; to: 1; duration: Theme.reduced ? 0 : Theme.enter; easing.type: Easing.OutCubic }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Left || event.key === Qt.Key_PageUp)
            move(-1);
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_PageDown)
            move(1);
        else if (event.key === Qt.Key_Down)
            deeper(1);
        else if (event.key === Qt.Key_Up)
            deeper(-1);
        else if (event.key === Qt.Key_Home)
            anchor = today();
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && chosen)
            openDay(chosen);
        else
            return;
        event.accepted = true;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.gapS
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gapS
            C.Segmented {
                fill: false
                Layout.preferredWidth: 260
                model: [{key: "week", text: "Week"}, {key: "month", text: "Month"}, {key: "year", text: "Year"}]
                current: dig.level
                onActivated: key => dig.level = key
            }
            Item { Layout.fillWidth: true }
            C.Button { glyph: "back"; flat: true; hint: "Earlier"; Accessible.name: "Earlier"; onClicked: dig.move(-1) }
            C.Label {
                text: dig.periodLabel()
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                Layout.preferredWidth: 170
            }
            C.Button { glyph: "chevron"; flat: true; hint: "Later"; Accessible.name: "Later"; onClicked: dig.move(1) }
            C.Button { text: "Today"; flat: true; onClicked: dig.anchor = dig.today() }
        }
        Item {
            id: bodyArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            opacity: dig.progress
            Accessible.role: Accessible.Table
            Accessible.name: "The Dig, " + dig.level + " of " + dig.periodLabel()

            // Rows: a week of equal layers, or a month of layers as thick as the day's active time.
            Repeater {
                model: dig.rowList
                Item {
                    id: row
                    required property var modelData
                    readonly property var marks: DigMath.layout(modelData.entry, dig.trackWidth)
                    readonly property bool selected: dig.shownDay === modelData.date
                    y: modelData.y
                    width: bodyArea.width
                    height: modelData.height
                    Rectangle {
                        anchors.fill: parent
                        color: Theme.accent
                        opacity: row.selected ? 0.12 : 0
                    }
                    C.StationText {
                        id: dayLabel
                        width: dig.labelWidth - 8
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.height >= 11
                        text: Qt.formatDate(new Date(row.modelData.date + "T12:00:00"), dig.level === "week" ? "ddd d" : "d")
                        font.pixelSize: 9
                        color: row.selected ? Theme.text : Theme.muted
                    }
                    // Fossils: a pinned app that was used that day, a small hollow square at the foot of the layer.
                    Row {
                        anchors.right: dayLabel.right
                        anchors.bottom: parent.bottom
                        spacing: 2
                        Repeater {
                            model: row.modelData.entry.fossils || []
                            Rectangle {
                                required property string modelData
                                width: 5
                                height: 5
                                color: "transparent"
                                border.width: 1
                                border.color: Theme.mineral(modelData)
                            }
                        }
                    }
                    Item {
                        id: track
                        x: dig.labelWidth
                        width: dig.trackWidth
                        height: parent.height
                        Rectangle {
                            anchors.fill: parent
                            radius: 1
                            color: Theme.raised
                            opacity: 0.55
                        }
                        // A week shows each stretch of the day; a month's layer is one colour, the day's main app.
                        Repeater {
                            model: dig.level === "week" ? row.marks.bands : []
                            Rectangle {
                                required property var modelData
                                x: modelData.x
                                width: modelData.width
                                height: track.height
                                color: dig.bandColor(modelData)
                            }
                        }
                        Rectangle {
                            visible: dig.level === "month" && !!row.modelData.entry.dominant
                            width: (row.modelData.entry.active + row.modelData.entry.watching) > 0 ? track.width : 0
                            height: track.height
                            radius: 1
                            color: Theme.mineral(row.modelData.entry.dominant)
                            opacity: 0.8
                        }
                        // Veins: a bright band across the layer for a Quiet session.
                        Repeater {
                            model: row.marks.veins
                            Rectangle {
                                required property var modelData
                                x: modelData.x
                                width: modelData.width
                                height: Math.min(4, track.height)
                                color: Theme.accent2
                            }
                        }
                        // Grains: round dots; a critical one is larger.
                        Repeater {
                            model: row.marks.grains
                            Rectangle {
                                required property var modelData
                                width: modelData.urgent ? 6 : 4
                                height: width
                                radius: width / 2
                                x: modelData.x - width / 2
                                y: track.height - height - 1
                                color: Theme.mineral(modelData.app)
                                border.width: 1
                                border.color: Theme.text
                            }
                        }
                        // Flecks: bone diamonds, at the moment an order was cleared.
                        Repeater {
                            model: row.marks.flecks
                            Rectangle {
                                required property var modelData
                                width: 6
                                height: 6
                                rotation: 45
                                x: modelData.x - 3
                                y: Math.max(0, (track.height - 6) / 2)
                                color: Theme.text
                            }
                        }
                        // Glints: a small cross where a screenshot or recording was saved.
                        Repeater {
                            model: row.marks.glints
                            Item {
                                id: spark
                                required property var modelData
                                x: modelData.x - 4
                                y: Math.max(0, (track.height - 8) / 2)
                                width: 8
                                height: 8
                                Rectangle { anchors.centerIn: parent; width: 8; height: 1; color: Theme.warning }
                                Rectangle { anchors.centerIn: parent; width: 1; height: 8; color: Theme.warning }
                                Rectangle { anchors.centerIn: parent; width: spark.modelData.kind === "recording" ? 4 : 2; height: width; color: Theme.warning }
                            }
                        }
                    }
                }
            }

            // A year: one column a day, coloured by the day's main app and dimmer when less was recorded.
            Repeater {
                model: dig.columnList
                Item {
                    id: slice
                    required property var modelData
                    readonly property bool selected: dig.shownDay === modelData.date
                    x: modelData.x
                    width: modelData.width
                    height: bodyArea.height - 18
                    Rectangle {
                        anchors.fill: parent
                        color: Theme.raised
                        opacity: 0.4
                    }
                    Rectangle {
                        visible: slice.modelData.level > 0
                        anchors.fill: parent
                        color: Theme.mineral(slice.modelData.app)
                        opacity: 0.2 + 0.2 * slice.modelData.level
                    }
                    Rectangle {
                        visible: slice.modelData.vein
                        width: parent.width
                        height: 3
                        color: Theme.accent2
                    }
                    Rectangle {
                        visible: slice.modelData.noted
                        width: Math.min(4, parent.width)
                        height: width
                        anchors.bottom: parent.bottom
                        color: Theme.text
                    }
                    Rectangle {
                        visible: slice.selected
                        anchors.fill: parent
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.text
                    }
                }
            }
            Repeater {
                model: dig.level === "year" ? DigMath.monthMarks(dig.columnList) : []
                C.StationText {
                    required property var modelData
                    x: modelData.x
                    y: bodyArea.height - 14
                    text: Qt.formatDate(new Date(modelData.date + "T12:00:00"), "MMM")
                    font.pixelSize: 9
                }
            }
            C.Label {
                visible: dig.days.length > 0 && !dig.days.some(entry => entry.active + entry.watching > 0)
                anchors.centerIn: parent
                text: "Nothing recorded in this period."
                color: Theme.muted
            }
            HoverHandler {
                id: hover
                onPointChanged: dig.hoveredDay = hover.hovered ? dig.pick(hover.point.position) : ""
                onHoveredChanged: if (!hovered) dig.hoveredDay = ""
            }
            TapHandler {
                onTapped: point => { dig.chosen = dig.pick(point.position); dig.forceActiveFocus(); }
                onDoubleTapped: point => { dig.chosen = dig.pick(point.position); if (dig.chosen) dig.openDay(dig.chosen); }
            }
            // Scrolling down goes deeper in time, up comes back; one step at a time.
            WheelHandler {
                property double last: 0
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    if (event.angleDelta.y === 0 || Date.now() - last < 220)
                        return;
                    last = Date.now();
                    dig.deeper(event.angleDelta.y < 0 ? 1 : -1);
                }
            }
        }
        // What is under the pointer, or the chosen day, with its note.
        C.Label {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: dig.shownEntry ? dig.describeDay(dig.shownEntry) : "Scroll to dig deeper · arrows to move · click a day, double-click to open it"
            color: dig.shownEntry ? Theme.text : Theme.muted
            font.pixelSize: Theme.small
            Accessible.name: text
        }
        C.Label {
            Layout.fillWidth: true
            visible: !!dig.shownEntry && !!dig.shownEntry.note
            text: dig.shownEntry && dig.shownEntry.note ? "“" + dig.shownEntry.note + "”" : ""
            elide: Text.ElideRight
            color: Theme.muted
            font.pixelSize: Theme.small
        }
        // The key to the marks. Each has its own shape, so no meaning rests on colour.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gapM
            Repeater {
                model: [{k: "grain", t: "Grain · a signal"}, {k: "vein", t: "Vein · Quiet"}, {k: "fleck", t: "Fleck · order cleared"},
                        {k: "glint", t: "Glint · capture"}, {k: "fossil", t: "Fossil · pinned app"}]
                RowLayout {
                    id: key
                    required property var modelData
                    spacing: 4
                    Item {
                        implicitWidth: 10
                        implicitHeight: 10
                        Rectangle { visible: key.modelData.k === "grain"; anchors.centerIn: parent; width: 5; height: 5; radius: 3; color: Theme.text }
                        Rectangle { visible: key.modelData.k === "vein"; anchors.centerIn: parent; width: 10; height: 3; color: Theme.accent2 }
                        Rectangle { visible: key.modelData.k === "fleck"; anchors.centerIn: parent; width: 6; height: 6; rotation: 45; color: Theme.text }
                        Rectangle { visible: key.modelData.k === "glint"; anchors.centerIn: parent; width: 10; height: 1; color: Theme.warning }
                        Rectangle { visible: key.modelData.k === "glint"; anchors.centerIn: parent; width: 1; height: 10; color: Theme.warning }
                        Rectangle { visible: key.modelData.k === "fossil"; anchors.centerIn: parent; width: 6; height: 6; color: "transparent"; border.width: 1; border.color: Theme.text }
                    }
                    C.Caption { text: key.modelData.t; Layout.fillWidth: false }
                }
            }
            Item { Layout.fillWidth: true }
        }
    }
}
