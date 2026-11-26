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
    property int delay: 1000
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
    implicitHeight: Math.max(description !== "" ? 60 : Theme.controlLarge, holdContent.implicitHeight + topPadding + bottomPadding)
    implicitWidth: 240
    padding: Theme.gapL
    topPadding: Theme.gapM
    bottomPadding: Theme.gapM
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    enabled: armed && !triggered
    // Labels that already say "Hold to …" are read as they are.
    Accessible.name: /^hold to /i.test(text) ? text : "Hold to " + text.toLowerCase()
    Accessible.description: "Hold for " + delay / 1000 + (delay === 1000 ? " second" : " seconds") + ". Release early to cancel."
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

    // A module, or for destructive actions the danger edge and wash; holding fills it from the left.
    background: Rectangle {
        readonly property bool lit: root.hovered || root.visualFocus || root.down
        radius: Theme.radiusCard
        color: root.destructive ? (lit ? Theme.dangerSoft : Theme.dangerWash) : lit ? Theme.mix(Theme.module, Theme.text, 0.05) : Theme.module
        border.width: root.destructive ? 1 : 0
        border.color: Theme.dangerLine

        // Clipped square on the right, so the fill keeps the key's rounded left end as it grows.
        Item {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * root.progress
            clip: true

            Rectangle {
                width: root.width
                height: parent.height
                radius: Theme.radiusCard
                color: root.destructive ? Theme.tint(Theme.danger, 0.28) : Theme.accentSoft
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
            size: root.description !== "" ? Theme.iconLarge : Theme.icon
            color: root.destructive ? Theme.dangerText : Theme.text
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.gapXs

            C.Label {
                text: root.text
                font.weight: Font.DemiBold
                color: root.destructive ? Theme.dangerText : Theme.text
                Layout.fillWidth: true
            }

            C.Label {
                visible: root.description !== ""
                text: root.description
                color: root.destructive ? Theme.tint(Theme.dangerText, 0.75) : Theme.textDim
                font.pixelSize: Theme.small
                Layout.fillWidth: true
            }

        }

        C.Label {
            visible: root.down
            text: Math.max(0, (root.delay * (1 - root.progress)) / 1000).toFixed(1) + "s"
            font.pixelSize: Theme.small
            font.family: Theme.mono
            color: root.destructive ? Theme.dangerText : Theme.textDim
        }

    }

}
