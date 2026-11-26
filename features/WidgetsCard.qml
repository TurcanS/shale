import QtQuick
import QtQuick.Effects
import "../core"

// One desktop widget card: the case colour, a little see-through, with a hairline edge and a long soft shadow
// (skipped when effects are trimmed). Cards are 214 px tall; each sets its width and padding. A card with `panel`
// opens that panel on its output when clicked where it has no control of its own.
Item {
    id: root
    default property alias content: body.data
    property string outputName: ""
    property string panel: ""
    property int padding: 16
    implicitHeight: 214
    height: 214
    RectangularShadow {
        anchors.fill: parent
        visible: !Theme.lowPower
        radius: Theme.radiusCase
        blur: 40
        offset.y: 20
        color: Qt.rgba(0, 0, 0, 0.35)
    }
    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusCase
        color: Theme.tint(Theme.caseColor, 0.78)
        border.width: 1
        border.color: Theme.cardEdge
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.panel !== ""
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: ShellState.open(root.panel, root.outputName)
    }
    Item {
        id: body
        anchors.fill: parent
        anchors.margins: root.padding
    }
}
