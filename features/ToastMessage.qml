import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components" as C

// Shell messages (a saved setting, an error, Undo) in a small card above the bottom edge, one at a time.
PanelWindow {
    id: messageWindow
    // Whether this window's screen is the one toasts show on now.
    property bool target: false
    property string retainedText: ""
    property string retainedKind: "info"
    property var retainedAction: null
    readonly property bool showing: messageWindow.target && ShellState.toast !== "" && !ShellState.locked
    property real reveal: showing ? 1 : 0
    Connections {
        target: ShellState
        function onToastChanged() {
            if (ShellState.toast === "")
                return;
            messageWindow.retainedText = ShellState.toast;
            messageWindow.retainedKind = ShellState.toastKind;
            messageWindow.retainedAction = ShellState.toastAction;
        }
    }
    // Lively and Playful: it rises out of the bottom edge like a tray and seats. Calm keeps the short fade.
    Behavior on reveal {
        NumberAnimation {
            duration: Motion.calm || !messageWindow.showing ? Theme.fast : Motion.ms(320)
            easing.type: Motion.calm || !messageWindow.showing ? Easing.OutCubic : Easing.BezierSpline
            easing.bezierCurve: Motion.seatCurve(Motion.ov(0.8))
        }
    }
    anchors {
        bottom: true
    }
    margins.bottom: 18
    TextMetrics {
        id: messageMetrics
        font.family: Theme.font
        font.pixelSize: Theme.body
        text: messageWindow.retainedText
    }
    implicitWidth: Math.min(560, screen.width - 40, Math.max(240, messageMetrics.advanceWidth + 100 + (retainedAction ? actionMetrics.advanceWidth + 36 : 0)))
    TextMetrics {
        id: actionMetrics
        font.family: Theme.font
        font.pixelSize: Theme.body
        text: messageWindow.retainedAction ? messageWindow.retainedAction.label : ""
    }
    implicitHeight: Math.max(60, messageLabel.implicitHeight + 24)
    visible: messageWindow.target && !ShellState.locked && reveal > 0
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shale-message"
    WlrLayershell.layer: WlrLayer.Overlay
    // The same surface as the notification toasts: a tile says what kind of message it is.
    Rectangle {
        anchors.fill: parent
        color: Theme.module
        opacity: Math.min(1, messageWindow.reveal * (Motion.calm ? 1 : 2))
        transform: Translate { y: Theme.reduced ? 0 : (1 - messageWindow.reveal) * (Motion.calm ? 6 : 44 * Motion.travel) }
        radius: 14
        border.width: 1
        border.color: messageWindow.retainedKind === "error" ? Theme.dangerLine : Theme.cardEdge
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 8
            spacing: Theme.gapM
            Rectangle {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                radius: 9
                color: messageWindow.retainedKind === "error" ? Theme.dangerSoft : messageWindow.retainedKind === "success" ? Theme.accentSoft : Theme.key
                C.Icon {
                    anchors.centerIn: parent
                    name: messageWindow.retainedKind === "error" ? "alert" : messageWindow.retainedKind === "success" ? "check" : "info"
                    color: messageWindow.retainedKind === "error" ? Theme.dangerText : messageWindow.retainedKind === "success" ? Theme.accentText : Theme.textSecondary
                }
            }
            C.Label {
                id: messageLabel
                text: messageWindow.retainedText
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                color: messageWindow.retainedKind === "error" ? Theme.dangerText : Theme.text
            }
            C.Button {
                visible: !!messageWindow.retainedAction
                text: messageWindow.retainedAction ? messageWindow.retainedAction.label : ""
                implicitHeight: 30
                cornerRadius: 8
                labelSize: 12
                onClicked: {
                    const action = messageWindow.retainedAction;
                    ShellState.toast = "";
                    if (action)
                        action.run();
                }
            }
            C.Button {
                glyph: "close"
                flat: true
                implicitWidth: 28
                implicitHeight: 28
                foreground: hovered || visualFocus ? Theme.text : Theme.textDim
                hint: "Dismiss message"
                onClicked: ShellState.toast = ""
            }
        }
    }
}
