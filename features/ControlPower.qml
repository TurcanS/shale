import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../core"
import "../core/paths.js" as Paths
import "../services"
import "../components" as C
import "../core/format.js" as Format

// Control → Power: the power modes and the battery.
ColumnLayout {
    // The Control page this view belongs to: its state, requests and helpers.
    required property var control
    visible: ShellState.detail === "power"
    Layout.fillWidth: true
    spacing: Theme.gapS
    C.StatusCard {
        Layout.fillWidth: true
        glyph: Services.batteryCharging ? "bolt" : Services.batteryAvailable ? "battery" : "gauge"
        title: Services.batteryAvailable ? Math.round(Services.batteryPercent) + "%" : "AC power"
        subtitle: {
            const state = Services.batteryCharging ? "Charging" : Services.onBattery ? "On battery" : "Plugged in";
            const seconds = Services.batterySeconds;
            return state + (seconds > 0 ? " · " + Format.span(seconds) + (Services.batteryCharging ? " until full" : " remaining") : "");
        }
        level: Services.batteryAvailable ? Services.batteryPercent / 100 : -1
        positive: Services.batteryCharging
    }
    C.SectionHeader {
        text: "Power mode"
        Layout.topMargin: Theme.gapXs
    }
    C.Label {
        visible: !(ShellState.profiles.profiles || []).length
        text: control.busy ? "Loading power modes…" : "Power modes are unavailable on this device."
        color: Theme.textMuted
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    Repeater {
        model: ShellState.profiles.profiles || []
        C.ListRow {
            required property string modelData
            Layout.fillWidth: true
            text: ({"power-saver": "Power saver", "balanced": "Balanced", "performance": "Performance"})[modelData] || modelData
            subtitle: ({"power-saver": "Longest battery life, quiet fans", "balanced": "Fast when needed, efficient at idle", "performance": "Full CPU and GPU power"})[modelData] || "System power profile"
            glyph: modelData === "power-saver" ? "leaf" : modelData === "performance" ? "bolt" : "gauge"
            selected: ShellState.profiles.active === modelData && !(modelData === "performance" && maxRow.selected)
            enabled: !control.acting
            Accessible.role: Accessible.RadioButton
            Accessible.checkable: true
            Accessible.checked: selected
            onClicked: control.perform("power.set", {
                profile: modelData
            }, r => ShellState.profiles = r)
        }
    }
    // Lenovo firmware limits at their maximum, through shale-power-max.service (scripts/install-power-max.py).
    C.ListRow {
        id: maxRow
        visible: ShellState.profiles.maxAvailable === true
        Layout.fillWidth: true
        text: "Max performance"
        subtitle: Services.onBattery ? "Plug in the charger to use it" : "Highest CPU and GPU power the firmware allows · louder fans"
        glyph: "bolt"
        selected: ShellState.profiles.max === true && ShellState.profiles.active === "performance"
        enabled: !control.acting && !Services.onBattery
        Accessible.role: Accessible.RadioButton
        Accessible.checkable: true
        Accessible.checked: selected
        onClicked: control.perform("power.max", {}, r => ShellState.profiles = r)
    }
    C.Label {
        id: tunedHint
        // The installer lives in the Shale repository; a shell run from there knows its path.
        readonly property string script: Paths.localPath(Qt.resolvedUrl("../scripts/install-power.py"))
        property bool scriptFound: false
        visible: (ShellState.profiles.profiles || []).length > 0 && ShellState.profiles.tuned === false
        function probe() {
            if (visible && !scriptFound && !scriptProbe.running)
                scriptProbe.running = true;
        }
        onVisibleChanged: probe()
        Component.onCompleted: probe()
        text: "Using the stock tuned profiles. For the full effect, run " + (scriptFound
            ? "sudo python3 " + (/^[\w\/.+-]+$/.test(script) ? script : "'" + script.replace(/'/g, "'\\''") + "'") + " --apply"
            : "this from the Shale repository: sudo python3 \"$PWD/scripts/install-power.py\" --apply")
        color: Theme.textMuted
        font.pixelSize: Theme.small
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        Process {
            id: scriptProbe
            command: ["test", "-f", tunedHint.script]
            onExited: code => tunedHint.scriptFound = code === 0
        }
    }
    C.Toggle {
        visible: Backend.capabilities.builtinPanel !== false
        Layout.fillWidth: true
        Layout.topMargin: Theme.gapXs
        text: "Lower refresh rate in power saver"
        selected: ShellState.setting("saverRefresh", true)
        onClicked: ShellState.setSetting("saverRefresh", !ShellState.setting("saverRefresh", true))
    }
}
