import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import "../core"
import "../services"
import "../components" as C

// Control → Bluetooth: the adapter switch, Scan, pairing, and the paired and nearby devices.
C.Card {
    // The Control page this view belongs to: its state, requests and helpers.
    required property var control
    // Called when Control changes page: a half-typed pairing PIN never carries over.
    function clearPin() {
        pin.clear();
    }
    visible: ShellState.detail === "bluetooth"
    Layout.fillWidth: true
    implicitHeight: bluetoothColumn.implicitHeight + 24
    ColumnLayout {
        id: bluetoothColumn
        anchors.fill: parent
        anchors.margins: 12
        spacing: 6
        ControlModuleHeader {
            title: "Bluetooth"
            large: true
            note: {
                const count = Services.bluetoothDevices.filter(d => d.connected).length;
                return !Services.bluetoothAvailable ? "no adapter detected" : !Services.bluetoothEnabled ? "off"
                     : count ? count + " connected" : Services.bluetoothScanning ? "searching nearby" : "on";
            }
            Layout.leftMargin: 2
            Layout.bottomMargin: 4
            // Scan turns while it looks; pressing it again stops.
            C.Button {
                id: bluetoothScan
                visible: Services.bluetoothEnabled
                text: Services.bluetoothScanning ? "Scanning" : "Scan"
                hint: Services.bluetoothScanning ? "Stop looking for devices" : "Look for devices to pair"
                implicitHeight: 28
                leftPadding: 10
                rightPadding: 10
                topPadding: 0
                bottomPadding: 0
                labelSize: 12
                cornerRadius: 8
                foreground: Services.bluetoothScanning ? Theme.accentText : Theme.text
                Accessible.role: Accessible.CheckBox
                Accessible.checkable: true
                Accessible.checked: Services.bluetoothScanning
                onClicked: Services.bluetoothScan(!Services.bluetoothScanning)
                background: Rectangle {
                    radius: bluetoothScan.cornerRadius
                    color: bluetoothScan.hovered || bluetoothScan.down || bluetoothScan.visualFocus ? Theme.keyHover : Theme.key
                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.fast
                        }
                    }
                }
                contentItem: RowLayout {
                    spacing: 6
                    C.Icon {
                        id: scanSpinner
                        name: "spinner"
                        size: 13
                        color: bluetoothScan.foreground
                        RotationAnimator on rotation {
                            running: Services.bluetoothScanning && !Theme.reduced
                            from: 0
                            to: 360
                            duration: 900
                            loops: Animation.Infinite
                            onRunningChanged: if (!running) scanSpinner.rotation = 0
                        }
                    }
                    C.Label {
                        text: bluetoothScan.text
                        color: bluetoothScan.foreground
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }
            }
            C.Switch {
                hint: Services.bluetoothEnabled ? "Turn Bluetooth off" : "Turn Bluetooth on"
                selected: Services.bluetoothEnabled
                enabled: Services.bluetoothAvailable
                onClicked: Services.bluetoothPower(!Services.bluetoothEnabled)
            }
        }
        Rectangle {
            visible: !!control.pairing
            Layout.fillWidth: true
            implicitHeight: pairingContent.implicitHeight + 24
            radius: Theme.radiusCard
            color: Theme.accentSoft
            border.width: 1
            border.color: Theme.accentLine
            ColumnLayout {
                id: pairingContent
                anchors.fill: parent
                anchors.margins: 12
                spacing: Theme.gapS
                C.Label {
                    text: control.pairing ? control.pairing.message : ""
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
                C.Field {
                    id: pin
                    Layout.fillWidth: true
                    implicitHeight: 36
                    placeholderText: "PIN or passkey"
                    visible: control.pairing && control.pairing.input
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.gapS
                    C.Button {
                        text: "Reject"
                        implicitHeight: 32
                        onClicked: {
                            ShellState.run("bluetooth.reply", {
                                accept: false
                            });
                            control.pairing = null;
                        }
                    }
                    C.Button {
                        text: "Accept"
                        accent: true
                        implicitHeight: 32
                        Layout.fillWidth: true
                        enabled: !!control.pairing && (!control.pairing.input || pin.text.trim().length > 0)
                        onClicked: {
                            ShellState.run("bluetooth.reply", {
                                accept: true,
                                value: pin.text
                            });
                            pin.clear();
                            control.pairing = null;
                        }
                    }
                }
            }
        }
        // Paired devices, connected first.
        Repeater {
            model: Services.bluetoothEnabled ? control.pairedDevices : []
            BluetoothDeviceRow {
                required property var modelData
                Layout.fillWidth: true
                device: modelData
                working: control.bluetoothWork[modelData.dbusPath] || ""
                autoConnect: control.autoConnectList.indexOf(String(modelData.address).toUpperCase()) >= 0
                expanded: control.expandedDevice === modelData.dbusPath
                locked: control.acting
                onActivated: control.bluetoothActivate(modelData)
                onOptionsRequested: control.expandedDevice = expanded ? "" : modelData.dbusPath
                onAutoConnectToggled: control.toggleAutoConnect(modelData)
                onForgetRequested: {
                    control.expandedDevice = "";
                    modelData.forget();
                }
            }
        }
        C.EmptyState {
            visible: Services.bluetoothEnabled && control.nearbyDevices.length === 0 && control.pairedDevices.length === 0
            Layout.fillWidth: true
            Layout.topMargin: Theme.gapM
            Layout.bottomMargin: Theme.gapM
            glyph: "bluetooth"
            title: Services.bluetoothScanning ? "Looking for devices…" : "No devices yet"
            description: Services.bluetoothScanning ? "Put your device in pairing mode" : "Scan to find nearby devices"
        }
        // Devices found nearby, to pair.
        C.Caption {
            visible: Services.bluetoothEnabled && (control.nearbyDevices.length > 0 || control.pairedDevices.length > 0)
            text: control.nearbyDevices.length > 0 ? "Nearby" : Services.bluetoothScanning ? "Looking for devices in pairing mode…" : "Scan to add a new device"
            font.pixelSize: 12
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.topMargin: 4
        }
        Repeater {
            model: Services.bluetoothEnabled ? control.nearbyDevices : []
            BluetoothDeviceRow {
                required property var modelData
                Layout.fillWidth: true
                device: modelData
                locked: control.acting
                onActivated: control.bluetoothActivate(modelData)
            }
        }
        ControlSmallKey {
            visible: Services.bluetoothEnabled && control.hiddenDevices > 0 && !control.showAllDevices
            text: "Show " + control.hiddenDevices + (control.hiddenDevices === 1 ? " unnamed device" : " unnamed devices")
            rest: "transparent"
            Layout.alignment: Qt.AlignHCenter
            onClicked: control.showAllDevices = true
        }
    }
}
