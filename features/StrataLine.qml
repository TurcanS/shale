pragma ComponentBehavior: Bound
import QtQuick
import "../core"
import "../core/line.js" as LineMath
import "../services"
import "../components" as C

// Today along the bottom of the Day pill, midnight to midnight: what was recorded to the left of the Front, what is
// planned to the right. It grows upward inside the pill while the pointer is on it, so nothing in the bar moves.
Item {
    id: line
    // The bar's width and whether it is on screen; the Line waits while it is hidden.
    property bool onScreen: true
    property bool open: false
    readonly property bool tracking: ShellState.setting("activityTracking", "ask") === "on"
    readonly property bool shown: onScreen && !ShellState.presentation && !ShellState.locked
    readonly property int restHeight: 4
    readonly property int hoverHeight: 9
    // Space either side so the Line stays inside the pill's rounded ends.
    readonly property int inset: 7
    readonly property real span: width - 2 * inset
    property real now: Date.now()
    property var bounds: LineMath.dayBounds(now)
    property var activity: null
    readonly property var segments: activity && activity.date === Day.today() ? activity.segments : []
    readonly property var ranking: LineMath.ranking(activity ? activity.apps || [] : [])
    readonly property var bands: LineMath.bands(segments, bounds.start, bounds.end, now, span)
    readonly property var marks: LineMath.marks(Day.items, Day.todos, bounds.start, bounds.end, span)
    // Recorded time, added up as Activity's day view does (active and watching).
    readonly property var totals: LineMath.totals(segments, now)
    readonly property real recorded: totals.active + totals.watching
    readonly property string front: LineMath.frontState(segments, now)
    readonly property bool hovered: hover.hovered
    // The Line has grown while the pointer is on it, and keeps its size while it points at something.
    readonly property bool grown: hovered && !open
    visible: shown
    height: restHeight + (hoverHeight - restHeight) * grow
    property real grow: grown ? 1 : 0
    Behavior on grow {
        NumberAnimation {
            duration: Theme.fast
            easing.type: Easing.OutCubic
        }
    }
    // The hit strip is taller than the resting Line so it is easy to find; clicks fall through to the pill.
    Item {
        id: hit
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.max(8, line.height)
        HoverHandler {
            id: hover
            cursorShape: Qt.PointingHandCursor
        }
    }
    function load() {
        if (!line.shown || !line.tracking || !Backend.ready)
            return;
        const day = Day.today();
        Backend.request("activity.day", {date: day}, (result, error) => {
            if (!error && day === Day.today())
                line.activity = result;
        });
    }
    function tick() {
        now = Date.now();
        if (now >= bounds.end || now < bounds.start)
            bounds = LineMath.dayBounds(now);
        load();
    }
    // 30 s, as Activity's own refresh; a new day starts an empty Line on the same tick.
    Timer {
        interval: 30000
        repeat: true
        running: line.shown
        triggeredOnStart: true
        onTriggered: line.tick()
    }
    onShownChanged: if (shown) tick()
    onTrackingChanged: if (tracking) tick(); else activity = null
    Connections {
        target: Backend
        function onReadyChanged() {
            line.load();
        }
    }
    function bandColor(band) {
        if (band.state === "idle")
            return Theme.activityIdle;
        const index = line.ranking.indexOf(band.app);
        const mineral = Theme.activityApps[index >= 0 ? index : Theme.activityApps.length - 1];
        return band.state === "watching" ? Theme.mix(mineral, Theme.warning, 0.35) : mineral;
    }
    // Open rock: the part of the day still to come.
    Item {
        id: strip
        x: line.inset
        width: line.span
        anchors.bottom: parent.bottom
        height: line.height
        Rectangle {
            anchors.fill: parent
            radius: 2
            color: Theme.raised
            opacity: 0.55
        }
        // Faint hour notches in the open rock, always there, so the scale reads before the pointer arrives.
        Repeater {
            model: 7
            Rectangle {
                required property int index
                x: index / 6 * strip.width - 0.5
                y: -3
                width: 1
                height: 3
                color: Theme.text
                opacity: 0.22
            }
        }
        Repeater {
            model: line.bands
            Rectangle {
                required property var modelData
                x: modelData.x
                width: modelData.width
                height: parent.height
                radius: 1
                color: line.bandColor(modelData)
            }
        }
        // Hour ticks, and labels every third hour, while the Line is grown.
        Repeater {
            model: 25
            Item {
                id: tick
                required property int index
                x: index / 24 * strip.width
                height: strip.height
                opacity: line.grow
                visible: line.grow > 0.02
                Rectangle {
                    width: 1
                    height: tick.index % 3 ? 3 : 6
                    anchors.bottom: parent.bottom
                    color: Theme.text
                    opacity: 0.45
                }
                C.StationText {
                    visible: tick.index % 3 === 0 && tick.index > 0 && tick.index < 24
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    text: String(tick.index).padStart(2, "0")
                    font.pixelSize: 8
                    font.letterSpacing: 0.6
                }
            }
        }
        // Flecks (done), ticks (timed to-dos) and stones (reminders).
        Repeater {
            model: line.marks
            Rectangle {
                required property var modelData
                readonly property bool stone: modelData.kind === "stone"
                readonly property bool fleck: modelData.kind === "fleck"
                x: modelData.x - width / 2
                y: stone || fleck ? Math.max(0, strip.height - 9) : strip.height - 6
                width: stone || fleck ? 7 : 2
                height: stone || fleck ? 7 : 6
                rotation: stone || fleck ? 45 : 0
                color: fleck ? Theme.text : stone ? (modelData.fired ? Theme.accent2 : "transparent") : Theme.accent2
                border.width: stone ? 1 : 0
                border.color: Theme.accent2
            }
        }
        // The Front: bright while active, amber-leaning while watching, dim while idle.
        Rectangle {
            visible: !Theme.lowPower && line.front !== "idle"
            x: front.x - 5
            width: 13
            height: parent.height + 8
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -2
            radius: 6
            color: line.front === "watching" ? Theme.warning : Theme.accent
            opacity: 0.28 * front.breath
        }
        Rectangle {
            id: front
            x: Math.min(strip.width, LineMath.position(line.now, line.bounds.start, line.bounds.end, strip.width)) - width / 2
            width: 3
            height: parent.height + 2
            anchors.bottom: parent.bottom
            radius: 1
            gradient: Gradient {
                GradientStop { position: 0; color: line.front === "watching" ? Theme.warning : Theme.accent }
                GradientStop { position: 1; color: line.front === "watching" ? Theme.warning : Theme.accent2 }
            }
            opacity: (line.front === "idle" ? 0.4 : 1) * breath
            property real breath: 1
            SequentialAnimation on breath {
                running: line.shown && line.front === "active" && !Theme.reduced && !Theme.lowPower
                loops: Animation.Infinite
                onRunningChanged: if (!running) front.breath = 1
                NumberAnimation { to: 0.6; duration: 1400; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 1400; easing.type: Easing.InOutSine }
            }
            Behavior on opacity {
                NumberAnimation { duration: Theme.enter }
            }
        }
    }
    // What is under the pointer: the app and how long, or the item and its time. Drawn below the bar, which the
    // window leaves transparent; it is a hint only, so it takes no input.
    readonly property var pointed: {
        if (!hovered || !hover.point.position)
            return null;
        const x = hover.point.position.x - inset;
        const mark = LineMath.markAt(marks, x);
        if (mark)
            return {x: mark.x, text: mark.text + "  ·  " + Qt.formatDateTime(new Date(mark.at), ShellState.timeFormat)};
        const band = LineMath.bandAt(bands, x);
        if (!band)
            return null;
        return {x: band.x + band.width / 2, text: (band.state === "idle" ? "Idle" : band.app) + "  ·  "
            + LineMath.span(band.end - band.start) + (band.state === "watching" ? " watching" : "")};
    }
    Rectangle {
        id: tip
        visible: !!line.pointed && line.grown
        x: Math.max(0, Math.min(line.width - width, line.inset + (line.pointed ? line.pointed.x : 0) - width / 2))
        y: line.height + 4
        width: tipText.implicitWidth + 16
        height: tipText.implicitHeight + 10
        radius: Theme.controlRadius
        color: Theme.panel
        border.width: 1
        border.color: Theme.border
        C.Label {
            id: tipText
            anchors.centerIn: parent
            text: line.pointed ? line.pointed.text : ""
            font.pixelSize: Theme.caption
        }
    }
}
