pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../components" as C

// One device nearby: its picture on a disc, a ring around it that fills as the files go, its name and what is
// happening. Press to send what is chosen; press again while it sends to cancel. Pops in when found, shakes when
// declined, fades when it leaves.
AbstractButton {
    id: root
    required property string peerId
    required property string name
    required property string kind
    required property bool available
    required property bool lost
    required property string phase
    required property real done
    required property real total
    required property string message
    // Something is chosen to send and no other send runs.
    property bool ready: false
    property int order: 0
    readonly property bool moving: phase === "asking" || phase === "sending"
    readonly property real fraction: phase === "done" ? 1 : total > 0 ? Math.min(1, done / total) : 0
    readonly property string glyph: ({iphone: "phone", ipad: "tablet", mac: "laptop"})[kind] || "monitor"
    readonly property string status: {
        if (lost)
            return "Gone";
        if (!available)
            return "Not accepting";
        switch (phase) {
        case "asking":
            return "Waiting…";
        case "sending":
            return Math.round(fraction * 100) + "%";
        case "done":
            return "Sent";
        case "declined":
            return "Declined";
        case "failed":
            return "Didn't send";
        case "cancelled":
            return "Cancelled";
        }
        return "";
    }
    implicitWidth: 112
    implicitHeight: 128
    enabled: !lost && available && (moving || ready)
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    Accessible.role: Accessible.Button
    Accessible.name: moving ? "Cancel sending to " + name : "Send to " + name
    Accessible.description: status
    ToolTip.visible: hovered && (!available || phase === "failed" && message !== "")
    ToolTip.delay: 500
    ToolTip.text: !available ? "On " + name + ", set AirDrop to Everyone for 10 Minutes" : message
    // Found: rises and fades in, each a little after the one before.
    opacity: 0
    scale: 0.92
    Component.onCompleted: entrance.start()
    SequentialAnimation {
        id: entrance
        PauseAnimation {
            duration: Theme.reduced ? 0 : Math.min(root.order, 6) * 40
        }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "opacity"
                to: root.lost ? 0.4 : 1
                duration: Theme.enter
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.easeOut
            }
            NumberAnimation {
                target: root
                property: "scale"
                to: 1
                duration: Theme.reduced ? 0 : Theme.enter + 60
                easing.type: Easing.OutBack
                easing.overshoot: 1.4
            }
        }
    }
    onLostChanged: if (!entrance.running)
        opacity = lost ? 0.4 : 1
    Behavior on opacity {
        enabled: !entrance.running
        NumberAnimation {
            duration: Theme.leave
        }
    }
    // Declined or failed: a short shake, as a password field does.
    onPhaseChanged: if ((phase === "declined" || phase === "failed") && !Theme.reduced)
        shake.restart()
    property real nudge: 0
    transform: Translate {
        x: root.nudge
    }
    SequentialAnimation {
        id: shake
        loops: 1
        NumberAnimation { target: root; property: "nudge"; to: -5; duration: 50 }
        NumberAnimation { target: root; property: "nudge"; to: 5; duration: 70 }
        NumberAnimation { target: root; property: "nudge"; to: -4; duration: 70 }
        NumberAnimation { target: root; property: "nudge"; to: 3; duration: 60 }
        NumberAnimation { target: root; property: "nudge"; to: 0; duration: 50 }
    }
    background: Rectangle {
        radius: Theme.radiusCard + 2
        color: root.down ? Theme.rowWash(true) : root.hovered || root.visualFocus ? Theme.rowWash(false) : "transparent"
        Behavior on color {
            ColorAnimation {
                duration: Theme.fast
            }
        }
        C.FocusRing {
            visible: root.visualFocus
            radius: parent.radius
        }
    }
    contentItem: ColumnLayout {
        spacing: 6
        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 6
            implicitWidth: 72
            implicitHeight: 72
            scale: root.down && !Theme.reduced ? Theme.pressScale : 1
            Behavior on scale {
                NumberAnimation {
                    duration: Theme.press
                    easing.type: Easing.OutCubic
                }
            }
            // Progress: the share sent, smoothed between the command's reports.
            C.Ring {
                id: ring
                anchors.fill: parent
                size: 72
                thickness: 3
                trackColor: root.moving || root.phase === "done" ? Theme.key : "transparent"
                color: Theme.accent
                property real shown: root.fraction
                // Only a send that runs or ran fills it; an idle device shows no ring.
                value: root.phase === "sending" || root.phase === "done" ? shown : 0
                Behavior on shown {
                    enabled: root.phase === "sending" || root.phase === "done"
                    NumberAnimation {
                        duration: Theme.reduced ? 0 : 240
                        easing.type: Easing.OutCubic
                    }
                }
            }
            // Waiting for the other side to accept: a quarter arc going round.
            C.Ring {
                anchors.fill: parent
                size: 72
                thickness: 3
                visible: root.phase === "asking"
                trackColor: "transparent"
                value: 0.25
                RotationAnimator on rotation {
                    running: root.phase === "asking" && !Theme.reduced && !Theme.lowPower
                    from: 0
                    to: 360
                    duration: 1100
                    loops: Animation.Infinite
                    onRunningChanged: if (!running)
                        target.rotation = 0
                }
            }
            Rectangle {
                anchors.centerIn: parent
                width: 58
                height: 58
                radius: 29
                color: root.phase === "done" ? Theme.raised : Theme.module
                border.width: 1
                border.color: root.phase === "done" ? "transparent" : Theme.edge
                Behavior on color {
                    ColorAnimation {
                        duration: Theme.fast
                    }
                }
                C.Raise {
                    shown: root.phase === "done"
                }
                C.Icon {
                    anchors.centerIn: parent
                    name: root.moving && root.hovered ? "close" : root.glyph
                    size: 26
                    color: root.phase === "done" ? Theme.accentText : !root.available || root.lost ? Theme.textFaint : Theme.text
                }
            }
            // Sent: a check pops onto the disc's edge.
            Rectangle {
                id: badge
                width: 22
                height: 22
                radius: 11
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 2
                color: root.phase === "done" ? Theme.accent : Theme.danger
                border.width: 2
                border.color: Theme.caseColor
                readonly property bool shown: root.phase === "done" || root.phase === "declined" || root.phase === "failed"
                scale: shown ? 1 : 0
                visible: scale > 0
                Behavior on scale {
                    NumberAnimation {
                        duration: Theme.reduced ? 0 : 260
                        easing.type: Easing.OutBack
                        easing.overshoot: 2
                    }
                }
                C.Icon {
                    anchors.centerIn: parent
                    name: root.phase === "done" ? "check" : "close"
                    size: 12
                    color: root.phase === "done" ? Theme.accentInk : Theme.caseColor
                }
            }
        }
        C.Label {
            text: root.name
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: !root.available || root.lost ? Theme.textDim : Theme.text
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }
        C.Label {
            text: root.status || " "
            font.pixelSize: 12
            font.features: ({"tnum": 1})
            color: root.phase === "declined" || root.phase === "failed" ? Theme.dangerText
                 : root.moving || root.phase === "done" ? Theme.accentText : Theme.textDim
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
            Layout.topMargin: -4
        }
    }
}
