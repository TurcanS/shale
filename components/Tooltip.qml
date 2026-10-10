import QtQuick
import Quickshell
import "../core"

// One hint popup shared by a window's buttons (set Button.tooltip), so the bar's height can't clip it.
// It appears once the pointer rests on a button, and moves straight to a neighbour while it's up.
PopupWindow {
    id: root
    property Button target: null
    property Button pending: null
    property bool shown: false
    // Set briefly after a tooltip closes because the pointer left, so the next button needs no wait.
    property bool warm: false
    readonly property string text: target ? target.hint : ""
    readonly property bool live: shown && !!target && target.visible && text !== "" && !ShellState.locked
    property real reveal: live ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.live ? Theme.fast : Theme.leave
            easing.type: Easing.OutCubic
        }
    }
    function show(item) {
        pending = item;
        if (warm || shown) {
            delay.stop();
            open();
        } else {
            delay.restart();
        }
    }
    function hide(item, pressed) {
        if (pending === item) {
            delay.stop();
            pending = null;
        }
        if (target !== item)
            return;
        warm = shown && !pressed;
        if (warm)
            cooling.restart();
        shown = false;
    }
    function open() {
        if (!pending)
            return;
        target = pending;
        anchor.item = pending;
        anchor.rect.width = pending.width;
        anchor.rect.height = pending.height + 6;
        shown = true;
    }
    Timer {
        id: delay
        interval: 500
        onTriggered: root.open()
    }
    Timer {
        id: cooling
        interval: 300
        onTriggered: root.warm = false
    }
    anchor.rect.x: 0
    anchor.rect.y: 0
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    implicitWidth: Math.min(360, label.implicitWidth + 20)
    implicitHeight: label.implicitHeight + 12
    visible: reveal > 0
    color: "transparent"
    // A hint never takes the pointer from what it describes.
    mask: Region {}
    Rectangle {
        anchors.fill: parent
        radius: 8
        color: Theme.raised
        border.width: 1
        border.color: Theme.border
        opacity: root.reveal
        transform: Translate { y: Theme.reduced ? 0 : (1 - root.reveal) * -4 }
        Label {
            id: label
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            text: root.text
            font.pixelSize: Theme.small
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
