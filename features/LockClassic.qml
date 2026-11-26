import QtQuick
import QtQuick.Layouts
import Quickshell
import "../core"
import "../components" as C

// The classic lock screen: the date and a large clock near the top with the glance chips under them, the unlock
// group at the bottom centre, what's playing and the keyboard layout bottom left, the power keys bottom right.
Item {
    id: root
    required property var context
    property string screenName: ""
    property real reveal: 0
    Component.onCompleted: reveal = 1
    opacity: context.unlocking ? 0 : reveal
    Behavior on opacity {
        NumberAnimation {
            duration: Theme.enter
            easing.type: Easing.OutCubic
        }
    }
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    LockBackdrop {
        anchors.fill: parent
        screenName: root.screenName
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.round(root.height * 0.145)
        spacing: 6
        transform: Translate { y: Theme.reduced ? 0 : (1 - root.reveal) * 14 }
        C.Label {
            text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
            color: Theme.tint(Theme.text, 0.85)
            font.pixelSize: 22
            font.weight: Font.Medium
            elide: Text.ElideNone
            Layout.alignment: Qt.AlignHCenter
        }
        // A 168 px box with the digits centred in it, as the design's line-height 1. Tabular figures keep the
        // clock from shifting as the minutes change.
        Item {
            implicitWidth: time.implicitWidth
            implicitHeight: 168
            Layout.alignment: Qt.AlignHCenter
            FontMetrics {
                id: timeMetrics
                font: time.font
            }
            C.Label {
                id: time
                // Read through the metrics' font, so it is measured again once the bundled font has loaded.
                readonly property rect digits: timeMetrics.font.family !== "" ? timeMetrics.tightBoundingRect("0123456789") : Qt.rect(0, 0, 0, 0)
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.round(parent.height / 2 + digits.height / 2 - baselineOffset)
                text: Qt.formatDateTime(clock.date, ShellState.setting("clock24h", true) ? "HH:mm" : "h:mm")
                font.pixelSize: 168
                font.weight: Font.DemiBold
                font.letterSpacing: -6.7
                font.features: {"tnum": 1}
                elide: Text.ElideNone
            }
        }
        LockStatus {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 12
        }
    }

    LockPrompt {
        id: prompt
        context: root.context
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.max(48, Math.round(root.height * 0.133))
        transform: Translate { y: Theme.reduced ? 0 : (1 - root.reveal) * 14 }
    }

    // Bottom left: what's playing (with play/pause and next) and the keyboard layout.
    RowLayout {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 32
        anchors.bottomMargin: 28
        spacing: 8
        LockMedia {
            maxWidth: Math.max(160, Math.min(360, root.width - 420))
        }
        LockKeyboard {}
    }
    // Top right: AirDrop requests, answered without unlocking.
    LockAirDrop {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 32
        anchors.topMargin: 28
    }
    LockPower {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 32
        anchors.bottomMargin: 28
        context: root.context
        onReleased: prompt.focusField()
    }
}
