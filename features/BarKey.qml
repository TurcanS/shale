import QtQuick
import "../core"
import "../components" as C

// A key on the bar, 28 px tall. Flat keys show a light wash on hover; the status key rests on
// `module`. A key whose panel is open on this screen turns keySelected.
C.Button {
    id: key
    // Whether the item has something to show; the zone hides its slot otherwise.
    property bool shown: true
    property color rest: "transparent"
    labelSize: 13
    implicitHeight: 28
    topPadding: 0
    bottomPadding: 0
    cornerRadius: Theme.radiusKey
    // Panels open out of the key that was pressed (PanelHost takes the mark), and go back into it on closing.
    onPressed: Motion.mark(key)
    // Catching its panel back, the key dips a pixel or two and lights for a moment.
    property real catchT: 1
    transform: Translate {
        y: key.sunk + 1.6 * Math.sin(Math.PI * key.catchT)
    }
    NumberAnimation {
        id: catchAnimation
        target: key
        property: "catchT"
        from: 0
        to: 1
        duration: Motion.ms(190)
    }
    Connections {
        target: Motion
        function onCaught(item) {
            if (item === key)
                catchAnimation.restart();
        }
    }
    foreground: !enabled ? Theme.textFaint : tone === "danger" ? Theme.dangerText : tone === "warning" ? Theme.warning : Theme.text
    background: Rectangle {
        radius: key.cornerRadius
        color: key.selected ? Theme.keySelected : key.rest
        Behavior on color {
            ColorAnimation {
                duration: Theme.fast
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: key.wash
            opacity: key.hovered || key.down || key.visualFocus ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.fast
                }
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Theme.knob
            opacity: 0.12 * Math.sin(Math.PI * key.catchT)
            visible: opacity > 0.001
        }
    }
}
