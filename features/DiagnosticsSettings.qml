import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

// Settings → Diagnostics: the helper, the version, the commands Shale uses and the system monitor.
ColumnLayout {
    id: page
    // Shale's version, which Settings reads once.
    property string version: ""
    spacing: 8
    C.Group {
        C.SettingRow {
            label: "Desktop helper"
            description: Backend.ready ? "Desktop services are available" : "Desktop controls may be unavailable"
            // A status chip: green dot and Connected, or a danger wash while the helper is away.
            Rectangle {
                implicitWidth: statusRow.implicitWidth + 20
                implicitHeight: 28
                radius: 14
                color: Backend.ready ? "transparent" : Theme.dangerWash
                border.width: 1
                border.color: Backend.ready ? Theme.edge : Theme.dangerLine
                RowLayout {
                    id: statusRow
                    anchors.centerIn: parent
                    spacing: 6
                    Rectangle {
                        implicitWidth: 7
                        implicitHeight: 7
                        radius: 3.5
                        color: Backend.ready ? Theme.success : Theme.danger
                    }
                    C.Label {
                        text: Backend.ready ? "Connected" : "Helper offline"
                        color: Backend.ready ? Theme.textSecondary : Theme.dangerText
                        font.pixelSize: Theme.small
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
        C.ValueRow {
            label: "Version"
            description: "The commit the installer put in place"
            value: page.version ? "Shale " + page.version : "Shale · version unknown"
            mono: true
        }
        C.ValueRow {
            label: "D-Bus adapter"
            description: "For Wi-Fi and power controls"
            value: Backend.capabilities.dbus ? "Available" : "Install python-dbus-next"
            valueColor: Backend.capabilities.dbus ? Theme.success : Theme.warning
        }
    }
    C.Label {
        text: ShellState.settings.diagnostic || Backend.lastError
        visible: text !== ""
        color: Theme.warning
        font.pixelSize: Theme.small
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    C.SectionHeader { text: "Commands" }
    C.Group {
        Repeater {
            model: Object.keys(Backend.capabilities.commands || {})
            RowLayout {
                id: command
                required property string modelData
                readonly property bool available: Backend.has(modelData, false)
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(40, Theme.body + 24)
                Layout.leftMargin: Theme.gapL
                Layout.rightMargin: Theme.gapL
                spacing: Theme.gapM
                C.Label {
                    text: command.modelData
                    font.family: Theme.mono
                    font.pixelSize: Theme.small
                    wrapMode: Text.WrapAnywhere
                    Layout.fillWidth: true
                }
                C.Label {
                    text: command.available ? "Available" : "Not installed"
                    color: command.available ? Theme.success : Theme.textDim
                    font.pixelSize: Theme.small
                }
            }
        }
    }
    C.SectionHeader { text: "System monitor" }
    C.Group {
        C.ChoiceRow {
            settingKey: "systemWindow"
            label: "System monitor graphs"
            description: "How far back the graphs reach"
            model: [{key: 60, text: "1 min"}, {key: 300, text: "5 min"}]
            current: ShellState.setting("systemWindow", 60)
            onActivated: key => ShellState.setSetting("systemWindow", key)
        }
        C.OpenRow {
            label: "System monitor"
            description: "Processor, memory, disks, network and graphics, live"
            action: "Open system monitor"
            glyph: "gauge"
            onOpened: ShellState.open("system")
        }
    }
}
