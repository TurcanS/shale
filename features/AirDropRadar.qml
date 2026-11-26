pragma ComponentBehavior: Bound
import QtQuick
import "../core"
import "../components" as C

// The AirDrop glyph on a round tile; while `live` (looking for devices, or visible to them) accent rings widen out
// from it and fade, one after another. Still rings stand in for them with reduced motion or effects trimmed. Without
// `rings` (a header, where they would spill over the title) only the tile shows that it is live.
Item {
    id: root
    property bool live: false
    property bool rings: true
    property int size: 32
    property color color: Theme.accent
    readonly property bool moving: live && rings && visible && !Theme.reduced && !Theme.lowPower
    implicitWidth: size
    implicitHeight: size
    Repeater {
        model: 3
        Rectangle {
            id: ring
            required property int index
            property real phase: 0
            anchors.centerIn: parent
            width: root.size * (1 + phase * 1.1)
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1.5
            border.color: root.color
            visible: root.live && root.rings
            // Still: two faint rings at fixed steps.
            opacity: root.moving ? 0.55 * (1 - phase) : ring.index < 2 ? 0.22 - ring.index * 0.1 : 0
            Component.onCompleted: if (!root.moving)
                phase = 0.25 + ring.index * 0.35
            SequentialAnimation on phase {
                running: root.moving
                loops: Animation.Infinite
                PauseAnimation {
                    duration: ring.index * 800
                }
                NumberAnimation {
                    from: 0
                    to: 1
                    duration: 2400
                    easing.type: Easing.OutCubic
                }
                PauseAnimation {
                    duration: (2 - ring.index) * 800
                }
                onStopped: ring.phase = 0.25 + ring.index * 0.35
            }
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: root.live ? Theme.accent : Theme.key
        Behavior on color {
            ColorAnimation {
                duration: Theme.fast
            }
        }
        C.Icon {
            anchors.centerIn: parent
            name: "airdrop"
            size: Math.round(root.size * 0.55)
            color: root.live ? Theme.accentInk : Theme.text
        }
    }
}
