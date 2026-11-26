import QtQuick
import "../core"

// A soft fade over the bottom edge of a scrolling view while more lies below it, so a row cut by the edge reads as
// "there is more" rather than as a clipped panel. Anchor it to the view's bottom, over the view.
Item {
    id: root
    // A Flickable (ListView, GridView) or a ScrollView's contentItem.
    property Item flickable: null
    readonly property Flickable target: flickable as Flickable
    // The surface the view sits on.
    property color tone: Theme.caseColor
    implicitHeight: 32
    visible: !!target && target.contentHeight > target.height + 1 && !target.atYEnd
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.tint(root.tone, 0) }
            GradientStop { position: 1; color: root.tone }
        }
    }
}
