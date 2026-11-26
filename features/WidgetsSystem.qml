import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C
import "../core/format.js" as Format

// The System card: processor, memory and temperature as rings. It asks the helper's system sampler every 5 s (10 s
// when effects are trimmed), only while it is on screen, and never for nvidia-smi or processes, so no sleeping GPU
// wakes for it. Opens the System monitor.
WidgetsCard {
    id: root
    property bool live: false
    property var sample: null
    property bool waiting: false
    readonly property var cpu: sample ? sample.cpu : null
    readonly property var memory: sample && sample.memory && sample.memory.available ? sample.memory : null
    panel: "system"
    padding: 16
    function known(value) {
        return Format.known(value);
    }
    function bytes(value) {
        return Format.bytes(value);
    }
    function poll() {
        if (waiting || !Backend.ready)
            return;
        waiting = true;
        Backend.request("system.sample", {}, (result, failure) => {
            root.waiting = false;
            if (!failure)
                root.sample = result;
        }, {owner: root});
    }
    Timer {
        interval: Theme.lowPower ? 10000 : 5000
        running: root.live
        repeat: true
        triggeredOnStart: true
        onTriggered: root.poll()
    }
    readonly property var meters: [
        {label: "CPU", value: cpu && known(cpu.usage) ? Math.round(cpu.usage) + "%" : "–", fraction: cpu && known(cpu.usage) ? cpu.usage / 100 : 0,
         color: Theme.accent},
        {label: "Memory", value: memory ? bytes(memory.used) : "–", fraction: memory && memory.total ? memory.used / memory.total : 0, color: Theme.second},
        {label: "Temperature", value: cpu && known(cpu.temperature) ? Math.round(cpu.temperature) + "°" : "–",
         fraction: cpu && known(cpu.temperature) ? Math.min(1, cpu.temperature / 100) : 0,
         color: cpu && known(cpu.temperature) && cpu.temperature >= 90 ? Theme.danger : Theme.textSecondary}
    ]
    ColumnLayout {
        anchors.fill: parent
        spacing: 10
        C.Label {
            text: "System"
            font.pixelSize: 15
            font.weight: Font.DemiBold
            Layout.fillWidth: true
        }
        Repeater {
            model: root.meters
            RowLayout {
                id: meter
                required property var modelData
                Layout.fillWidth: true
                spacing: 10
                Accessible.role: Accessible.StaticText
                Accessible.name: modelData.label + ", " + modelData.value
                C.Ring {
                    size: 36
                    thickness: 4
                    value: meter.modelData.fraction
                    color: meter.modelData.color
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    C.Label {
                        text: meter.modelData.label
                        color: Theme.textDim
                        font.pixelSize: 12
                        Layout.fillWidth: true
                    }
                    C.Label {
                        text: meter.modelData.value
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        font.features: ({"tnum": 1})
                        Layout.fillWidth: true
                    }
                }
            }
        }
        Item {
            Layout.fillHeight: true
        }
    }
}
