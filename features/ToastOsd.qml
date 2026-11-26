import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components" as C

// Levels (volume, brightness) as a round pill with a slim bar and the value; everything else (microphone,
// keyboard layout, Do not disturb, countdowns) as a small card with a title and what it is about.
PanelWindow {
    id: osdWindow
    // Whether this window's screen is the one toasts show on now.
    property bool target: false
    readonly property bool level: ShellState.osdValue >= 0
    readonly property bool volume: ShellState.osdGlyph === "volume" || ShellState.osdGlyph === "mute"
    // "Muted · Microphone" → Muted over Microphone; the older one-line labels get the same shape.
    readonly property var card: {
        const label = ShellState.osdLabel;
        const dnd = /^Do not disturb (on|off)$/.exec(label);
        if (dnd)
            return {title: dnd[1] === "on" ? "On" : "Off", subtitle: "Do not disturb"};
        const countdown = /^Screenshot in (\d+)$/.exec(label);
        if (countdown)
            return {title: "In " + countdown[1], subtitle: "Screenshot"};
        const parts = label.split(" · ");
        return {title: parts[0], subtitle: parts.slice(1).join(" · ")};
    }
    // Something switched on (Do not disturb): a light tile with dark ink.
    readonly property bool lit: ShellState.osdGlyph === "bell-off"
    // Transparent room for the shadow; nothing here takes clicks.
    readonly property int room: 40
    readonly property bool showing: osdWindow.target && ShellState.osdVisible && !ShellState.locked
    property real reveal: showing ? 1 : 0
    // Lively and Playful: it extrudes out of the bottom edge and seats; it goes back quickly. Calm keeps the fade.
    Behavior on reveal {
        NumberAnimation {
            duration: Motion.calm || !osdWindow.showing ? Theme.fast : Motion.ms(300)
            easing.type: Motion.calm || !osdWindow.showing ? Easing.OutCubic : Easing.BezierSpline
            easing.bezierCurve: Motion.seatCurve(Motion.ov(0.9))
        }
    }
    // The level as a VU needle: it swings to a new value. Pushed past 0 or 100 it gives against the stop and comes
    // back (peg, toward pegSide).
    property real shownLevel: Math.max(0, Math.min(1, ShellState.osdValue))
    C.Ballistic on shownLevel {}
    property real lastValue: -1
    property real peg: 0
    property int pegSide: 1
    SequentialAnimation {
        id: pegging
        NumberAnimation { target: osdWindow; property: "peg"; to: 1; duration: Motion.ms(60); easing.type: Easing.OutQuad }
        NumberAnimation { target: osdWindow; property: "peg"; to: 0; duration: Motion.ms(320); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.seatCurve(Motion.ov(1.2)) }
    }
    // Switching between the level pill and the card swaps the face like a module.
    property real swapScale: 1
    onLevelChanged: if (reveal > 0.5 && !Motion.calm) swapping.restart()
    NumberAnimation {
        id: swapping
        target: osdWindow
        property: "swapScale"
        from: 0.88
        to: 1
        duration: Motion.ms(300)
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.seatCurve(Motion.ov(1))
    }
    anchors {
        bottom: true
    }
    margins.bottom: (ShellState.toast !== "" ? 92 : 64) - room
    implicitWidth: (level ? 320 : 196) + 2 * room
    implicitHeight: (level ? 56 : 124) + 2 * room
    visible: osdWindow.target && !ShellState.locked && reveal > 0
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shale-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    // Nothing here is clickable, so clicks reach the windows underneath.
    mask: Region {}
    Item {
        id: osd
        anchors.fill: parent
        anchors.margins: osdWindow.room
        opacity: Math.min(1, osdWindow.reveal * (Motion.calm ? 1 : 2))
        transform: [
            Scale {
                origin.x: osd.width / 2
                origin.y: Motion.calm ? osd.height / 2 : osd.height
                xScale: (Theme.reduced ? 1 : Motion.calm ? 0.94 + 0.06 * osdWindow.reveal : Motion.lerp(0.86, 1, Math.min(1, osdWindow.reveal)))
                        * (1 + 0.05 * osdWindow.peg * Motion.travel) * osdWindow.swapScale
                yScale: (Theme.reduced ? 1 : Motion.calm ? 0.94 + 0.06 * osdWindow.reveal : Motion.lerp(0.3, 1, osdWindow.reveal)) * osdWindow.swapScale
            },
            Translate {
                x: osdWindow.pegSide * 4 * osdWindow.peg * Motion.travel
                y: Theme.reduced ? 0 : Motion.calm ? (1 - osdWindow.reveal) * 6 : (1 - osdWindow.reveal) * 22 * Motion.travel
            }
        ]
        RectangularShadow {
            anchors.fill: osdCase
            visible: !Theme.lowPower
            radius: osdCase.radius
            blur: 30
            offset.y: 14
            color: Qt.rgba(0, 0, 0, 0.45)
        }
        Rectangle {
            id: osdCase
            anchors.fill: parent
            radius: osdWindow.level ? height / 2 : 24
            color: Theme.tint(Theme.module, 0.92)
            border.width: 1
            border.color: Theme.cardEdge
        }
        // The level pill: icon disc, slim bar, value.
        RowLayout {
            visible: osdWindow.level
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 16
            spacing: Theme.gapM
            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: 18
                color: ShellState.osdMuted ? Theme.dangerSoft : osdWindow.volume ? Theme.tint(Theme.accent, 0.16) : Theme.key
                Behavior on color { ColorAnimation { duration: Theme.fast } }
                C.Icon {
                    id: osdIcon
                    anchors.centerIn: parent
                    name: ShellState.osdGlyph
                    color: ShellState.osdMuted ? Theme.dangerText : osdWindow.volume ? Theme.accent : Theme.text
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                radius: 3
                color: Theme.key
                RectangularShadow {
                    anchors.fill: levelFill
                    visible: osdWindow.volume && !ShellState.osdMuted && !Theme.lowPower && levelFill.width > 0
                    radius: levelFill.radius
                    blur: 12
                    color: Theme.accentGlow
                }
                Rectangle {
                    id: levelFill
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * Math.max(0, Math.min(1, osdWindow.shownLevel))
                    radius: 3
                    // Volume runs from the accent wash to the accent; brightness is light; muted keeps the real
                    // level visible, just quieter.
                    color: ShellState.osdMuted ? Theme.textFaint : Theme.text
                    gradient: osdWindow.volume && !ShellState.osdMuted ? volumeGradient : undefined
                    Gradient {
                        id: volumeGradient
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Theme.tint(Theme.accent, 0.16) }
                        GradientStop { position: 1; color: Theme.accent }
                    }
                }
            }
            C.Label {
                text: Math.round(ShellState.osdValue * 100)
                color: ShellState.osdMuted ? Theme.textDim : Theme.text
                font.pixelSize: 14
                font.weight: 650
                font.features: ({"tnum": 1})
                horizontalAlignment: Text.AlignRight
                Layout.preferredWidth: 30
            }
        }
        // The card: tile, then the title and what it is about at the bottom.
        ColumnLayout {
            visible: !osdWindow.level
            anchors.fill: parent
            anchors.margins: 16
            spacing: 6
            Rectangle {
                id: cardTile
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 13
                color: ShellState.osdMuted ? Theme.dangerSoft : osdWindow.lit ? Theme.mix(Theme.knob, Theme.textSecondary, 0.35) : Theme.key
                C.Icon {
                    id: cardIcon
                    anchors.centerIn: parent
                    name: ShellState.osdGlyph
                    color: ShellState.osdMuted ? Theme.dangerText : osdWindow.lit ? Theme.accentInk : Theme.text
                }
            }
            Item {
                Layout.fillHeight: true
            }
            C.Label {
                text: osdWindow.card.title
                font.pixelSize: 16
                font.weight: 650
                Layout.fillWidth: true
            }
            C.Label {
                visible: text !== ""
                text: osdWindow.card.subtitle
                color: Theme.textDim
                font.pixelSize: 12
                Layout.fillWidth: true
            }
        }
        // A small bump on every change confirms the key press even at 0% or 100%.
        SequentialAnimation {
            id: bump
            property Item icon: osdWindow.level ? osdIcon : cardIcon
            NumberAnimation { target: bump.icon; property: "scale"; to: 1.2; duration: 70; easing.type: Easing.OutQuad }
            NumberAnimation { target: bump.icon; property: "scale"; to: 1; duration: 160; easing.type: Easing.OutBack }
        }
        Connections {
            target: ShellState
            function onOsdSerialChanged() {
                if (!Theme.reduced && !Theme.lowPower && osdWindow.reveal > 0)
                    bump.restart();
                // Pushed against an end it is already at: the needle pegs.
                const value = ShellState.osdValue;
                if (osdWindow.level && !Motion.calm && osdWindow.reveal > 0.5 && value === osdWindow.lastValue && (value >= 1 || value <= 0)) {
                    osdWindow.pegSide = value >= 1 ? 1 : -1;
                    pegging.restart();
                }
                osdWindow.lastValue = value;
            }
        }
    }
}
