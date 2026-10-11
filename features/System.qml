import QtQuick
import QtQuick.Layouts
import Quickshell
import "../core"
import "../components" as C

// Live system usage: CPU, memory, disks, network and GPUs. The helper is sampled once a second (every two in
// power saver) only while this panel is open; the graphs keep the last minute.
// `mode` leaves room for more views, such as processes; the tab row appears once there is more than one.
FocusScope {
    id: root
    property string mode: "performance"
    readonly property var modes: [{key: "performance", title: "Performance"}]
    property var sample: null
    property var history: ({})
    readonly property int capacity: 60
    property string selected: "cpu"
    property bool alive: true
    property bool waiting: false
    property int generation: 0
    property string error: ""
    // check-ui renders fixed sample data so screenshots are deterministic; --open shows the real system.
    readonly property string previewDetail: Quickshell.env("SHALE_PREVIEW") === "system" && Quickshell.env("SHALE_SCREENSHOT") !== ""
        ? (Quickshell.env("SHALE_DETAIL") || "cpu") : ""
    Component.onDestruction: alive = false
    Component.onCompleted: if (previewDetail !== "") loadPreview(previewDetail)

    function poll() {
        if (previewDetail !== "" || waiting || !Backend.ready)
            return;
        waiting = true;
        const request = ++generation;
        // nvidia-smi keeps an NVIDIA card awake, so its usage is only asked for while that card is on screen.
        const nvidia = !!current && current.kind === "gpu" && current.item.vendor === "nvidia";
        Backend.request("system.sample", {nvidia: nvidia}, (result, failure) => {
            if (!alive || request !== generation)
                return;
            waiting = false;
            if (failure) {
                error = failure.message || "System data is unavailable.";
            } else {
                error = "";
                absorb(result);
            }
        });
    }
    Timer {
        interval: Theme.lowPower ? 2000 : 1000
        running: root.previewDetail === ""
        repeat: true
        triggeredOnStart: true
        onTriggered: root.poll()
    }
    Connections {
        target: Backend
        function onReadyChanged() {
            if (Backend.ready)
                root.poll();
        }
    }

    // One history list per series, newest last.
    function absorb(next) {
        const kept = {};
        const add = (key, value) => kept[key] = (history[key] || []).concat([Math.max(0, value || 0)]).slice(-capacity);
        add("cpu", next.cpu.usage);
        add("memory", next.memory.total > 0 ? 100 * next.memory.used / next.memory.total : 0);
        for (const disk of next.disks) {
            add("disk:" + disk.name, disk.busy);
            add("disk-read:" + disk.name, disk.read);
            add("disk-write:" + disk.name, disk.write);
        }
        for (const link of next.network) {
            add("net-rx:" + link.name, link.rx);
            add("net-tx:" + link.name, link.tx);
        }
        for (const gpu of next.gpus)
            add("gpu:" + gpu.id, gpuLevel(gpu));
        history = kept;
        sample = next;
    }
    function gpuLevel(gpu) {
        if (gpu.state === "asleep")
            return 0;
        if (gpu.usage !== null && gpu.usage !== undefined)
            return gpu.usage;
        return gpu.frequency !== null && gpu.frequencyMax ? 100 * gpu.frequency / gpu.frequencyMax : 0;
    }

    function bytes(value) {
        const units = ["B", "KB", "MB", "GB", "TB"];
        let amount = Math.max(0, value || 0), unit = 0;
        while (amount >= 1024 && unit < units.length - 1) {
            amount /= 1024;
            unit++;
        }
        return (unit === 0 ? Math.round(amount) : amount.toFixed(amount >= 100 ? 0 : 1)) + " " + units[unit];
    }
    function rate(value) {
        return bytes(value) + "/s";
    }
    function percent(value) {
        return value === null || value === undefined ? "–" : Math.round(value) + " %";
    }
    function temperature(value) {
        return value === null || value === undefined ? "–" : Math.round(value) + " °C";
    }
    function duration(seconds) {
        const days = Math.floor(seconds / 86400), hours = Math.floor(seconds % 86400 / 3600), minutes = Math.floor(seconds % 3600 / 60);
        return days > 0 ? days + " d " + hours + " h" : hours > 0 ? hours + " h " + minutes + " min" : minutes + " min";
    }
    // Throughput graphs scale to the busiest moment of the last minute, never below 64 KB/s.
    function scaleFor(series) {
        let top = 65536;
        for (const key of series)
            for (const value of history[key] || [])
                top = Math.max(top, value * 1.15);
        return top;
    }

    readonly property var resources: {
        const s = sample;
        if (!s)
            return [];
        const list = [];
        if (s.cpu.available)
            list.push({key: "cpu", kind: "cpu", title: "CPU", subtitle: s.cpu.frequency ? (s.cpu.frequency / 1000).toFixed(2) + " GHz" : s.cpu.cores.length + " threads",
                       value: percent(s.cpu.usage), series: ["cpu"], color: Theme.accent, model: s.cpu.model});
        if (s.memory.available)
            list.push({key: "memory", kind: "memory", title: "Memory", subtitle: bytes(s.memory.used) + " / " + bytes(s.memory.total),
                       value: percent(100 * s.memory.used / s.memory.total), series: ["memory"], color: Theme.activityApps[2], model: bytes(s.memory.total) + " total"});
        s.disks.forEach((disk, index) => list.push({key: "disk:" + disk.name, kind: "disk", item: disk, title: "Disk " + index,
                       subtitle: disk.mounts.map(mount => mount.path).join("  ") || disk.name, value: percent(disk.busy),
                       series: ["disk:" + disk.name], color: Theme.activityApps[4], model: disk.model}));
        // Connected adapters only, unless none is connected.
        const links = s.network.filter(link => link.up);
        (links.length ? links : s.network).forEach(link => list.push({key: "net:" + link.name, kind: "network", item: link,
                       title: link.kind === "wifi" ? "Wi-Fi" : "Ethernet", subtitle: link.up ? "↓ " + rate(link.rx) + "   ↑ " + rate(link.tx) : "Disconnected",
                       value: "", series: ["net-rx:" + link.name, "net-tx:" + link.name], color: Theme.activityApps[3], model: link.name, scaled: true}));
        s.gpus.forEach((gpu, index) => list.push({key: "gpu:" + gpu.id, kind: "gpu", item: gpu, title: "GPU " + index, subtitle: gpu.name,
                       value: gpu.state === "asleep" ? "Asleep" : gpu.usage !== null && gpu.usage !== undefined ? percent(gpu.usage)
                            : gpu.frequency !== null && gpu.frequency !== undefined ? (gpu.frequency > 0 ? Math.round(gpu.frequency) + " MHz" : "Idle") : "Awake",
                       series: ["gpu:" + gpu.id], color: Theme.activityApps[1], model: gpu.name}));
        return list;
    }
    readonly property var current: resources.find(resource => resource.key === selected) || resources[0] || null
    // Rows and stat cards are keyed by name and read their values from these, so a new sample updates them in place
    // instead of rebuilding every delegate each second (which reset scrolling, hover and animations).
    property var resourceKeys: []
    property var statLabels: []
    readonly property var resourceMap: {
        const map = {};
        for (const resource of resources)
            map[resource.key] = resource;
        return map;
    }
    readonly property var blank: ({key: "", title: "", subtitle: "", value: "", series: [""], color: Theme.accent, scaled: false})
    onResourcesChanged: keep("resourceKeys", resources.map(resource => resource.key))
    onStatsChanged: keep("statLabels", stats.map(stat => stat.label))
    function keep(name, list) {
        if (list.join("\n") !== root[name].join("\n"))
            root[name] = list;
    }
    readonly property int currentIndex: current ? resources.indexOf(current) : -1

    readonly property var stats: {
        const s = sample, c = current;
        if (!s || !c)
            return [];
        if (c.kind === "cpu")
            return [{label: "Utilization", value: percent(s.cpu.usage)},
                    {label: "Speed", value: s.cpu.frequency ? (s.cpu.frequency / 1000).toFixed(2) + " GHz" : "–"},
                    {label: "Processes", value: String(s.cpu.processes), note: s.cpu.threads + " threads"},
                    {label: "Up time", value: duration(s.uptime)},
                    {label: "Load", value: s.cpu.load[0].toFixed(2), note: s.cpu.load[1].toFixed(2) + " · " + s.cpu.load[2].toFixed(2) + " (5, 15 min)"},
                    {label: "Temperature", value: temperature(s.cpu.temperature)}]
                .concat(s.fans.map(fan => ({label: fan.label, value: fan.rpm + " rpm"})));
        if (c.kind === "memory")
            return [{label: "In use", value: bytes(s.memory.used), note: percent(100 * s.memory.used / s.memory.total)},
                    {label: "Available", value: bytes(s.memory.free)},
                    {label: "Cached", value: bytes(s.memory.cached), note: "Freed when needed"},
                    {label: "Swap", value: s.memory.swapTotal > 0 ? bytes(s.memory.swapUsed) : "None",
                     note: s.memory.swapTotal > 0 ? "of " + bytes(s.memory.swapTotal) : ""}];
        if (c.kind === "disk")
            return [{label: "Active time", value: percent(c.item.busy)},
                    {label: "Read", value: rate(c.item.read)},
                    {label: "Write", value: rate(c.item.write)},
                    {label: "Temperature", value: temperature(c.item.temperature)}];
        if (c.kind === "network")
            return [{label: "Receive", value: rate(c.item.rx)},
                    {label: "Send", value: rate(c.item.tx)},
                    {label: "Adapter", value: c.item.name},
                    {label: "State", value: c.item.up ? "Connected" : "Disconnected"}];
        const gpu = c.item;
        if (gpu.state === "asleep")
            return [{label: "State", value: "Asleep"}];
        const list = [];
        if (gpu.usage !== null && gpu.usage !== undefined)
            list.push({label: "Utilization", value: percent(gpu.usage)});
        if (gpu.frequency !== null && gpu.frequency !== undefined)
            // An idle Intel GPU sleeps in RC6 and reports 0 MHz.
            list.push({label: "Clock", value: gpu.frequency > 0 ? Math.round(gpu.frequency) + " MHz" : "Idle", note: gpu.frequencyMax ? "of " + Math.round(gpu.frequencyMax) + " MHz" : ""});
        if (gpu.memoryTotal)
            list.push({label: "Memory", value: bytes(gpu.memoryUsed), note: "of " + bytes(gpu.memoryTotal)});
        if (gpu.temperature !== null && gpu.temperature !== undefined)
            list.push({label: "Temperature", value: temperature(gpu.temperature)});
        // An NVIDIA card's figures arrive with the next sample after it is selected.
        return list.length ? list : [{label: "State", value: "Awake"}];
    }
    readonly property string graphCaption: !current ? "" : current.kind === "cpu" ? "Utilization" : current.kind === "memory" ? "Memory in use"
        : current.kind === "disk" ? "Active time" : current.kind === "network" ? "Throughput"
        : current.item.vendor === "intel" ? "Clock speed, % of maximum" : "Utilization"

    function move(step) {
        if (!resources.length)
            return;
        const index = Math.max(0, Math.min(resources.length - 1, currentIndex + step));
        selected = resources[index].key;
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
            move(event.key === Qt.Key_Down ? 1 : -1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
            move(event.key === Qt.Key_Home ? -resources.length : resources.length);
            event.accepted = true;
        }
    }

    component Card: Rectangle {
        color: Theme.surface
        radius: Theme.controlRadius
    }
    component Caption: C.Label {
        font.pixelSize: Theme.caption
        color: Theme.muted
    }
    component Stat: Card {
        id: stat
        property string label: ""
        property string value: ""
        property string note: ""
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.preferredHeight: 64
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 1
            C.Label { text: stat.label; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight }
            C.Label { text: stat.value; font.family: Theme.mono; font.pixelSize: 17; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
            Caption { visible: stat.note !== ""; text: stat.note; color: Theme.disabled; Layout.fillWidth: true; elide: Text.ElideRight }
        }
    }
    component Meter: Item {
        id: meter
        property real fraction: 0
        property color color: Theme.activityLevel3
        implicitHeight: 6
        Rectangle { anchors.fill: parent; radius: height / 2; color: Theme.raised }
        Rectangle {
            width: Math.max(meter.fraction > 0 ? height : 0, parent.width * Math.max(0, Math.min(1, meter.fraction)))
            height: parent.height
            radius: height / 2
            color: meter.color
            Behavior on width { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12
        RowLayout {
            visible: root.modes.length > 1
            spacing: 6
            Repeater {
                model: root.modes
                C.Button {
                    required property var modelData
                    text: modelData.title
                    selected: root.mode === modelData.key
                    implicitWidth: 110
                    onClicked: root.mode = modelData.key
                }
            }
        }
        C.EmptyState {
            visible: root.resources.length === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            glyph: "gauge"
            title: root.error !== "" ? "System data is unavailable" : root.sample ? "Nothing to show" : !Backend.ready ? "Waiting for the desktop helper" : "Reading the system…"
            description: root.error !== "" ? root.error : root.sample ? "This system doesn't report processor, memory, disk or network use." : ""
        }
        C.Label {
            visible: root.error !== "" && root.resources.length > 0
            text: "Not updating: " + root.error
            color: Theme.warning
            font.pixelSize: Theme.small
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        RowLayout {
            visible: root.resources.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16
            ListView {
                id: list
                Layout.preferredWidth: 236
                Layout.fillHeight: true
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                model: root.resourceKeys
                currentIndex: root.currentIndex
                Accessible.role: Accessible.List
                Accessible.name: "Resources"
                delegate: Rectangle {
                    id: row
                    required property string modelData
                    required property int index
                    readonly property var resource: root.resourceMap[modelData] || root.blank
                    readonly property bool current: !!root.current && root.current.key === modelData
                    width: list.width
                    height: 58
                    radius: Theme.controlRadius
                    color: current ? Theme.selection : rowArea.containsMouse ? Theme.hover : "transparent"
                    Accessible.role: Accessible.ListItem
                    Accessible.name: resource.title + ", " + (resource.value || resource.subtitle)
                    Accessible.selected: current
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.selected = row.modelData
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10
                        Rectangle {
                            Layout.preferredWidth: 64
                            Layout.preferredHeight: 34
                            radius: 6
                            color: Theme.raised
                            clip: true
                            C.Sparkline {
                                anchors.fill: parent
                                anchors.margins: 1
                                values: root.history[row.resource.series[0]] || []
                                secondary: row.resource.series.length > 1 ? root.history[row.resource.series[1]] || [] : []
                                maximum: row.resource.scaled ? root.scaleFor(row.resource.series) : 100
                                capacity: root.capacity
                                color: row.resource.color
                                lineWidth: 1.2
                            }
                        }
                        ColumnLayout {
                            spacing: 1
                            Layout.fillWidth: true
                            RowLayout {
                                Layout.fillWidth: true
                                C.Label { text: row.resource.title; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                C.Label { text: row.resource.value; font.family: Theme.mono; font.pixelSize: Theme.small; color: Theme.muted }
                            }
                            Caption { text: row.resource.subtitle; Layout.fillWidth: true; elide: Text.ElideRight }
                        }
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    C.Label { text: root.current ? root.current.title : ""; font.pixelSize: 22; font.weight: Font.DemiBold }
                    C.Label {
                        text: root.current ? root.current.model : ""
                        color: Theme.muted
                        horizontalAlignment: Text.AlignRight
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                    }
                }
                Card {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 190
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            Caption { text: root.graphCaption; Layout.fillWidth: true }
                            Caption {
                                visible: !!root.current && root.current.kind === "network"
                                text: "↓ Receive"
                                color: root.current ? root.current.color : Theme.muted
                            }
                            Caption {
                                visible: !!root.current && root.current.kind === "network"
                                text: "↑ Send"
                                color: Theme.activityWatching
                                Layout.leftMargin: 8
                            }
                            Caption {
                                Layout.leftMargin: 8
                                font.family: Theme.mono
                                text: !root.current ? "" : root.current.scaled ? root.rate(root.scaleFor(root.current.series)) : "100 %"
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Repeater {
                                model: [0.25, 0.5, 0.75]
                                Rectangle {
                                    required property real modelData
                                    width: parent.width
                                    height: 1
                                    y: Math.round(parent.height * modelData)
                                    color: Theme.border
                                    opacity: 0.5
                                }
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 1
                                color: Theme.border
                            }
                            C.Sparkline {
                                anchors.fill: parent
                                values: root.current ? root.history[root.current.series[0]] || [] : []
                                secondary: root.current && root.current.series.length > 1 ? root.history[root.current.series[1]] || [] : []
                                maximum: root.current && root.current.scaled ? root.scaleFor(root.current.series) : 100
                                capacity: root.capacity
                                color: root.current ? root.current.color : Theme.accent
                                lineWidth: 2
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Caption { text: "60 seconds"; color: Theme.disabled; Layout.fillWidth: true }
                            Caption { text: "Now"; color: Theme.disabled }
                        }
                    }
                }
                GridLayout {
                    Layout.fillWidth: true
                    columns: 4
                    columnSpacing: 8
                    rowSpacing: 8
                    Repeater {
                        model: root.statLabels
                        Stat {
                            required property string modelData
                            required property int index
                            label: modelData
                            value: root.stats[index] ? root.stats[index].value : ""
                            note: root.stats[index] ? root.stats[index].note || "" : ""
                        }
                    }
                }
                // Per-thread load, one bar each.
                ColumnLayout {
                    visible: !!root.current && root.current.kind === "cpu"
                    Layout.fillWidth: true
                    spacing: 6
                    Caption { text: "Threads" }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        Layout.maximumHeight: 36
                        spacing: 3
                        Repeater {
                            // A count, so the bars stay and animate from one sample to the next.
                            model: root.sample ? root.sample.cpu.cores.length : 0
                            Rectangle {
                                id: core
                                required property int index
                                readonly property real load: root.sample && root.sample.cpu.cores[index] !== undefined ? root.sample.cpu.cores[index] : 0
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 3
                                color: Theme.raised
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: Math.max(2, parent.height * core.load / 100)
                                    radius: 3
                                    color: Theme.accent
                                    opacity: 0.85
                                    Behavior on height { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }
                                }
                            }
                        }
                    }
                }
                // What the memory holds: in use, cached (reclaimable) and free.
                ColumnLayout {
                    visible: !!root.current && root.current.kind === "memory"
                    Layout.fillWidth: true
                    spacing: 6
                    readonly property var memory: root.sample ? root.sample.memory : ({total: 1, used: 0, cached: 0})
                    Caption { text: "Composition" }
                    Item {
                        id: composition
                        Layout.fillWidth: true
                        Layout.preferredHeight: 10
                        readonly property real usedPart: Math.min(1, parent.memory.used / Math.max(1, parent.memory.total))
                        readonly property real cachedPart: Math.min(1 - usedPart, parent.memory.cached / Math.max(1, parent.memory.total))
                        Rectangle { anchors.fill: parent; radius: 5; color: Theme.raised }
                        Rectangle { width: parent.width * composition.usedPart; height: parent.height; radius: 5; color: Theme.activityApps[2] }
                        Rectangle {
                            x: parent.width * composition.usedPart
                            width: parent.width * composition.cachedPart
                            height: parent.height
                            radius: 5
                            color: Theme.mix(Theme.raised, Theme.activityApps[2], 0.45)
                        }
                    }
                }
                // Space on each filesystem of this disk.
                ColumnLayout {
                    visible: !!root.current && root.current.kind === "disk" && root.current.item.mounts.length > 0
                    Layout.fillWidth: true
                    spacing: 8
                    Caption { text: "Space" }
                    Repeater {
                        model: root.current && root.current.kind === "disk" ? root.current.item.mounts.length : 0
                        ColumnLayout {
                            required property int index
                            readonly property var mount: root.current && root.current.kind === "disk" && root.current.item.mounts[index]
                                || ({path: "", used: 0, total: 1})
                            Layout.fillWidth: true
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                C.Label { text: mount.path; font.family: Theme.mono; font.pixelSize: Theme.small; Layout.fillWidth: true; elide: Text.ElideMiddle }
                                C.Label {
                                    text: root.bytes(mount.used) + " of " + root.bytes(mount.total)
                                    font.pixelSize: Theme.small
                                    color: mount.used / mount.total > 0.9 ? Theme.warning : Theme.muted
                                }
                            }
                            Meter {
                                Layout.fillWidth: true
                                fraction: mount.used / mount.total
                                color: mount.used / mount.total > 0.9 ? Theme.warning : Theme.activityApps[4]
                            }
                        }
                    }
                }
                Caption {
                    visible: !!root.current && root.current.kind === "gpu" && root.current.item.state === "asleep"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "Powered down to save energy. Shale doesn't query a sleeping GPU, so this panel never wakes it."
                }
                Item { Layout.fillHeight: true }
            }
        }
    }

    // Fixed data for check-ui screenshots.
    function loadPreview(detail) {
        const bare = detail === "bare", asleep = detail === "gpu-asleep";
        const make = (base, swing, phase) => Array.from({length: capacity}, (_, i) => Math.max(0, base + swing * Math.sin(i / 5 + phase) + swing / 2 * Math.sin(i / 2.3 + phase * 2)));
        const next = {
            time: 0, uptime: 93784,
            cpu: {available: !bare, model: "11th Gen Intel(R) Core(TM) i5-11400H @ 2.70GHz", usage: 23, cores: [31, 12, 45, 8, 22, 17, 60, 5, 14, 28, 9, 33],
                  frequency: 3120, load: [1.24, 0.98, 0.75], processes: 284, threads: 1192, temperature: 58},
            memory: {available: !bare, total: 16470024192, used: 6012954214, free: 10457069978, cached: 4335702016, swapTotal: 4294963200, swapUsed: 268435456},
            disks: bare ? [] : [
                {name: "nvme0n1", model: "SAMSUNG MZALQ512HALU-000L2", read: 1288490, write: 335544, busy: 4, temperature: 34.9,
                 mounts: [{path: "/", total: 501863112704, used: 58992025600}, {path: "/boot", total: 1071628288, used: 543440896}]},
                {name: "nvme1n1", model: "Micron_2400_MTFDKBA512QFM", read: 0, write: 0, busy: 0, temperature: 30.9, mounts: [{path: "/home", total: 502920011776, used: 477774011187}]}],
            network: bare ? [] : [{name: "wlan0", kind: "wifi", up: true, rx: 2411724, tx: 180224}, {name: "enp47s0", kind: "ethernet", up: false, rx: 0, tx: 0}],
            gpus: bare ? [] : [
                {id: "card0", vendor: "nvidia", name: "NVIDIA GeForce RTX 3050 Mobile", state: asleep ? "asleep" : "active", usage: asleep ? null : 41,
                 memoryUsed: asleep ? null : 1288490188, memoryTotal: asleep ? null : 4294967296, temperature: asleep ? null : 52, frequency: null, frequencyMax: null},
                {id: "card1", vendor: "intel", name: "Intel UHD Graphics", state: "active", usage: null, memoryUsed: null, memoryTotal: null, temperature: null, frequency: 633, frequencyMax: 1450}],
            fans: bare ? [] : [{label: "CPU fan", rpm: 3100}, {label: "GPU fan", rpm: 3200}]
        };
        history = {"cpu": make(24, 10, 0), "memory": make(37, 1.5, 1), "disk:nvme0n1": make(4, 4, 2), "disk:nvme1n1": make(1, 1, 3),
                   "net-rx:wlan0": make(1600000, 1200000, 4), "net-tx:wlan0": make(160000, 120000, 5),
                   "gpu:card0": asleep ? make(0, 0, 0) : make(40, 15, 6), "gpu:card1": make(40, 20, 7)};
        sample = next;
        selected = ({memory: "memory", disk: "disk:nvme0n1", network: "net:wlan0", gpu: "gpu:card0", "gpu-asleep": "gpu:card0"})[detail] || "cpu";
    }
}
