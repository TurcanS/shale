pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../core"
import "../core/station.js" as Station
import "../core/notes.js" as Notes
import "../services"
import "../components" as C

// The station lock screen: the particle clock, unchanged, with today's drum running behind it and the station's
// readings in the corner (the next event, the open orders, an operator note). Anyone at the screen can read it, so
// titles stay hidden unless the lockTitles setting allows them. Unlocking opens it along the Front (LockTransition).
LockParticles {
    id: root
    property real now: Date.now()
    property var activity: null
    readonly property bool recording: ShellState.setting("activityTracking", "ask") === "on"
    readonly property bool titles: ShellState.setting("lockTitles", false)
    readonly property bool stationWords: ShellState.setting("stationWords", true)
    readonly property real dayStart: new Date(new Date(now).getFullYear(), new Date(now).getMonth(), new Date(now).getDate()).getTime()
    readonly property real dayEnd: new Date(new Date(now).getFullYear(), new Date(now).getMonth(), new Date(now).getDate() + 1).getTime()
    // The same events the hub's drum marks: reminders still to come and running timers.
    readonly property var events: {
        const pending = item => item.kind === "reminder" && !item.doneAt && !(item.firedAt && item.firedAt >= item.at);
        const reminders = Day.items.filter(pending);
        const next = Day.nextItem;
        if (next && pending(next) && !reminders.some(item => item.id === next.id))
            reminders.push(next);
        const timers = Focus.timers.map(timer => ({at: timer.endsAt, text: timer.label || Focus.minutesText(timer.seconds) + " timer"}));
        return reminders.concat(timers).sort((a, b) => a.at - b.at).slice(0, 5);
    }
    readonly property var readings: Station.lockReadings(events, Day.todos.length, now, titles, stationWords)
    // Picked once per lock: the screen is made anew each time the session locks.
    readonly property string note: ShellState.setting("operatorNotes", true) && !ShellState.presentation
                                   ? Notes.pick(ShellState.setting("operatorLines", []), Date.now(), 1) : ""

    function loadActivity() {
        if (recording)
            Backend.request("activity.day", {date: Day.today()}, (result, error) => root.activityLoaded(result, error));
    }
    function activityLoaded(result, error) {
        if (!error)
            activity = result;
    }
    // A named function rather than code in the handler: qmllint skips a whole file whose handlers declare constants.
    function lowerWallpaper(drum) {
        for (let i = 0; i < children.length; i++) {
            const child = children[i];
            if (child !== drum && child.darken !== undefined && child.sharp !== undefined) {
                child.z = -2;
                return;
            }
        }
    }
    Component.onCompleted: loadActivity()
    // The drum moves on once a minute, as in the hub.
    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: {
            root.now = Date.now();
            root.loadActivity();
        }
    }

    // The drum: the whole width, so its stylus is the Front the screen splits along on unlock. It sits just above the
    // wallpaper, under the dust and the clock; it fades with the blur, so the last frame is the plain wallpaper the
    // reveal starts from.
    Item {
        id: drumLayer
        x: 0
        width: root.width
        height: Math.round(root.digitHeight * 1.5)
        y: Math.round(root.clockCy - height / 2)
        opacity: 0.55 * root.veil
        // The particle screen's own children all sit at z 0 in their order, the wallpaper first. QML cannot insert an
        // item among them, so the wallpaper goes one step further down instead, and the drum between it and the rest.
        z: -1
        Component.onCompleted: root.lowerWallpaper(drumLayer)
        Canvas {
            id: drum
            anchors.fill: parent
            anchors.bottomMargin: 18
            readonly property var inputs: [root.activity, root.now, root.readings, root.recording, Theme.accent, Theme.lowPower, width, height]
            onInputsChanged: requestPaint()
            onPaint: Station.paint(getContext("2d"), {
                width: width,
                height: height,
                segments: root.recording && root.activity ? root.activity.segments : [],
                dayStart: root.dayStart,
                dayEnd: root.dayEnd,
                now: root.now,
                items: root.readings.items,
                blocks: [],
                blockFill: "transparent",
                accent: Theme.accent,
                grid: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.1),
                ahead: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3),
                event: Theme.accent2,
                stylus: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.5),
                glow: !Theme.lowPower,
                font: "11px \"" + Theme.instrument + "\""
            })
        }
        Repeater {
            model: 9
            Text {
                required property int index
                x: Math.round(index / 8 * drum.width) - (index === 8 ? implicitWidth + 6 : index ? implicitWidth / 2 : -6)
                anchors.bottom: parent.bottom
                text: String(index * 3).padStart(2, "0")
                font.family: Theme.instrument
                font.pixelSize: Theme.caption
                color: Theme.muted
            }
        }
    }

    // The station's readings, opposite the status corner.
    ColumnLayout {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 28
        // Slides down 20 px into place as the chrome comes in, as the status corner opposite does.
        anchors.topMargin: 28 - (1 - root.chrome) * 20
        width: Math.min(420, root.width / 2 - 56)
        spacing: 6
        opacity: root.chrome * (1 - 0.4 * root.idleness)
        C.StationText {
            text: ShellState.word("unattended")
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.95)
            Accessible.name: "Locked"
        }
        C.Label {
            visible: text !== ""
            text: root.readings.next
            color: Theme.accent2
            font.family: Theme.instrument
            font.pixelSize: Theme.small
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        C.Label {
            text: root.readings.open
            color: Theme.text
            font.family: Theme.instrument
            font.pixelSize: Theme.small
            Layout.fillWidth: true
        }
        C.Label {
            visible: text !== ""
            text: root.note
            color: Theme.muted
            font.pixelSize: Theme.small
            font.italic: true
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Layout.topMargin: 6
        }
    }
}
