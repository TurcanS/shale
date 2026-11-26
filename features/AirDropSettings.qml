pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "../components" as C

// Settings → AirDrop: how it receives, this computer's name and the senders let straight in, and a check of what
// AirDrop needs here. The name and the senders are the airdrop command's own settings, changed through it.
ColumnLayout {
    id: root
    spacing: 8
    Component.onCompleted: if (AirDrop.available && !AirDrop.doctor)
        AirDrop.checkComputer()
    C.Group {
        visible: !AirDrop.available
        C.ValueRow {
            label: "AirDrop for Linux"
            description: AirDrop.command ? "Installed, but older than Shale needs: update it and install it again" : "Install the airdrop command and its helper; Shale finds it on your PATH or in ~/.local/bin"
            value: AirDrop.command ? "Too old" : "Not installed"
            valueColor: Theme.warning
        }
    }
    C.Group {
        visible: AirDrop.available
        C.ChoiceRow {
            settingKey: "airdropMode"
            label: "When Shale starts"
            description: ShellState.setting("airdropMode", "off") === "background" ? "Listens on Bluetooth; Wi-Fi pauses only while an iPhone sends" : "Nobody nearby sees this computer until you choose Visible"
            model: [{key: "off", text: "Off"}, {key: "background", text: "Background"}]
            current: ShellState.setting("airdropMode", "off")
            onActivated: key => {
                ShellState.setSetting("airdropMode", key);
                if (AirDrop.mode !== "visible")
                    AirDrop.setMode(key, false);
            }
        }
        C.ChoiceRow {
            settingKey: "airdropAsk"
            label: "Before saving"
            description: ShellState.setting("airdropAsk", "ask") === "all" ? "Anyone nearby can put files here while you're visible" : "Ask each time; senders you let in always go straight in"
            descriptionColor: ShellState.setting("airdropAsk", "ask") === "all" ? Theme.warning : Theme.textDim
            model: [{key: "ask", text: "Ask"}, {key: "all", text: "Accept all"}]
            current: ShellState.setting("airdropAsk", "ask")
            onActivated: key => ShellState.setSetting("airdropAsk", key)
        }
        C.ChoiceRow {
            settingKey: "airdropTimeout"
            label: "Answer within"
            description: "A request nobody answers is declined"
            model: [30, 60, 120, 300].map(seconds => ({key: seconds, text: seconds < 60 ? seconds + " s" : seconds / 60 + " min"}))
            current: ShellState.setting("airdropTimeout", 60)
            onActivated: key => ShellState.setSetting("airdropTimeout", key)
        }
        C.FolderField {
            label: "Save to"
            note: "Received files go here"
            key: "airdropFolder"
            fallback: "~/Downloads/AirDrop"
        }
    }
    C.SectionHeader {
        visible: AirDrop.available
        text: "This computer"
    }
    C.Group {
        visible: AirDrop.available
        C.SettingRow {
            label: "Name"
            description: "What iPhones and Macs nearby show"
            C.Field {
                id: nameField
                text: AirDrop.deviceName
                placeholderText: "This computer's name"
                implicitWidth: 240
                implicitHeight: 36
                // An empty name isn't taken: the field shows the one in use again.
                onEditingFinished: {
                    if (text.trim() === "")
                        text = AirDrop.deviceName;
                    else
                        AirDrop.rename(text);
                }
            }
        }
        // Senders let in with Always: their requests go straight in.
        Repeater {
            model: AirDrop.knownSenders
            C.SettingRow {
                id: known
                required property string modelData
                label: modelData
                description: "Goes straight in, without asking"
                C.Button {
                    text: "Forget"
                    implicitHeight: 32
                    onClicked: AirDrop.forget(known.modelData)
                }
            }
        }
        C.ValueRow {
            visible: AirDrop.knownSenders.length === 0
            label: "Senders let straight in"
            description: "Always on a request adds its sender here"
            value: "None yet"
        }
    }
    C.SectionHeader {
        visible: AirDrop.available
        text: "Check this computer"
    }
    C.Group {
        visible: AirDrop.available
        C.SettingRow {
            label: AirDrop.checking ? "Checking…" : !AirDrop.doctor ? "Not checked yet" : AirDrop.doctor.ok ? "Ready for AirDrop" : "Something needs fixing"
            description: "The Wi-Fi card, the helper, Bluetooth and the radio rules AirDrop needs"
            descriptionColor: AirDrop.doctor && !AirDrop.doctor.ok ? Theme.dangerText : Theme.textDim
            C.Button {
                text: "Check again"
                implicitHeight: 32
                enabled: !AirDrop.checking
                onClicked: AirDrop.checkComputer()
            }
        }
        // For a session that ended badly and left the network paused.
        C.SettingRow {
            label: "Wi-Fi stays off after AirDrop"
            description: AirDrop.looking ? "Wait for the send to finish first" : "Reconnects the network AirDrop paused (airdrop recover); asks for your password"
            C.Button {
                text: AirDrop.recovering ? "Giving it back…" : "Give Wi-Fi back"
                implicitHeight: 32
                enabled: !AirDrop.recovering && !AirDrop.looking
                onClicked: AirDrop.recover()
            }
        }
        Repeater {
            model: AirDrop.doctor ? AirDrop.doctor.checks : []
            C.SettingRow {
                id: check
                required property var modelData
                label: modelData.label
                description: modelData.detail
                descriptionColor: modelData.level === "error" ? Theme.dangerText : Theme.textDim
                C.Icon {
                    name: check.modelData.level === "ok" ? "check" : check.modelData.level === "error" ? "alert" : "info"
                    size: 18
                    color: check.modelData.level === "ok" ? Theme.success : check.modelData.level === "error" ? Theme.danger : Theme.textDim
                }
            }
        }
    }
}
