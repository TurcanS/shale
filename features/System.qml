import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C
import "../core/format.js" as Format

// Live system usage: CPU, memory, disks, network and GPUs on the left, the chosen device's graph and figures on the
// right, and the busiest processes under them. The helper is sampled once a second (every two in power saver) while
// this panel is open. The helper also keeps the graphs' last five minutes, sampled every two seconds (four in power
// saver) while the panel is closed and not at all while locked, so the panel opens on them.
FocusScope {
    id: root
    readonly property string title: "System monitor"
    readonly property int panelWidth: 960
    readonly property int panelHeight: 660
    // Uptime and process count beside the title; while the helper is away, why the numbers have stopped.
    readonly property string headerNote: error !== "" && sample ? "Not updating: " + error
        : sample ? "Up " + duration(sample.uptime) + " · " + sample.cpu.processes + " processes" : ""
    readonly property Component headerTools: rangeTool
    property var sample: null
    // Graph series → [time, value] pairs, oldest first; appended to in place, with `revision` bumped for redraws.
    property var history: ({})
    property int revision: 0
    property real now: 0
    readonly property int window: 300
    readonly property int span: ShellState.setting("systemWindow", 60) === 300 ? 300 : 60
    // The first sample brings the helper's history; later ones add a point each.
    property bool needsHistory: true
    property string selected: "cpu"
    property bool waiting: false
    property int generation: 0
    property string error: ""
    // Processes: the sort the helper lists them by, the one whose End was pressed once ("pid:start"), and the ones
    // ended here, hidden until the helper stops listing them.
    property string processSort: "cpu"
    property string armed: ""
    property var ended: []

    Component {
        id: rangeTool
        C.Segmented {
            fill: false
            segmentHeight: 32
            model: [{key: 60, text: "1 min", accessibleName: "Show the last minute"}, {key: 300, text: "5 min", accessibleName: "Show the last 5 minutes"}]
            current: root.span
            onActivated: key => ShellState.setSetting("systemWindow", key)
        }
    }

    function poll() {
        if (waiting)
            return;
        if (!Backend.ready) {
            // Shown over the last numbers, so they are never read as live while the helper restarts.
            if (sample)
                error = "The desktop helper is restarting.";
            return;
        }
        waiting = true;
        const request = ++generation;
        // nvidia-smi keeps an NVIDIA card awake, so its usage is only asked for while that card is on screen.
        const nvidia = !!current && current.kind === "gpu" && current.item.vendor === "nvidia";
        Backend.request("system.sample", {nvidia: nvidia, history: needsHistory, processes: processSort}, (result, failure) => {
            if (request !== generation)
                return;
            waiting = false;
            if (failure) {
                error = failure.message || "System data is unavailable.";
            } else {
                error = "";
                absorb(result);
            }
        }, {owner: root});
    }
    Timer {
        id: pollTimer
        interval: Theme.lowPower ? 2000 : 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.poll()
    }
    Connections {
        target: Backend
        function onReadyChanged() {
            if (Backend.ready) {
                // A restarted helper has its own history.
                root.needsHistory = true;
                root.poll();
            }
        }
    }

    // Arrays are extended in place rather than copied each second; a new or vanished series replaces the map.
    function absorb(next) {
        if (next.history) {
            history = next.history;
            needsHistory = false;
        } else {
            const cutoff = next.time - window;
            let changed = false;
            for (const key in next.recorded) {
                if (!history[key]) {
                    history[key] = [];
                    changed = true;
                }
                history[key].push([next.time, next.recorded[key]]);
            }
            for (const key in history) {
                const points = history[key];
                while (points.length && points[0][0] < cutoff)
                    points.shift();
                if (!points.length) {
                    delete history[key];
                    changed = true;
                }
            }
            if (changed)
                history = Object.assign({}, history);
        }
        now = next.time;
        revision++;
        // Forget ended processes once the helper no longer lists them.
        if (ended.length && next.processes) {
            const listed = next.processes.map(process => processKey(process));
            ended = ended.filter(key => listed.indexOf(key) >= 0);
        }
        sample = next;
    }

    function bytes(value) {
        return Format.bytes(value);
    }
    // "6.3 / 15.3 GB" when both share a unit.
    function bytesOf(part, whole) {
        const a = bytes(part), b = bytes(whole);
        return a.split(" ")[1] === b.split(" ")[1] ? a.split(" ")[0] + " / " + b : a + " / " + b;
    }
    function rate(value) {
        return bytes(value) + "/s";
    }
    function known(value) {
        return Format.known(value);
    }
    function percent(value) {
        return known(value) ? Math.round(value) + "%" : "–";
    }
    function temperature(value) {
        return known(value) ? Math.round(value) + " °C" : "–";
    }
    function duration(seconds) {
        return Format.span(seconds);
    }
    // "11th Gen Intel(R) Core(TM) i5-11400H @ 2.70GHz" → "Intel Core i5-11400H", and its base clock.
    function cpuName(model) {
        return (model || "").replace(/\((R|TM|tm|r)\)/g, "").replace(/@.*$/, "").replace(/\b\d+(st|nd|rd|th) Gen\b/i, "")
            .replace(/\bCPU\b/, "").replace(/\s*\d+-Core Processor/i, "").replace(/\s+/g, " ").trim() || "Processor";
    }
    function baseClock(model) {
        const match = /@\s*([\d.]+)\s*GHz/i.exec(model || "");
        return match ? "base " + Number(match[1]).toFixed(2) : "";
    }
    // A disk's best-known mount: the system, then home, then whatever it holds.
    function diskPlace(disk) {
        const paths = disk.mounts.map(mount => mount.path);
        if (paths.indexOf("/") >= 0)
            return "System";
        if (paths.indexOf("/home") >= 0)
            return "Home";
        return paths.length ? paths[0] : disk.name;
    }
    // Throughput graphs scale to the busiest moment on screen, never below 64 KB/s.
    function scaleFor(series, seconds, revision) {
        let top = 65536;
        const start = now - seconds;
        for (const key of series) {
            const points = history[key] || [];
            for (let i = points.length - 1; i >= 0 && points[i][0] >= start; i--)
                if (points[i][1] !== null)
                    top = Math.max(top, points[i][1] * 1.15);
        }
        return top;
    }

    readonly property var devices: {
        const s = sample;
        if (!s)
            return [];
        const list = [];
        if (s.cpu.available)
            list.push({key: "cpu", kind: "cpu", title: "CPU",
                       subtitle: [percent(s.cpu.usage), s.cpu.frequency ? (s.cpu.frequency / 1000).toFixed(1) + " GHz" : "", known(s.cpu.temperature) ? temperature(s.cpu.temperature) : ""].filter(part => part).join(" · "),
                       value: percent(s.cpu.usage), series: ["cpu"], model: cpuName(s.cpu.model) + " · " + s.cpu.cores.length + " threads"});
        if (s.memory.available)
            list.push({key: "memory", kind: "memory", title: "Memory", subtitle: bytesOf(s.memory.used, s.memory.total),
                       value: percent(100 * s.memory.used / s.memory.total), series: ["memory"], model: bytes(s.memory.total) + " in all"});
        s.disks.forEach((disk, index) => list.push({key: "disk:" + disk.name, kind: "disk", item: disk, title: "Disk " + index,
                       subtitle: diskPlace(disk) + " · " + percent(disk.busy) + " active", value: percent(disk.busy),
                       series: ["disk:" + disk.name], model: disk.model !== disk.name ? disk.model + " · " + disk.name : disk.name}));
        // Connected adapters only, unless none is connected.
        const links = s.network.filter(link => link.up);
        (links.length ? links : s.network).forEach(link => list.push({key: "net:" + link.name, kind: "network", item: link,
                       title: link.kind === "wifi" ? "Wi-Fi" : "Ethernet", subtitle: link.up ? "↓ " + rate(link.rx) + " · ↑ " + rate(link.tx) : "Disconnected",
                       value: link.up ? rate(link.rx) : "", series: ["net-rx:" + link.name, "net-tx:" + link.name], model: link.name, scaled: true}));
        s.gpus.forEach((gpu, index) => {
            const asleep = gpu.state === "asleep";
            const level = asleep ? "Asleep" : known(gpu.usage) ? percent(gpu.usage)
                : known(gpu.frequency) ? (gpu.frequency > 0 ? Math.round(gpu.frequency) + " MHz" : "Idle") : "Awake";
            list.push({key: "gpu:" + gpu.id, kind: "gpu", item: gpu, title: s.gpus.length > 1 ? "GPU " + index : "GPU",
                       subtitle: asleep || !known(gpu.usage) && !known(gpu.frequency) ? level : level + " · " + gpu.name,
                       value: asleep ? "" : level, asleep: asleep, series: ["gpu:" + gpu.id], model: gpu.name});
        });
        return list;
    }
    readonly property var current: devices.find(resource => resource.key === selected) || devices[0] || null
    // Rows and stat tiles are keyed by name and read their values from these, so a new sample updates them in place
    // instead of rebuilding every delegate each second (which reset scrolling, hover and animations).
    property var deviceKeys: []
    property var statLabels: []
    readonly property var deviceMap: {
        const map = {};
        for (const resource of devices)
            map[resource.key] = resource;
        return map;
    }
    readonly property var blank: ({key: "", title: "", subtitle: "", value: "", series: [""], scaled: false, asleep: false})
    onDevicesChanged: keep("deviceKeys", devices.map(resource => resource.key))
    onStatsChanged: keep("statLabels", stats.map(stat => stat.label))
    function keep(name, list) {
        if (list.join("\n") !== root[name].join("\n"))
            root[name] = list;
    }
    readonly property int currentIndex: current ? devices.indexOf(current) : -1

    readonly property var stats: {
        const s = sample, c = current;
        if (!s || !c)
            return [];
        if (c.kind === "cpu")
            return [{label: "Utilisation", value: percent(s.cpu.usage), note: s.cpu.threads + " threads running"},
                    {label: "Speed", value: s.cpu.frequency ? (s.cpu.frequency / 1000).toFixed(2) + " GHz" : "–", note: baseClock(s.cpu.model)},
                    {label: "Temperature", value: temperature(s.cpu.temperature), note: known(s.cpu.temperature) ? "package" : ""},
                    {label: "Load", value: s.cpu.load[0].toFixed(2), note: s.cpu.load[1].toFixed(2) + " · " + s.cpu.load[2].toFixed(2)}]
                .concat(s.fans.map(fan => ({label: fan.label, value: fan.rpm > 0 ? fan.rpm + " rpm" : "Stopped", note: fan.rpm > 0 ? "" : "quiet at this load"})));
        if (c.kind === "memory")
            return [{label: "In use", value: bytes(s.memory.used), note: percent(100 * s.memory.used / s.memory.total)},
                    {label: "Available", value: bytes(s.memory.free)},
                    {label: "Cached", value: bytes(s.memory.cached), note: "freed when needed"},
                    {label: "Swap", value: s.memory.swapTotal > 0 ? bytes(s.memory.swapUsed) : "None",
                     note: s.memory.swapTotal > 0 ? "of " + bytes(s.memory.swapTotal) : ""}];
        if (c.kind === "disk")
            return [{label: "Active time", value: percent(c.item.busy)},
                    {label: "Kind", value: ({nvme: "NVMe SSD", ssd: "SSD", hdd: "Hard disk", removable: "Removable"})[c.item.kind] || "Disk",
                     note: c.item.size ? bytes(c.item.size) : ""},
                    {label: "Read", value: rate(c.item.read)},
                    {label: "Write", value: rate(c.item.write)},
                    {label: "Temperature", value: temperature(c.item.temperature)}]
                // Space on each filesystem of this disk.
                .concat(c.item.mounts.map(mount => ({label: mount.path === "/" ? "Used on /" : "Used on " + mount.path, value: bytes(mount.used),
                                                     note: "of " + bytes(mount.total), full: mount.used / mount.total > 0.9})));
        if (c.kind === "network")
            return [{label: "Receive", value: rate(c.item.rx)},
                    {label: "Send", value: rate(c.item.tx)},
                    {label: "Adapter", value: c.item.name},
                    {label: "State", value: c.item.up ? "Connected" : "Disconnected"}];
        const gpu = c.item;
        if (gpu.state === "asleep")
            return [{label: "State", value: "Asleep"}];
        const list = [];
        if (known(gpu.usage))
            list.push({label: "Utilisation", value: percent(gpu.usage)});
        if (known(gpu.frequency))
            // An idle Intel GPU sleeps in RC6 and reports 0 MHz.
            list.push({label: "Clock", value: gpu.frequency > 0 ? Math.round(gpu.frequency) + " MHz" : "Idle", note: gpu.frequencyMax ? "of " + Math.round(gpu.frequencyMax) + " MHz" : ""});
        if (gpu.memoryTotal)
            list.push({label: "Memory", value: bytes(gpu.memoryUsed), note: "of " + bytes(gpu.memoryTotal)});
        if (known(gpu.temperature))
            list.push({label: "Temperature", value: temperature(gpu.temperature)});
        // An NVIDIA card's figures arrive with the next sample after it is selected.
        return list.length ? list : [{label: "State", value: "Awake"}];
    }
    readonly property string graphCaption: !current ? "" : current.kind === "gpu" && current.item.vendor === "intel" && !known(current.item.usage)
        ? "Clock speed, share of its maximum" : ""

    // The busiest processes, less the ones just ended here.
    readonly property var processes: (sample && sample.processes || []).filter(process => ended.indexOf(processKey(process)) < 0)
    function processKey(process) {
        return process ? process.pid + ":" + process.start : "";
    }
    function sortBy(key) {
        if (processSort === key)
            return;
        processSort = key;
        armed = "";
        pollTimer.restart();
    }
    // The first press asks "Sure?"; the second, on the same process, ends it.
    function end(process) {
        const key = processKey(process);
        if (armed !== key) {
            armed = key;
            disarm.restart();
            return;
        }
        armed = "";
        ended = ended.concat([key]);
        Backend.request("system.end", {pid: process.pid, start: process.start}, (result, failure) => {
            // The helper says why (already gone, another user's); show the row again.
            if (failure)
                root.ended = root.ended.filter(entry => entry !== key);
        }, {owner: root});
    }
    Timer {
        id: disarm
        interval: 4000
        onTriggered: root.armed = ""
    }

    function move(step) {
        if (!devices.length)
            return;
        const index = Math.max(0, Math.min(devices.length - 1, currentIndex + step));
        selected = devices[index].key;
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
            move(event.key === Qt.Key_Down ? 1 : -1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
            move(event.key === Qt.Key_Home ? -devices.length : devices.length);
            event.accepted = true;
        }
    }

    C.EmptyState {
        visible: root.devices.length === 0
        anchors.fill: parent
        glyph: "gauge"
        title: root.error !== "" ? "System data is unavailable" : root.sample ? "Nothing to show" : !Backend.ready ? "Waiting for the desktop helper" : "Reading the system…"
        description: root.error !== "" ? root.error : root.sample ? "This system doesn't report processor, memory, disk or network use." : ""
    }

    RowLayout {
        visible: root.devices.length > 0
        anchors.fill: parent
        spacing: 10

        // Devices: one key each with its last minute, filling the column while they fit.
        ListView {
            id: list
            readonly property real rowHeight: count ? Math.max(62, (height - spacing * (count - 1)) / count) : 62
            Layout.preferredWidth: 250
            Layout.fillHeight: true
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: root.deviceKeys
            currentIndex: root.currentIndex
            Accessible.role: Accessible.List
            Accessible.name: "Devices"
            delegate: Rectangle {
                id: row
                required property string modelData
                required property int index
                readonly property var resource: root.deviceMap[modelData] || root.blank
                readonly property bool current: !!root.current && root.current.key === modelData
                width: list.width
                height: list.rowHeight
                // Powering up, the device keys seat one after another under the light bar.
                opacity: rowIn.shown
                transform: C.Cascade {
                    id: rowIn
                    panel: "system"
                    order: row.index
                    dy: -10
                    spacing: 1.4
                }
                radius: 14
                color: current ? Theme.accentSoft : rowArea.containsMouse ? Theme.mix(Theme.module, Theme.text, 0.04) : Theme.module
                border.width: 1
                border.color: current ? Theme.accentLine : "transparent"
                Accessible.role: Accessible.ListItem
                Accessible.name: resource.title + ", " + resource.subtitle
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
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10
                    Rectangle {
                        Layout.preferredWidth: 72
                        Layout.preferredHeight: 36
                        radius: 6
                        color: Theme.well
                        clip: true
                        C.Sparkline {
                            anchors.fill: parent
                            values: root.history[row.resource.series[0]] || []
                            secondary: row.resource.series.length > 1 ? root.history[row.resource.series[1]] || [] : []
                            maximum: row.resource.scaled ? root.scaleFor(row.resource.series, 60, root.revision) : 100
                            span: 60
                            end: root.now
                            revision: root.revision
                            color: row.resource.asleep ? Theme.textFaint : Theme.accent
                            filled: !row.resource.asleep
                            lineWidth: 1.5
                        }
                    }
                    ColumnLayout {
                        spacing: 1
                        Layout.fillWidth: true
                        C.Label { text: row.resource.title; font.pixelSize: 14; font.weight: Font.DemiBold; Layout.fillWidth: true }
                        C.Label { text: row.resource.subtitle; font.pixelSize: 12; color: Theme.textDim; Layout.fillWidth: true }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            // The chosen device: name, model and its reading, the graph, then its figures.
            C.Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    anchors.topMargin: 14
                    anchors.bottomMargin: 14
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        C.Label { text: root.current ? root.current.title : ""; font.pixelSize: 20; font.weight: 650; elide: Text.ElideNone; Layout.alignment: Qt.AlignBaseline }
                        C.Label {
                            text: root.current ? root.current.model : ""
                            font.pixelSize: 13
                            color: Theme.textDim
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignBaseline
                        }
                        C.Label {
                            text: root.current ? root.current.value : ""
                            font.pixelSize: 22
                            font.weight: 650
                            font.features: ({"tnum": 1})
                            color: Theme.accent
                            elide: Text.ElideNone
                            Layout.alignment: Qt.AlignBaseline
                        }
                    }
                    Rectangle {
                        visible: !!root.current && !root.current.asleep
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Theme.radiusCard
                        color: Theme.well
                        clip: true
                        Repeater {
                            model: [0.25, 0.5, 0.75]
                            Rectangle {
                                required property real modelData
                                width: parent.width
                                height: 1
                                y: Math.round(parent.height * modelData)
                                color: Theme.separator
                            }
                        }
                        C.Sparkline {
                            anchors.fill: parent
                            anchors.topMargin: 6
                            values: root.current ? root.history[root.current.series[0]] || [] : []
                            secondary: root.current && root.current.series.length > 1 ? root.history[root.current.series[1]] || [] : []
                            maximum: root.current && root.current.scaled ? root.scaleFor(root.current.series, root.span, root.revision) : 100
                            span: root.span
                            end: root.now
                            revision: root.revision
                            lineWidth: 2
                        }
                        // Receive in the accent and send in the second colour; throughput graphs say what the top is.
                        RowLayout {
                            x: 10
                            y: 8
                            spacing: 12
                            visible: !!root.current && root.current.kind === "network"
                            Repeater {
                                model: [{text: "Receive", color: Theme.accent}, {text: "Send", color: Theme.second}]
                                RowLayout {
                                    required property var modelData
                                    spacing: 5
                                    Rectangle { Layout.preferredWidth: 10; Layout.preferredHeight: 3; radius: 2; color: parent.modelData.color }
                                    C.Label { text: parent.modelData.text; font.pixelSize: 12; color: Theme.textSecondary }
                                }
                            }
                        }
                        C.Label {
                            visible: text !== ""
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.leftMargin: 10
                            anchors.topMargin: 8
                            text: root.graphCaption
                            font.pixelSize: 11
                            color: Theme.textDim
                        }
                        C.Label {
                            visible: !!root.current && !!root.current.scaled
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.rightMargin: 10
                            anchors.topMargin: 8
                            text: root.current && root.current.scaled ? root.rate(root.scaleFor(root.current.series, root.span, root.revision)) : ""
                            font.pixelSize: 11
                            font.family: Theme.mono
                            color: Theme.textDim
                        }
                        C.Label {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 10
                            anchors.bottomMargin: 6
                            text: root.span === 300 ? "5 min ago" : "1 min ago"
                            font.pixelSize: 11
                            color: Theme.textDim
                        }
                        C.Label {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.rightMargin: 10
                            anchors.bottomMargin: 6
                            text: "now"
                            font.pixelSize: 11
                            color: Theme.textDim
                        }
                    }
                    // A sleeping GPU is never read, so there is no graph to draw.
                    Rectangle {
                        visible: !!root.current && !!root.current.asleep
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Theme.radiusCard
                        color: Theme.well
                        ColumnLayout {
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 80, 360)
                            spacing: 8
                            C.Icon { name: "moon"; size: 28; color: Theme.textMuted; Layout.alignment: Qt.AlignHCenter }
                            C.Label { text: "Asleep to save power"; font.pixelSize: 15; font.weight: Font.DemiBold; Layout.alignment: Qt.AlignHCenter }
                            C.Label {
                                text: "Shale doesn't read a sleeping GPU, so opening this never wakes it."
                                font.pixelSize: 13
                                color: Theme.textMuted
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                                lineHeight: 1.2
                                Layout.fillWidth: true
                            }
                        }
                    }
                    // Load on each thread, one bar each.
                    RowLayout {
                        visible: !!root.current && root.current.kind === "cpu"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 18
                        Layout.maximumHeight: 18
                        spacing: 3
                        Accessible.role: Accessible.Chart
                        Accessible.name: "Load on each thread"
                        Repeater {
                            // A count, so the bars stay and animate from one sample to the next.
                            model: root.sample ? root.sample.cpu.cores.length : 0
                            Rectangle {
                                id: core
                                required property int index
                                readonly property real load: root.sample && root.sample.cpu.cores[index] !== undefined ? root.sample.cpu.cores[index] : 0
                                // The self-test as the panel powers up: each thread's bar sweeps to full and falls back to its load.
                                readonly property real test: selfTest.progress
                                readonly property real shown: test >= 1 ? load : test < 0.45 ? 100 * Motion.out(test / 0.45) : Motion.lerp(100, load, Motion.smooth((test - 0.45) / 0.55))
                                transform: C.Cascade {
                                    id: selfTest
                                    panel: "system"
                                    order: core.index
                                    dy: 0
                                    limit: 32
                                    spacing: 0.5
                                    duration: 620
                                    overshoot: 0
                                }
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                // Bare bars on the graph's floor: empty wells read as a row of broken boxes at idle.
                                color: "transparent"
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: Math.max(2, parent.height * Math.min(100, core.shown) / 100)
                                    radius: 2
                                    color: core.shown >= 1 ? Theme.accent : Theme.key
                                    Behavior on height {
                                        enabled: core.test >= 1
                                        NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic }
                                    }
                                }
                            }
                        }
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 4
                        columnSpacing: 6
                        rowSpacing: 6
                        Repeater {
                            // Padded with blank tiles to whole rows, so a lone tile keeps a quarter of the width.
                            model: root.statLabels.concat(Array((4 - root.statLabels.length % 4) % 4).fill(""))
                            C.Stat {
                                required property string modelData
                                required property int index
                                readonly property var entry: root.stats[index] || ({})
                                radius: Theme.radiusKey
                                inset: 9
                                valueSize: 16
                                Layout.preferredHeight: 62
                                opacity: modelData === "" ? 0 : 1
                                label: modelData
                                value: entry.value || ""
                                note: entry.note || " "
                                noteColor: entry.full ? Theme.warning : Theme.textDim
                            }
                        }
                    }
                }
            }

            // Processes, busiest first by CPU or memory; End asks "Sure?" before it sends the process away.
            C.Card {
                Layout.fillWidth: true
                Layout.preferredHeight: 208
                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.topMargin: 10
                    anchors.bottomMargin: 10
                    spacing: 2
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        Layout.leftMargin: 6
                        Layout.rightMargin: 6
                        spacing: 12
                        C.Label { text: "Processes"; font.pixelSize: 14; font.weight: 650; Layout.fillWidth: true }
                        Repeater {
                            model: [{key: "cpu", text: "CPU"}, {key: "memory", text: "Memory"}]
                            C.Button {
                                id: sortKey
                                required property var modelData
                                readonly property bool on: root.processSort === modelData.key
                                text: modelData.text + (on ? " ↓" : "")
                                flat: true
                                labelSize: 12
                                implicitHeight: 24
                                padding: 4
                                foreground: on || hovered || visualFocus ? Theme.text : Theme.textDim
                                hint: "Sort by " + modelData.text.toLowerCase()
                                Accessible.checkable: true
                                Accessible.checked: on
                                Layout.preferredWidth: 70
                                onClicked: root.sortBy(modelData.key)
                                contentItem: C.Label {
                                    text: sortKey.text
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: sortKey.foreground
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                        }
                        Item { Layout.preferredWidth: 74 }
                    }
                    Repeater {
                        // Rows by position: each reads the process now in its place, so a new sample updates it in place.
                        model: Math.min(5, root.processes.length)
                        Rectangle {
                            id: processRow
                            required property int index
                            readonly property var process: root.processes[index] || ({pid: 0, start: 0, name: "", cpu: 0, memory: 0, own: false, protected: true})
                            readonly property bool sure: root.armed !== "" && root.armed === root.processKey(process)
                            readonly property bool endable: process.own && !process.protected
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            radius: 8
                            color: index % 2 === 0 ? Theme.moduleAlt : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                spacing: 12
                                Rectangle {
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    radius: 6
                                    color: Theme.key
                                    C.Label {
                                        anchors.centerIn: parent
                                        text: processRow.process.name.charAt(0).toUpperCase()
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: Theme.textSecondary
                                    }
                                }
                                C.Label { text: processRow.process.name; font.pixelSize: 13; Layout.fillWidth: true }
                                C.Label {
                                    text: processRow.process.cpu.toFixed(1) + "%"
                                    font.pixelSize: 13
                                    font.features: ({"tnum": 1})
                                    color: processRow.index === 0 && root.processSort === "cpu" ? Theme.accent : Theme.textSecondary
                                    horizontalAlignment: Text.AlignRight
                                    Layout.preferredWidth: 70
                                }
                                C.Label {
                                    text: root.bytes(processRow.process.memory)
                                    font.pixelSize: 13
                                    font.features: ({"tnum": 1})
                                    color: processRow.index === 0 && root.processSort === "memory" ? Theme.accent : Theme.textSecondary
                                    horizontalAlignment: Text.AlignRight
                                    Layout.preferredWidth: 70
                                }
                                C.Button {
                                    id: endKey
                                    text: processRow.sure ? "Sure?" : "End"
                                    enabled: processRow.endable
                                    labelSize: 12
                                    implicitHeight: 24
                                    cornerRadius: 7
                                    padding: 0
                                    hint: !processRow.process.own ? "Belongs to another user" : processRow.process.protected ? "Ending this would end your session" : ""
                                    foreground: !enabled ? Theme.textFaint : processRow.sure ? Theme.dangerText : Theme.text
                                    Accessible.name: (processRow.sure ? "Sure? End " : "End ") + processRow.process.name
                                    Layout.preferredWidth: 74
                                    onClicked: root.end(processRow.process)
                                    background: Rectangle {
                                        radius: 7
                                        color: !endKey.enabled ? Theme.module : processRow.sure ? Theme.tint(Theme.danger, 0.18)
                                             : endKey.hovered || endKey.visualFocus ? Theme.keyHover : Theme.key
                                        Behavior on color { ColorAnimation { duration: Theme.fast } }
                                    }
                                }
                            }
                        }
                    }
                    C.Label {
                        visible: root.processes.length === 0
                        text: root.sample ? "Reading processes…" : ""
                        font.pixelSize: 13
                        color: Theme.textDim
                        Layout.leftMargin: 6
                        Layout.topMargin: 6
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}
