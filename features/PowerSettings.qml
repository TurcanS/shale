import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

// Settings → Power: the power mode, the lid and the refresh rate in power saver. Control → Power has the battery.
ColumnLayout {
    spacing: 8
    Component.onCompleted: ShellState.refreshProfiles()
    C.Group {
        C.ChoiceRow {
            readonly property var modes: ShellState.profiles.profiles || []
            label: "Power mode"
            description: modes.length ? "Until you change it; battery rules may switch it" : "Unavailable on this computer"
            enabled: modes.length > 0
            model: modes.map(mode => ({key: mode, text: ({"power-saver": "Saver", "balanced": "Balanced", "performance": "Performance"})[mode] || mode}))
            current: ShellState.profiles.active || ""
            onActivated: key => Backend.request("power.set", {profile: key}, (r, e) => {
                if (e)
                    ShellState.message(e.message, "error");
                else
                    ShellState.profiles = r;
            })
        }
        C.Toggle {
            visible: Backend.capabilities.lid === true
            Layout.fillWidth: true
            flat: true
            text: "Stay awake with the lid closed"
            description: "For an external screen; until you turn it off or log out"
            selected: ShellState.lidAwake
            enabled: !ShellState.lidBusy
            onClicked: ShellState.toggleLidAwake()
        }
        C.SettingToggle {
            visible: Backend.capabilities.builtinPanel !== false
            text: "Lower refresh rate in power saver"
            description: "The built-in screen drops to its lowest refresh rate"
            key: "saverRefresh"
            fallback: true
        }
        C.OpenRow {
            label: "Battery"
            description: "Charge, time left and the power modes in Control"
            action: "Open"
            glyph: "battery"
            onOpened: {
                ShellState.open("control");
                ShellState.detail = "power";
            }
        }
    }
}
