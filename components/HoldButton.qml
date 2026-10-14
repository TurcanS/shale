import "../core"
import "." as C
import QtQuick
import QtQuick.Layouts

C.Button {
    id: root

    property string description: ""
    property bool destructive: false
    property bool armed: true
    property bool triggered: false
    property real progress: 0
    property int delay: 1400
    property double startedAt: 0

    signal confirmed()

    onPressed: {
        progress = 0;
        startedAt = Date.now();
        holdTimer.restart();
    }
    onReleased: cancelHold()
    onDownChanged: if (!down) cancelHold()
    function cancelHold() {
        holdTimer.stop();
        progress = 0;
    }

    glyph: "power"
    implicitHeight: Math.max(68, holdContent.implicitHeight + topPadding + bottomPadding + 6)
    implicitWidth: 240
    padding: Theme.gapL
    topPadding: Theme.gapM
    bottomPadding: 18
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    enabled: armed && !triggered
    Accessible.name: "Hold to " + text.toLowerCase()
    Accessible.description: "Hold for 1.4 seconds. Release early to cancel."
    onVisibleChanged: {
        if (!visible) {
            cancelHold();
        }
    }
    onEnabledChanged: {
        if (!enabled) {
            cancelHold();
        }
    }
    onActiveFocusChanged: {
        if (!activeFocus) {
            cancelHold();
        }
    }
    onCanceled: cancelHold()
    Keys.onEscapePressed: (event) => {
        cancelHold();
        event.accepted = false;
    }
    Timer {
        id: holdTimer
        interval: 16
        repeat: true
        onTriggered: {
            if (!root.enabled || !root.visible || !root.down || !root.pressed || !root.activeFocus) {
                root.cancelHold();
                return;
            }
            root.progress = Math.min(1, (Date.now() - root.startedAt) / root.delay);
            if (root.progress >= 1) {
                stop();
                root.triggered = true;
                root.confirmed();
            }
        }
    }

    background: Rectangle {
        radius: Theme.controlRadius
        color: root.hovered || root.visualFocus || root.down ? Theme.hover : Theme.surface

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Theme.gapM
            height: 3
            radius: 1.5
            color: Theme.raised

            Rectangle {
                width: parent.width * root.progress
                height: parent.height
                radius: 1.5
                color: root.destructive ? Theme.danger : Theme.text
            }

        }

        Behavior on color {
            ColorAnimation {
                duration: Theme.fast
            }

        }

    }

    contentItem: RowLayout {

        // Named: contentItem is created late, and a binding through it doesn't see later size changes.

        id: holdContent
        spacing: Theme.gapM

        C.Icon {
            name: root.glyph
            size: Theme.iconLarge
            color: root.destructive ? Theme.danger : Theme.text
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.gapXs

            C.Label {
                text: root.text
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }

            C.Label {
                visible: root.description !== ""
                text: root.description
                color: Theme.muted
                font.pixelSize: Theme.small
                Layout.fillWidth: true
            }

        }

        C.Label {
            visible: root.down
            text: Math.max(0, (root.delay * (1 - root.progress)) / 1000).toFixed(1) + "s"
            font.pixelSize: Theme.small
            font.family: Theme.mono
            color: root.destructive ? Theme.danger : Theme.muted
        }

    }

}
