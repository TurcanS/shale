import QtQuick
import "../core"

// An instrument plate: a screwed-on panel with its name stamped in the top left.
Piece {
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
