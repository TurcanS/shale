import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import "../core"
import "../components" as C

// One Bluetooth device: a type tile (accent wash when connected), name and state, a battery badge (danger under
// 15%), and Connect, Disconnect or Pair. The tile turns while something is under way. A paired device's ⋯ opens
// auto-connect, trust and forget.
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
    // BlueZ's icon names the kind of device; headphones are often only known by their name.
    readonly property var kind: {
        const icon = device.icon || "";
        if (/headset|headphone/.test(icon) || /head(phone|set)|earbud|airpods|buds/i.test(device.name || ""))
            return {text: "Headphones", glyph: "headphones"};
        if (/audio|speaker/.test(icon))
            return {text: "Speaker", glyph: "speaker"};
        if (/mouse|tablet/.test(icon))
            return {text: "Mouse", glyph: "mouse"};
        if (/keyboard/.test(icon))
            return {text: "Keyboard", glyph: "keyboard"};
        if (/gaming|joystick/.test(icon))
            return {text: "Controller", glyph: "gamepad"};
        if (/computer/.test(icon))
            return {text: "Computer", glyph: "laptop"};
        if (/video|display/.test(icon))
            return {text: "Display", glyph: "monitor"};
        if (/phone/.test(icon))
            return {text: "Phone", glyph: "bluetooth"};
        return {text: "Device", glyph: "bluetooth"};
    }
    readonly property string status: {
        if (device.pairing)
            return "Pairing…";
        if (working === "disconnect" || device.state === BluetoothDeviceState.Disconnecting)
            return "Disconnecting…";
        if (working === "connect" || device.state === BluetoothDeviceState.Connecting)
            return "Connecting…";
        if (!paired)
            return name === "Unnamed device" ? device.address : kind.text + " · nearby";
        return kind.text + (connected ? " · connected" : " · paired") + (autoConnect ? " · auto-connect" : "");
    }
    readonly property bool lowBattery: device.batteryAvailable && device.battery < 0.15

    implicitHeight: column.implicitHeight
    radius: Theme.radiusKey
    color: connected || expanded ? Theme.mix(Theme.module, Theme.text, 0.03) : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    clip: true
    Behavior on implicitHeight {
        NumberAnimation { duration: Theme.enter; easing.type: Easing.OutCubic }
    }

    ColumnLayout {
        id: column
        width: parent.width
        spacing: 0
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            Layout.leftMargin: 10
            Layout.rightMargin: 6
            spacing: Theme.gapM
            Rectangle {
                implicitWidth: 32
                implicitHeight: 32
                radius: Theme.radiusKey
                color: root.connected ? Theme.raisedOnKey : Theme.key
                C.Icon {
                    id: kindIcon
                    anchors.centerIn: parent
                    name: root.busy ? "spinner" : root.kind.glyph
                    size: 16
                    color: root.connected || root.busy ? Theme.accentText : Theme.textMuted
                    RotationAnimator on rotation {
                        running: root.busy && !Theme.reduced
                        from: 0
                        to: 360
                        duration: 900
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) kindIcon.rotation = 0
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                C.Label {
                    text: root.name
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }
                C.Label {
                    text: root.status
                    color: Theme.textDim
                    font.pixelSize: 12
                    Layout.fillWidth: true
                }
            }
            // Battery: a small cell drawn to its level, and the percentage.
            Rectangle {
                visible: root.connected && root.device.batteryAvailable
                implicitWidth: batteryRow.implicitWidth + 16
                implicitHeight: 22
                radius: 8
                color: root.lowBattery ? Theme.dangerSoft : Theme.key
                Accessible.name: "Battery " + Math.round(root.device.battery * 100) + "%"
                Row {
                    id: batteryRow
                    anchors.centerIn: parent
                    spacing: 6
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        height: 8
                        radius: 2.5
                        color: "transparent"
                        border.width: 1.5
                        border.color: batteryText.color
                        Rectangle {
                            x: 2.5
                            y: 2.5
                            width: Math.max(1, (parent.width - 5) * root.device.battery)
                            height: parent.height - 5
                            radius: 0.5
                            color: batteryText.color
                        }
                    }
                    C.Label {
                        id: batteryText
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(root.device.battery * 100) + "%"
                        color: root.lowBattery ? Theme.dangerText : Theme.textSecondary
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        font.features: {"tnum": 1}
                    }
                }
            }
            C.Button {
                id: actionKey
                text: !root.paired ? "Pair" : root.connected ? "Disconnect" : "Connect"
                accent: !root.connected
                implicitHeight: 30
                leftPadding: 10
                rightPadding: 10
                topPadding: 0
                bottomPadding: 0
                labelSize: 12
                cornerRadius: 8
                enabled: !root.busy && !root.locked
                Accessible.name: text + " " + root.name
                onClicked: root.activated()
            }
            C.Button {
                visible: root.paired
                glyph: "more"
                flat: true
                selected: root.expanded
                implicitWidth: 30
                implicitHeight: 30
                hint: root.expanded ? "Fewer options" : "Options"
                Accessible.name: "Options for " + root.name
                onClicked: root.optionsRequested()
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
                color: Theme.separator
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
