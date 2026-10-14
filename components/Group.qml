import QtQuick
import QtQuick.Layouts
import "../core"

// Settings rows on one card, divided by hairlines. Toggles placed here draw flat and light up on hover only.
Card {
    id: root
    default property alias rows: column.data
    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + 8
    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 4
        spacing: 0
    }
    // Rows that take up space; a Repeater is a visible child too, but has no size.
    readonly property var shown: column.visibleChildren.filter(item => item.height > 0)
    // Hairlines between visible rows; drawn over the gaps, so rows keep their own hover shape.
    Repeater {
        model: Math.max(0, root.shown.length - 1)
        Rectangle {
            required property int index
            readonly property Item above: root.shown[index] || null
            visible: !!above
            x: 16
            width: root.width - 32
            height: 1
            y: above ? column.y + above.y + above.height : 0
            color: Theme.border
            opacity: 0.6
        }
    }
}
