import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell.Bluetooth
import "../core"
import "../components" as C

// One Bluetooth device. Tapping it connects or disconnects (or pairs one found nearby); its badge shows the
// battery as a ring and spins while something is under way. A paired device's ⋯ opens auto-connect, trust and
// forget.
Rectangle {
    id: root
    required property var device
    // "connect" or "disconnect" while the shell's own request runs; BlueZ has no state for one it didn't start.
    property string working: ""
    property bool autoConnect: false
    property bool expanded: false
    property bool locked: false
    signal activated()
    signal optionsRequested()
    signal autoConnectToggled()
    signal forgetRequested()

    readonly property bool connected: device.connected
    readonly property bool paired: device.paired
    readonly property bool busy: working !== "" || device.pairing || device.state === BluetoothDeviceState.Connecting
                                 || device.state === BluetoothDeviceState.Disconnecting
    readonly property string name: {
        const name = device.name || "";
        return !name || /^([0-9a-f]{2}[-:]){5}[0-9a-f]{2}$/i.test(name) ? "Unnamed device" : name;
    }
    readonly property string glyph: {
        const icon = device.icon || "";
        return /headset|headphone/.test(icon) || /head(phone|set)|earbud|airpods|buds/i.test(device.name || "") ? "headphones"
             : /audio|speaker/.test(icon) ? "speaker" : /computer/.test(icon) ? "laptop" : /video|display/.test(icon) ? "monitor" : "bluetooth";
    }
    readonly property string status: {
        if (device.pairing)
            return "Pairing…";
        if (working === "disconnect" || device.state === BluetoothDeviceState.Disconnecting)
            return "Disconnecting…";
        if (working === "connect" || device.state === BluetoothDeviceState.Connecting)
            return "Connecting…";
        if (!paired)
            return name === "Unnamed device" ? device.address : "Tap to pair";
        const battery = device.batteryAvailable ? " · " + Math.round(device.battery * 100) + "%" : "";
        return (connected ? "Connected" + battery : "Tap to connect") + (autoConnect ? " · Auto-connect" : "");
    }

    implicitHeight: column.implicitHeight
    radius: Theme.controlRadius
    color: connected ? (tap.containsMouse ? Theme.selectionHover : Theme.selection) : tap.containsMouse ? Theme.hover : Theme.surface
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    clip: true
    Behavior on implicitHeight {
        NumberAnimation { duration: Theme.enter; easing.type: Easing.OutCubic }
    }

    ColumnLayout {
        id: column
        width: parent.width
        spacing: 0
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            MouseArea {
                id: tap
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: root.busy || root.locked ? Qt.ArrowCursor : Qt.PointingHandCursor
                enabled: !root.busy && !root.locked
                onClicked: root.activated()
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.gapM - 2
                anchors.rightMargin: Theme.gapS
                spacing: Theme.gapM
                // The badge: a ring for the battery, a turning arc while busy.
                Item {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    Rectangle {
                        anchors.centerIn: parent
                        width: 34
                        height: 34
                        radius: 17
                        color: root.connected ? Theme.selectionHover : Theme.raised
                        C.Icon {
                            anchors.centerIn: parent
                            name: root.glyph
                            size: 17
                            color: root.connected ? Theme.accentText : Theme.text
                        }
                    }
                    Shape {
                        anchors.fill: parent
                        visible: !root.busy && root.connected && root.device.batteryAvailable
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12)
                            strokeWidth: 2.5
                            fillColor: "transparent"
                            PathAngleArc { centerX: 20; centerY: 20; radiusX: 18.5; radiusY: 18.5; startAngle: 0; sweepAngle: 360 }
                        }
                        ShapePath {
                            strokeColor: root.device.battery <= 0.15 ? Theme.danger : root.device.battery <= 0.3 ? Theme.warning : Theme.success
                            strokeWidth: 2.5
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathAngleArc { centerX: 20; centerY: 20; radiusX: 18.5; radiusY: 18.5; startAngle: -90; sweepAngle: 360 * root.device.battery }
                        }
                    }
                    Shape {
                        id: spinner
                        anchors.fill: parent
                        visible: root.busy
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: Theme.accent
                            strokeWidth: 2.5
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathAngleArc { centerX: 20; centerY: 20; radiusX: 18.5; radiusY: 18.5; startAngle: 0; sweepAngle: 100 }
                        }
                        RotationAnimator on rotation {
                            running: spinner.visible && !Theme.reduced
                            from: 0
                            to: 360
                            duration: 900
                            loops: Animation.Infinite
                        }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    C.Label {
                        text: root.name
                        color: root.connected ? Theme.accentText : Theme.text
                        font.weight: Font.Medium
                        Layout.fillWidth: true
                    }
                    C.Label {
                        text: root.status
                        color: Theme.muted
                        font.pixelSize: Theme.small
                        Layout.fillWidth: true
                    }
                }
                C.Button {
                    visible: root.paired
                    glyph: "more"
                    flat: true
                    selected: root.expanded
                    implicitWidth: 34
                    implicitHeight: 34
                    hint: root.expanded ? "Fewer options" : "Options"
                    Accessible.name: "Options for " + root.name
                    onClicked: root.optionsRequested()
                }
            }
        }
        // Auto-connect, trust and forget for a paired device.
        ColumnLayout {
            id: options
            visible: root.expanded && root.paired
            Layout.fillWidth: true
            Layout.leftMargin: Theme.gapS
            Layout.rightMargin: Theme.gapS
            Layout.bottomMargin: Theme.gapS
            spacing: 2
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                Layout.bottomMargin: Theme.gapXs
                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
            }
            C.Toggle {
                Layout.fillWidth: true
                flat: true
                text: "Auto-connect"
                description: "When Bluetooth turns on, at login, after sleep and after unlocking"
                selected: root.autoConnect
                onClicked: root.autoConnectToggled()
            }
            C.Toggle {
                Layout.fillWidth: true
                flat: true
                text: "Trusted"
                description: "Connects without asking first"
                selected: root.device.trusted
                onClicked: root.device.trusted = !root.device.trusted
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.gapXs
                Layout.leftMargin: Theme.gapS
                spacing: Theme.gapS
                C.Label {
                    text: confirming.checked ? "Forget " + root.name + "?" : ""
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                C.Button {
                    visible: confirming.checked
                    text: "Cancel"
                    flat: true
                    implicitHeight: Theme.controlSmall + 4
                    onClicked: confirming.checked = false
                }
                C.Button {
                    id: forget
                    text: confirming.checked ? "Forget" : "Forget device"
                    glyph: confirming.checked ? "" : "trash"
                    danger: true
                    flat: !confirming.checked
                    implicitHeight: Theme.controlSmall + 4
                    enabled: !root.busy && !root.locked
                    onClicked: {
                        if (!confirming.checked) {
                            confirming.checked = true;
                            return;
                        }
                        confirming.checked = false;
                        root.forgetRequested();
                    }
                }
                // Holds the confirmation step; closing the options cancels it.
                QtObject {
                    id: confirming
                    property bool checked: false
                }
                Connections {
                    target: root
                    function onExpandedChanged() {
                        confirming.checked = false;
                    }
                }
            }
        }
    }
}
