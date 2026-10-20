pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../core"
import "../core/island.js" as Queue
import "../services"
import "../components" as C

// The capsule grows a card for a few seconds when something live happens: Quiet starting or hovered, a timer in its
// last seconds, a new track, an order cleared. One at a time by importance; a second live thing shows as a small
// bubble beside it. The card opens from the pill's own rectangle, so a reversal needs no special case.
Item {
    id: island
    // Where the pill is, in this item's coordinates; asked for through `rectOf` as the card opens.
    property var rectOf: null
    property rect pill: Qt.rect(0, 0, 0, 0)
    // No expansion while the hub is open or typed into, in presentation, or under the lock.
    property bool blocked: false
    property bool hovered: false
    property real now: Date.now()
    property var queue: []
    readonly property var picked: Queue.pick(queue, now, blocked, hovered)
    readonly property var current: picked.current
    readonly property var bubble: current ? picked.bubble : null
    readonly property alias card: card
    // The last activity shown, kept while the card closes so its content does not vanish mid-fade.
    property var shown: null
    readonly property string kind: shown ? shown.kind : ""
    readonly property int cardWidth: 280
    readonly property int cardHeight: 52
    property real reveal: current ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: island.current ? (Theme.reduced ? 0 : Theme.lowPower ? 160 : 320) : Theme.leave
            easing.type: Easing.OutCubic
        }
    }
    onCurrentChanged: {
        if (current) {
            shown = current;
            if (rectOf)
                pill = rectOf();
        }
    }
    function push(kind, milliseconds, live, hover) {
        now = Date.now();
        queue = Queue.push(queue, {kind: kind, until: milliseconds > 0 ? now + milliseconds : 0, live: live, hover: !!hover});
    }
    // The tick runs only while something is queued or a timer is counting.
    Timer {
        interval: 250
        repeat: true
        running: island.queue.length > 0 || !!Focus.nextTimer || island.reveal > 0
        onTriggered: {
            island.now = Date.now();
            island.queue = Queue.prune(island.queue, island.now);
            const timer = Focus.nextTimer;
            if (!timer) {
                if (island.queue.some(item => item.kind === "timer"))
                    island.queue = Queue.drop(island.queue, "timer");
            } else if (timer.endsAt - island.now <= 10000 && !island.queue.some(item => item.kind === "timer" && item.until === timer.endsAt)) {
                island.queue = Queue.push(island.queue, {kind: "timer", until: timer.endsAt, live: false, hover: false});
            }
        }
    }
    Connections {
        target: Focus
        function onActiveChanged() {
            if (Focus.active)
                island.push("quiet", 3000, true, true);
            else
                island.queue = Queue.drop(island.queue, "quiet");
        }
    }
    Connections {
        target: NowPlaying
        function onTrackChanged() {
            island.push("media", 3000, NowPlaying.playing, false);
        }
        function onPlayingChanged() {
            if (!NowPlaying.playing)
                island.queue = Queue.drop(island.queue, "media");
        }
    }
    Connections {
        target: Day
        function onCleared() {
            island.push("cleared", 1000, false, false);
        }
    }
    Component.onCompleted: if (Focus.active) push("quiet", 0, true, true)
    Rectangle {
        id: card
        readonly property real e: Theme.reduced ? 1 : island.reveal
        readonly property real finalX: Math.max(0, Math.min(island.width - island.cardWidth, island.pill.x + island.pill.width / 2 - island.cardWidth / 2))
        readonly property real finalY: island.pill.y + island.pill.height + 4
        visible: island.reveal > 0.01
        x: Theme.reduced ? finalX : island.pill.x + (finalX - island.pill.x) * e
        y: Theme.reduced ? finalY : island.pill.y + (finalY - island.pill.y) * e
        width: Theme.reduced ? island.cardWidth : island.pill.width + (island.cardWidth - island.pill.width) * e
        height: Theme.reduced ? island.cardHeight : island.pill.height + (island.cardHeight - island.pill.height) * e
        radius: Theme.controlRadius
        color: Theme.panel
        border.width: 1
        border.color: Theme.border
        opacity: Theme.reduced ? island.reveal : Math.min(1, island.reveal * 3)
        // What is live sets the colour of the card's left edge, as an app does on a notification card.
        Rectangle {
            x: 1
            y: 8
            width: 3
            height: parent.height - 16
            radius: 1.5
            color: island.kind === "quiet" ? Theme.accent : island.kind === "timer" ? Theme.accent2 : island.kind === "media" ? Theme.activityApps[1] : Theme.text
            opacity: Math.max(0, (island.reveal - 0.6) / 0.4)
        }
        // A lit top edge and two screws, as on the hub's plates.
        Rectangle {
            x: 10
            y: 1
            width: parent.width - 20
            height: 1
            color: Qt.rgba(1, 1, 1, 0.07)
        }
        Repeater {
            model: 2
            Rectangle {
                required property int index
                x: index ? card.width - 10 : 6
                y: 5
                width: 3
                height: 3
                radius: 1.5
                color: Theme.raised
            }
        }
        // Content fades in after the shape has settled.
        Item {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 14
            anchors.topMargin: 10
            anchors.bottomMargin: 8
            opacity: Math.max(0, (island.reveal - 0.6) / 0.4)
            RowLayout {
                anchors.fill: parent
                spacing: 10
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    C.StationText {
                        text: island.kind === "quiet" ? "Quiet" : island.kind === "timer" ? "Timer"
                            : island.kind === "media" ? "Now playing" : "Cleared"
                    }
                    C.Readout {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.pixelSize: Theme.body + 3
                        color: island.kind === "quiet" ? Theme.accent : Theme.text
                        text: {
                            const kind = island.kind;
                            if (kind === "quiet")
                                return Focus.clockText(Focus.remainingSeconds);
                            if (kind === "timer")
                                return Focus.nextTimer ? Focus.clockText(Math.max(0, Math.ceil((Focus.nextTimer.endsAt - island.now) / 1000))) + (Focus.nextTimer.label ? "  " + Focus.nextTimer.label : "") : "Done";
                            if (kind === "media")
                                return NowPlaying.player ? (NowPlaying.player.trackTitle || "") + (NowPlaying.player.trackArtist ? " · " + NowPlaying.player.trackArtist : "") : "";
                            return "Order cleared";
                        }
                    }
                }
                C.StationKey {
                    visible: island.kind === "quiet" || island.kind === "timer"
                    Layout.fillWidth: false
                    text: island.kind === "quiet" ? "End" : "Cancel"
                    onClicked: {
                        if (island.kind === "quiet") {
                            Focus.end(true);
                        } else if (Focus.nextTimer) {
                            Focus.cancelTimer(Focus.nextTimer.id);
                        }
                    }
                }
                C.StationKey {
                    visible: island.kind === "media" && !!NowPlaying.player
                    Layout.fillWidth: false
                    text: NowPlaying.playing ? "Pause" : "Play"
                    onClicked: NowPlaying.player.togglePlaying()
                }
                C.StationKey {
                    visible: island.kind === "media" && !!NowPlaying.player
                    Layout.fillWidth: false
                    text: "Next"
                    onClicked: NowPlaying.player.next()
                }
            }
        }
    }
    // The second live thing, as a small round bubble beside the card.
    Rectangle {
        visible: !!island.bubble && island.reveal > 0.01
        x: card.x + card.width + 6
        y: card.y
        width: 28
        height: 28
        radius: 14
        color: Theme.panel
        border.width: 1
        border.color: Theme.border
        opacity: island.reveal
        C.Readout {
            anchors.centerIn: parent
            font.pixelSize: Theme.caption
            text: island.bubble ? (island.bubble.kind === "quiet" ? "Q" : island.bubble.kind === "media" ? "♪" : island.bubble.kind === "timer" ? "T" : "") : ""
        }
    }
}
