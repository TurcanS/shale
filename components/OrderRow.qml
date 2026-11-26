import QtQuick
import QtQuick.Layouts
import "../core"
import "." as C

// One entry of an ordered list on a settings group: a drag handle, its name and what it shows, keys to move it earlier
// or later, then its show switch. Dragging the handle lifts the row and moves it with the pointer; the page reads
// where it is (a DropLine does) and decides where it lands when it is dropped.
Item {
    id: root
    // The page's name for the entry; DropLine finds rows by it.
    property string itemId: ""
    property string label: ""
    property string description: ""
    // The entry's own icon, after the handle.
    property string glyph: ""
    property bool shown: true
    // Always shown: the switch stays on.
    property bool locked: false
    property bool canEarlier: true
    property bool canLater: true
    property bool draggable: true
    // Words for the earlier and later keys ("Move Clock earlier").
    property string earlierWord: "earlier"
    property string laterWord: "later"
    property int labelWidth: 150
    property real dragOffset: 0
    readonly property bool dragging: handle.moving
    signal moved(int step)
    signal toggled()
    signal dragStarted()
    signal dropped()
    Layout.fillWidth: true
    implicitHeight: Math.max(46, entry.implicitHeight + 12)
    z: dragging ? 2 : 0
    Accessible.role: Accessible.Grouping
    Accessible.name: label
    Accessible.description: description
    transform: Translate { y: root.dragOffset }
    Behavior on dragOffset {
        enabled: !root.dragging
        NumberAnimation {
            duration: Theme.fast
            easing.type: Easing.OutCubic
        }
    }
    // Near the top or bottom of the scrolling page, a dragged row scrolls it, faster the closer it gets, so a row can
    // go past what is on screen without the arrow keys. The row stays under the pointer as the page moves.
    property Flickable scroller: null
    function findScroller() {
        for (let item = parent; item; item = item.parent)
            if (item.flicking !== undefined && item.contentHeight > item.height)
                return item;
        return null;
    }
    onDraggingChanged: scroller = dragging ? findScroller() : null
    Timer {
        interval: 16
        repeat: true
        running: root.dragging && !!root.scroller
        onTriggered: {
            const view = root.scroller;
            const middle = root.mapToItem(view, 0, root.height / 2).y;
            const edge = 56;
            const speed = middle < edge ? -(edge - middle) / 4 : middle > view.height - edge ? (middle - view.height + edge) / 4 : 0;
            const before = view.contentY;
            view.contentY = Math.max(0, Math.min(view.contentHeight - view.height, view.contentY + Math.max(-14, Math.min(14, speed))));
            const moved = view.contentY - before;
            if (moved) {
                handle.startY -= moved;
                root.dragOffset += moved;
            }
        }
    }
    // The lifted row covers the ones it passes over.
    Rectangle {
        anchors.fill: parent
        visible: root.dragging
        radius: Theme.radiusCard + 2
        color: Theme.keySelected
        border.width: 1
        border.color: Theme.edge
    }
    RowLayout {
        id: entry
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: Theme.gapM
        Item {
            implicitWidth: 18
            implicitHeight: 28
            Layout.rightMargin: -Theme.gapXs
            C.Icon {
                anchors.centerIn: parent
                name: "grip"
                size: 14
                color: handle.containsMouse || root.dragging ? Theme.textDim : Theme.textFaint
                opacity: root.draggable ? 1 : 0.35
            }
            MouseArea {
                id: handle
                // True once the pointer has moved far enough to count as a drag rather than a click.
                property bool moving: false
                property real startY: 0
                anchors.fill: parent
                anchors.margins: -4
                enabled: root.draggable
                hoverEnabled: true
                preventStealing: true
                cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                // Measured in the parent, which doesn't move with the row.
                function pointer(mouse) {
                    return mapToItem(root.parent, mouse.x, mouse.y).y;
                }
                onPressed: mouse => startY = pointer(mouse)
                onPositionChanged: mouse => {
                    if (!pressed)
                        return;
                    const offset = pointer(mouse) - startY;
                    if (!moving && Math.abs(offset) > 3) {
                        moving = true;
                        root.dragStarted();
                    }
                    if (moving)
                        root.dragOffset = offset;
                }
                function finish(drop) {
                    if (!moving)
                        return;
                    if (drop)
                        root.dropped();
                    moving = false;
                    root.dragOffset = 0;
                }
                onReleased: finish(true)
                onCanceled: finish(false)
            }
        }
        C.Icon {
            visible: root.glyph !== ""
            name: root.glyph
            size: 16
            color: root.shown ? Theme.textDim : Theme.textFaint
        }
        C.Label {
            text: root.label
            color: root.shown ? Theme.text : Theme.textFaint
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            Layout.preferredWidth: root.labelWidth
        }
        C.Label {
            text: root.description
            color: Theme.textDim
            font.pixelSize: Theme.small
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            Layout.fillWidth: true
            Layout.minimumWidth: 0
        }
        C.Button {
            glyph: "chevron"
            rotation: -90
            cornerRadius: 8
            enabled: root.canEarlier
            hint: "Move " + root.label + " " + root.earlierWord
            implicitWidth: 28
            implicitHeight: 28
            onClicked: root.moved(-1)
        }
        C.Button {
            glyph: "chevron"
            rotation: 90
            cornerRadius: 8
            enabled: root.canLater
            hint: "Move " + root.label + " " + root.laterWord
            implicitWidth: 28
            implicitHeight: 28
            onClicked: root.moved(1)
        }
        C.Switch {
            Layout.leftMargin: Theme.gapXs
            enabled: !root.locked
            selected: root.shown
            hint: root.locked ? root.label + " is always shown" : "Show " + root.label
            onClicked: root.toggled()
        }
    }
}
