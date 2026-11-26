import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import "../core"
import "../core/paths.js" as Paths
import "../core/controlItems.js" as ControlItems
import "../services"
import "../components" as C
import "../core/format.js" as Format

FocusScope {
    id: root
    readonly property string title: ({wifi: "Network", bluetooth: "Network", audio: "Sound", power: "Battery & power", media: "Player", tray: "System tray", update: "Update", focus: "Focus"})[ShellState.detail] || "Control"
    // Beside the title on the main page: the battery, or the power mode; it opens Battery & power.
    readonly property string headerNote: {
        if (ShellState.detail !== "")
            return "";
        const mode = ({"power-saver": "Power saver", "balanced": "Balanced", "performance": "Performance"})[ShellState.profiles.active] || "";
        if (!Services.batteryAvailable)
            return mode || "Power modes";
        const seconds = Services.batterySeconds;
        const span = Format.shortSpan(seconds);
        return "Battery " + Math.round(Services.batteryPercent) + "%" + (Services.batteryCharging ? (span ? " · full in " + span : " · charging") : span ? " · " + span + " left" : "");
    }
    readonly property string noteHint: "Battery and power modes"
    function noteClicked() {
        ShellState.detail = "power";
    }
    readonly property bool canGoBack: ShellState.detail !== ""
    // Settings → Control center orders the tiles and buttons and turns parts off.
    readonly property var arrangement: ControlItems.layout(ShellState.setting("controlLayout", {}))
    readonly property var shownTiles: arrangement.tiles.filter(tile => tile.shown && (tile.id !== "wifi" || ShellState.wifiAvailable)
                                                                        && (tile.id !== "lid" || Backend.capabilities.lid !== false)
                                                                        && (tile.id !== "airdrop" || AirDrop.available)).map(tile => tile.id)
    // What a tile shows. Wi-Fi and Bluetooth also open their page; the others are plain switches.
    function tile(id) {
        if (id === "wifi") {
            const current = (ShellState.wifi.networks || []).find(n => n.connected);
            return {text: "Wi-Fi", glyph: ShellState.wifi.powered ? "wifi" : "wifi-off", selected: ShellState.wifi.state === "connected",
                    subtitle: root.pendingMethod === "wifi.power" ? "Updating…" : current ? current.name : ShellState.wifi.powered ? "Not connected" : "Off",
                    hint: ShellState.wifi.powered ? "Turn Wi-Fi off" : "Turn Wi-Fi on", detail: "wifi", detailHint: "Wi-Fi networks", enabled: !root.acting};
        }
        if (id === "bluetooth") {
            const connected = Services.bluetoothDevices.filter(d => d.connected);
            const count = connected.length;
            // One device reads as its name and battery; more as a count.
            const one = count === 1 ? (connected[0].name || "1 connected") + (connected[0].batteryAvailable ? " · " + Math.round(connected[0].battery * 100) + "%" : "") : "";
            return {text: "Bluetooth", glyph: "bluetooth", selected: Services.bluetoothEnabled,
                    subtitle: !Services.bluetoothAvailable ? "Unavailable" : one || (count ? count + " connected" : Services.bluetoothEnabled ? "On" : "Off"),
                    hint: Services.bluetoothEnabled ? "Turn Bluetooth off" : "Turn Bluetooth on", detail: "bluetooth", detailHint: "Bluetooth devices",
                    enabled: Services.bluetoothAvailable};
        }
        // Visible to devices nearby for ten minutes; the arrow opens the AirDrop panel.
        if (id === "airdrop") {
            const visible = AirDrop.mode === "visible";
            return {text: "AirDrop", glyph: "airdrop", selected: visible,
                    subtitle: AirDrop.countPending > 0 ? "Request waiting" : AirDrop.progress >= 0 ? Math.round(AirDrop.progress * 100) + "%"
                            : AirDrop.error ? "Needs attention"
                            : visible ? "Visible · " + Math.ceil(AirDrop.visibleLeft / 60) + " min" : AirDrop.mode === "background" ? "Background" : "Off",
                    hint: visible ? "Stop being visible" : "Be visible for 10 minutes", detail: "airdrop", detailHint: "AirDrop", enabled: true};
        }
        const toggle = ({
                dnd: {text: "Do not disturb", glyph: "bell-off", on: ShellState.setting("dnd", false), subtitle: "Popups hidden", busy: false},
                awake: {text: "Stay awake", glyph: "moon", on: ShellState.presentation, subtitle: "Screen stays on", busy: false},
                grayscale: {text: "Greyscale", glyph: "palette", on: ShellState.grayscale, subtitle: "Colours off", busy: ShellState.grayscaleBusy},
                lid: {text: "Lid closed", glyph: "laptop", on: ShellState.lidAwake, subtitle: "Stays awake", busy: ShellState.lidBusy}
            })[id];
        return {text: toggle.text, glyph: toggle.glyph, selected: toggle.on, subtitle: toggle.on ? toggle.subtitle : "Off", hint: "",
                detail: "", detailHint: "", enabled: !toggle.busy, switch: true};
    }
    function activateTile(id) {
        if (id === "wifi")
            root.perform("wifi.power", {powered: !ShellState.wifi.powered}, () => ShellState.refreshWifi());
        else if (id === "bluetooth")
            Services.bluetoothPower(!Services.bluetoothEnabled);
        else if (id === "airdrop")
            AirDrop.toggleVisible();
        else if (id === "dnd")
            ShellState.setSetting("dnd", !ShellState.setting("dnd", false));
        else if (id === "awake")
            ShellState.presentation = !ShellState.presentation;
        else if (id === "grayscale")
            ShellState.toggleGrayscale();
        else if (id === "lid")
            ShellState.toggleLidAwake();
    }
    function back() {
        ShellState.detail = "";
    }
    // The Player is laid out wider, at its own 460 px, and Focus at 440.
    readonly property int panelWidth: ShellState.detail === "media" ? 460 : ShellState.detail === "focus" ? 440 : 420
    readonly property var headerChip: ShellState.detail === "focus" ? focusView.chip : null
    // Fits the page, header and padding included, within an 820 px ceiling (the host keeps it on the screen).
    readonly property int panelHeight: preferredContentHeight > 0 ? Math.max(200, Math.min(820, preferredContentHeight + 70)) : 620
    readonly property Component headerTools: ShellState.detail === "" ? settingsTool : ["wifi", "power", "update"].indexOf(ShellState.detail) >= 0 ? refreshTool : null
    // Settings → Control center is one of Settings' pages; this is the way there.
    Component {
        id: settingsTool
        C.Button {
            id: settingsKey
            glyph: "sliders"
            hint: "Settings"
            implicitWidth: 32
            implicitHeight: 32
            background: Rectangle {
                radius: Theme.radiusKey
                color: settingsKey.hovered || settingsKey.down || settingsKey.visualFocus ? Theme.mix(Theme.module, Theme.text, 0.05) : Theme.module
                Behavior on color {
                    ColorAnimation {
                        duration: Theme.fast
                    }
                }
            }
            onClicked: ShellState.open("settings")
        }
    }
    Component {
        id: refreshTool
        C.Button {
            glyph: "refresh"
            flat: true
            hint: "Refresh"
            implicitWidth: 32
            implicitHeight: 32
            enabled: !root.busy && !Updates.checking
            onClicked: root.refresh(true)
        }
    }
    readonly property int preferredContentHeight: Math.ceil(controlContent.implicitHeight + (errorLabel.visible ? errorLabel.implicitHeight + 10 : 0) + (actionFooter.visible ? actionFooter.implicitHeight + 10 : 0))
    property string error: ""
    // The output's live level, which the Sound view's strips read.
    readonly property alias outputMeter: outputLevel
    // A request is running exactly while pendingMethod names it.
    readonly property bool busy: pendingMethod !== ""
    // Busy with something the user asked for; background list refreshes don't dim the page.
    readonly property bool acting: busy && ["wifi.list", "power.profiles"].indexOf(pendingMethod) < 0
    // The VPN profile being connected or disconnected, while that request runs.
    property string pendingVpn: ""
    property string pendingMethod: ""
    property int requestGeneration: 0
    property var selectedNetwork: null
    // Kept outside the network rows: refreshes recreate them while you type.
    property string passwordDraft: ""
    // Scan's short wait for results, read by the Wi-Fi view.
    readonly property Timer scanTimer: scanWait
    // The form for a network that doesn't announce its name.
    property bool hiddenOpen: false
    // The DNS form under the network in use: the access point it was opened for (none when closed), the choice and
    // the servers typed for Custom.
    property string dnsPath: ""
    property string dnsMode: "auto"
    property string dnsDraft: ""
    function openDns(network) {
        const dns = network.dns || {mode: "auto", servers: []};
        forgetPath = "";
        dnsMode = dns.mode;
        dnsDraft = dns.mode === "custom" ? dns.servers.join(" ") : "";
        dnsPath = network.path;
    }
    function saveDns() {
        if (busy || !dnsPath || (dnsMode === "custom" && dnsDraft.trim() === ""))
            return;
        perform("wifi.dns", {path: dnsPath, mode: dnsMode, servers: dnsDraft}, () => {
            dnsPath = "";
            refresh();
        });
    }
    TrayMenu {
        id: trayMenu
    }
    property bool passwordVisible: false
    // The mixer's device list under its header: "out", "in" or none.
    property string deviceChooser: ""
    // Connected first, then paired, then nearby; nameless discoveries stay folded away.
    property bool showAllDevices: false
    function unnamed(device) {
        const name = device.name || "";
        return !name || /^([0-9a-f]{2}[-:]){5}[0-9a-f]{2}$/i.test(name);
    }
    readonly property var sortedDevices: {
        const rank = device => device.connected ? 0 : device.paired ? 1 : unnamed(device) ? 3 : 2;
        return Services.bluetoothDevices.slice().sort((a, b) => rank(a) - rank(b) || (a.name || "").localeCompare(b.name || ""));
    }
    readonly property int hiddenDevices: sortedDevices.filter(device => !device.paired && !device.connected && unnamed(device)).length
    readonly property var shownDevices: showAllDevices ? sortedDevices : sortedDevices.filter(device => device.paired || device.connected || !unnamed(device))
    readonly property var pairedDevices: sortedDevices.filter(device => device.paired)
    readonly property var nearbyDevices: shownDevices.filter(device => !device.paired)
    readonly property var autoConnectList: ShellState.setting("bluetoothAutoConnect", [])
    property var pairing: null
    // The Wi-Fi network waiting for a confirmation to be forgotten.
    property string forgetPath: ""
    // The device whose options are open, and the connects and disconnects the shell has under way.
    property string expandedDevice: ""
    property var bluetoothWork: ({})
    function setWork(path, kind) {
        const next = Object.assign({}, bluetoothWork);
        if (kind)
            next[path] = kind;
        else
            delete next[path];
        bluetoothWork = next;
    }
    // Tapping a device: connect or disconnect it through the helper (so auto-connect knows), or pair a new one.
    function bluetoothActivate(device) {
        const path = device.dbusPath;
        if (bluetoothWork[path] || !Services.bluetoothEnabled)
            return;
        if (!device.paired) {
            Services.bluetoothScan(false);
            perform("bluetooth.pair", {path: path}, () => {});
            return;
        }
        const kind = device.connected ? "disconnect" : "connect";
        setWork(path, kind);
        error = "";
        Backend.request("bluetooth." + kind, {path: path}, (r, e) => {
            root.setWork(path, "");
            if (e && e.code !== "cancelled")
                root.error = e.message;
        }, {owner: root});
    }
    function toggleAutoConnect(device) {
        const address = String(device.address).toUpperCase();
        const list = autoConnectList.slice();
        const at = list.indexOf(address);
        if (at >= 0)
            list.splice(at, 1);
        else
            list.push(address);
        ShellState.setSetting("bluetoothAutoConnect", list);
    }
    // Mixer: the app stream played alone, and the mute states it covered, to give back when solo ends.
    property var soloTarget: null
    property var soloSaved: ({})
    function toggleSolo(node) {
        const target = soloTarget;
        restoreSolo();
        if (target === node || !node)
            return;
        const saved = {};
        for (const stream of Services.audioStreams) {
            if (!stream.audio)
                continue;
            saved[stream.id] = stream.audio.muted;
            stream.audio.muted = stream !== node;
        }
        soloSaved = saved;
        soloTarget = node;
    }
    function restoreSolo() {
        if (!soloTarget)
            return;
        for (const stream of Services.audioStreams)
            if (stream.audio && soloSaved[stream.id] !== undefined)
                stream.audio.muted = soloSaved[stream.id];
        soloTarget = null;
        soloSaved = {};
    }
    // Pan of a stereo node from its two channel volumes: -1 (left) … 1 (right). Mono nodes stay centred.
    function balance(node) {
        const levels = node && node.audio ? node.audio.volumes || [] : [];
        if (levels.length !== 2)
            return 0;
        const loudest = Math.max(levels[0], levels[1]);
        return loudest > 0 ? (levels[1] - levels[0]) / loudest : 0;
    }
    // A panned node's level is its louder channel; moving the fader keeps the pan.
    function level(node) {
        if (!node || !node.audio)
            return 0;
        const levels = node.audio.volumes || [];
        return Math.abs(balance(node)) > 0.01 ? Math.max(levels[0], levels[1]) : node.audio.volume;
    }
    function setPanned(node, value, pan) {
        node.audio.volumes = [value * Math.min(1, 1 - pan), value * Math.min(1, 1 + pan)];
    }
    function setLevel(node, value, setter) {
        const pan = balance(node);
        if (Math.abs(pan) > 0.01 && node && node.audio)
            setPanned(node, Math.max(0, Math.min(node === Services.output && ShellState.setting("amplification", false) ? 1.5 : 1, value)), pan);
        else
            setter(value);
    }
    function setBalance(node, pan) {
        if (!node || !node.audio || (node.audio.volumes || []).length !== 2)
            return;
        setPanned(node, level(node), Math.abs(pan) < 0.05 ? 0 : Math.max(-1, Math.min(1, pan)));
    }
    // The power row: Restart asks for a second press; a session action closes the panel first.
    property bool restartArmed: false
    property bool leaving: false
    function endSession(action) {
        if (leaving)
            return;
        leaving = true;
        ShellState.close();
        ShellState.sessionAction(action);
    }
    property real pageProgress: 1
    NumberAnimation {
        id: pageEntrance
        target: root
        property: "pageProgress"
        from: 0
        to: 1
        duration: Theme.enter
        easing.type: Easing.OutCubic
    }
    function perform(method, params, callback) {
        const generation = ++requestGeneration;
        const page = ShellState.detail;
        pendingMethod = method;
        error = "";
        Backend.request(method, params, (r, e) => {
            if (generation !== root.requestGeneration || page !== ShellState.detail)
                return;
            pendingMethod = "";
            if (e) {
                if (method !== "power.profiles")
                    error = method === "wifi.list" ? "Wi-Fi service unavailable" : e.message;
            }
            else if (callback)
                callback(r);
        }, {owner: root});
    }
    function connectSelected() {
        if (busy || !selectedNetwork)
            return;
        const network = selectedNetwork;
        const secret = passwordDraft;
        passwordDraft = "";
        perform("wifi.connect", {
            path: network.path,
            password: secret
        }, () => {
            selectedNetwork = null;
            refresh();
        });
    }
    function cancelPassword() {
        passwordDraft = "";
        passwordVisible = false;
        selectedNetwork = null;
        if (busy && pendingMethod === "wifi.connect")
            perform("wifi.disconnect", {}, () => refresh());
    }
    // `manual`: the header's refresh button, which may also ask GitHub again (opening the Update page doesn't).
    function refresh(manual) {
        if (busy)
            return;
        if (ShellState.detail === "wifi") {
            perform("wifi.list", {}, r => {
                // Rows are rebuilt only when something changed, so hover and focus survive the refresh.
                if (JSON.stringify(r) !== JSON.stringify(ShellState.wifi))
                    ShellState.wifi = r;
            });
            ShellState.refreshVpn();
        }
        if (ShellState.detail === "power")
            perform("power.profiles", {}, r => ShellState.profiles = r);
        if (ShellState.detail === "update")
            Updates.refresh(manual === true);
    }
    Component.onCompleted: {
        refresh();
        ShellState.run("display.lid.get", {}, r => ShellState.lidAwake = r.enabled);
        ShellState.run("display.grayscale.get", {}, r => ShellState.grayscale = r.enabled);
        if (ShellState.detail !== "wifi")
            ShellState.refreshWifi();
        ShellState.run("brightness.get", {}, r => ShellState.brightness = r.available ? r.value : -1);
    }
    Component.onDestruction: {
        restoreSolo();
        requestGeneration++;
        Services.bluetoothScan(false);
        Backend.request("bluetooth.reply", {
            accept: false
        });
    }
    Connections {
        target: ShellState
        function onDetailChanged() {
            pageEntrance.restart();
            root.requestGeneration++;
            root.pendingMethod = "";
            root.error = "";
            root.selectedNetwork = null;
            root.forgetPath = "";
            root.dnsPath = "";
            root.expandedDevice = "";
            root.passwordDraft = "";
            root.passwordVisible = false;
            root.showAllDevices = false;
            root.restartArmed = false;
            root.deviceChooser = "";
            root.restoreSolo();
            scanWait.stop();
            if (root.pairing && ShellState.detail !== "bluetooth") {
                Backend.request("bluetooth.reply", { accept: false });
                root.pairing = null;
                bluetoothView.clearPin();
            }
            root.refresh();
            if (ShellState.detail !== "bluetooth")
                Services.bluetoothScan(false);
        }
    }
    Connections {
        target: Backend
        function onReadyChanged() {
            if (Backend.ready) root.refresh();
        }
        function onEventReceived(name, data) {
            if (name === "bluetooth.prompt") {
                if (ShellState.detail === "bluetooth")
                    root.pairing = data;
                else
                    Backend.request("bluetooth.reply", { accept: false });
            }
        }
    }
    Timer {
        interval: 5000
        running: ShellState.detail === "wifi" && !root.busy && !root.selectedNetwork && !root.dnsPath
        repeat: true
        onTriggered: root.refresh()
    }
    // Sink names read as their kind of device: HDMI and DisplayPort, headphones, otherwise speakers.
    function outputGlyph(name) {
        return /hdmi|displayport/i.test(name) ? "hdmi" : /head(phone|set)|earbud|earphone|airpods|buds/i.test(name) ? "headphones" : "speaker";
    }
    function outputName(node) {
        const name = node.description || node.nickname || node.name || "";
        return name.replace(/\s+(analog|digital) (stereo|surround|mono).*$/i, "").replace(/^built-in audio$/i, "Speakers") || name;
    }
    function streamName(node) {
        return node.properties && node.properties["application.name"] || node.description || node.name;
    }
    // Wi-Fi strength as lit arcs: 1 (the dot only) to 4.
    function signalBars(signal) {
        return signal >= 67 ? 4 : signal >= 45 ? 3 : signal >= 25 ? 2 : 1;
    }
    // The whole output's loudness from the shared cava levels while the mixer shows (0 … 1). Apps have no level of
    // their own, so their meters show the output level scaled by their volume; the microphone has none.
    C.Spectrum {
        id: outputLevel
        visible: false
        bars: 1
        active: ShellState.detail === "audio" && Services.audioAvailable && ShellState.setting("visualizer", true) && !Theme.reduced && !Theme.lowPower
        readonly property real level: Services.muted ? 0 : Math.min(1, (outputLevel.levels[0] || 0) / 1000)
    }

    // One output device: icon, name, and the live bars when it is the one playing.
    component OutputKey: C.Button {
        id: outputKey
        required property var modelData
        readonly property string name: root.outputName(modelData)
        selected: modelData === Services.output
        implicitHeight: 36
        leftPadding: 10
        rightPadding: 10
        cornerRadius: Theme.radiusCard
        hint: modelData.description || name
        foreground: selected ? Theme.text : Theme.textSecondary
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Accessible.name: name
        Accessible.role: Accessible.RadioButton
        Accessible.checkable: true
        Accessible.checked: selected
        onClicked: Services.setOutput(modelData)
        background: Rectangle {
            radius: outputKey.cornerRadius
            color: outputKey.selected ? Theme.accentSoft : outputKey.hovered || outputKey.down || outputKey.visualFocus ? Theme.mix(Theme.well, Theme.text, 0.05) : Theme.well
            border.width: 1
            border.color: outputKey.selected ? Theme.accentLine : "transparent"
            Behavior on color {
                ColorAnimation {
                    duration: Theme.fast
                }
            }
        }
        contentItem: RowLayout {
            spacing: Theme.gapS
            C.Icon {
                name: root.outputGlyph(outputKey.modelData.description || outputKey.name)
                size: 17
                color: outputKey.foreground
            }
            C.Label {
                text: outputKey.name
                color: outputKey.foreground
                font.pixelSize: 13
                font.weight: Font.DemiBold
                Layout.fillWidth: true
                Layout.minimumWidth: 0
            }
            ControlLevelBars {
                visible: outputKey.selected
                live: NowPlaying.playing && !Services.muted
            }
        }
    }
    // An app's level on the main page: name, a slim track, the value.
    component AppLevel: RowLayout {
        id: appLevel
        required property var modelData
        Layout.fillWidth: true
        Layout.preferredHeight: 26
        spacing: 10
        C.Label {
            text: root.streamName(appLevel.modelData)
            color: Theme.textSecondary
            font.pixelSize: 13
            Layout.preferredWidth: 74
        }
        Slider {
            id: appSlider
            Layout.fillWidth: true
            implicitHeight: 26
            padding: 0
            from: 0
            to: 1
            stepSize: 0.01
            value: root.level(appLevel.modelData)
            wheelEnabled: true
            enabled: !!appLevel.modelData.audio
            Accessible.name: root.streamName(appLevel.modelData) + " volume"
            onMoved: root.setLevel(appLevel.modelData, value, v => Services.setStreamVolume(appLevel.modelData, v))
            background: Rectangle {
                y: (appSlider.height - height) / 2
                width: appSlider.width
                height: 4
                radius: 2
                color: Theme.key
                Rectangle {
                    width: appSlider.visualPosition * parent.width
                    height: parent.height
                    radius: 2
                    color: Theme.textDim
                }
            }
            handle: Rectangle {
                x: appSlider.visualPosition * (appSlider.availableWidth - width)
                y: (appSlider.height - height) / 2
                width: appSlider.pressed ? 14 : 12
                height: width
                radius: width / 2
                color: Theme.textSecondary
                C.FocusRing {
                    visible: appSlider.visualFocus
                    inset: 4
                }
            }
        }
        C.Label {
            text: appLevel.modelData.audio && appLevel.modelData.audio.muted ? "Off" : String(Math.round(appSlider.value * 100))
            color: Theme.textDim
            font.family: Theme.mono
            font.pixelSize: 12
            font.features: {"tnum": 1}
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: 34
        }
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 10
        C.Label {
            id: errorLabel
            visible: root.error !== ""
            text: root.error
            color: Theme.dangerText
            font.pixelSize: Theme.small
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        ScrollView {
            id: controlScroll
            ScrollBar.vertical: C.ScrollBar {
                parent: controlScroll
                x: controlScroll.width - width
                y: controlScroll.topPadding
                height: controlScroll.availableHeight
            }
            opacity: root.pageProgress
            transform: Translate {
                x: Theme.reduced ? 0 : (1 - root.pageProgress) * 6
            }
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            Layout.preferredHeight: 0
            contentWidth: availableWidth
            clip: true
            ColumnLayout {
                id: controlContent
                width: controlScroll.availableWidth
                spacing: Theme.gapS
                C.FocusScroller {
                    flickable: controlScroll.contentItem
                    content: controlContent
                    Layout.preferredHeight: 0
                    Layout.preferredWidth: 0
                }
                ColumnLayout {
                    visible: ShellState.detail === ""
                    Layout.fillWidth: true
                    spacing: Theme.gapS
                    // A newer Shale, or what the last update brought: the page behind the arrow lists the changes.
                    C.ListRow {
                        visible: Updates.available || !!Updates.recent
                        Layout.fillWidth: true
                        text: Updates.available ? "Update available" : "Updated to " + Updates.installed
                        subtitle: Updates.available ? Updates.installed + " → " + Updates.latest + " · " + Updates.changes(Updates.count) : "See what changed"
                        glyph: "update"
                        positive: true
                        checkmark: false
                        hint: "What changed"
                        onClicked: ShellState.detail = "update"
                        trailing: C.Icon { name: "chevron"; color: Theme.textDim; Layout.rightMargin: 4 }
                    }
                    // Every tile here is an on/off switch; Wi-Fi and Bluetooth open their page from the arrow.
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: Theme.gapS
                        columnSpacing: Theme.gapS
                        Repeater {
                            model: root.shownTiles
                            C.QuickTile {
                                id: quickTile
                                required property string modelData
                                required property int index
                                readonly property var info: root.tile(modelData)
                                // Opening Control, the tiles seat in their rails one after another.
                                opacity: seat.shown
                                transform: [
                                    Translate {
                                        y: quickTile.sunk
                                    },
                                    C.Cascade {
                                        id: seat
                                        panel: "control"
                                        order: quickTile.index
                                        dy: -14
                                    }
                                ]
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.preferredWidth: 1
                                Layout.preferredHeight: Math.max(60, Theme.body * 4.2)
                                text: info.text
                                glyph: info.glyph
                                selected: info.selected
                                subtitle: info.subtitle
                                hint: info.hint
                                detailHint: info.detailHint
                                enabled: info.enabled
                                Accessible.role: info.switch ? Accessible.CheckBox : Accessible.Button
                                Accessible.checkable: !!info.switch
                                Accessible.checked: !!info.switch && selected
                                onClicked: root.activateTile(modelData)
                                onDetailRequested: quickTile.info.detail === "airdrop" ? ShellState.open("airdrop") : ShellState.detail = quickTile.info.detail
                            }
                        }
                    }
                    // Volume (with its glow), microphone and brightness; each icon mutes, the arrow opens the mixer.
                    C.Card {
                        visible: root.arrangement.sections.levels
                        Layout.fillWidth: true
                        implicitHeight: levelRows.implicitHeight + 20
                        ColumnLayout {
                            id: levelRows
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            anchors.topMargin: 10
                            anchors.bottomMargin: 10
                            spacing: 6
                            C.SliderRow {
                                Layout.fillWidth: true
                                title: "Volume"
                                showTitle: false
                                glow: true
                                muteable: true
                                muted: Services.muted
                                onIconClicked: Services.toggleMute()
                                value: Services.volume
                                maximum: ShellState.setting("amplification", false) ? 1.5 : 1
                                enabled: Services.audioAvailable
                                detailHint: "Mixer"
                                onDetailRequested: ShellState.detail = "audio"
                                onMoved: value => Services.setVolume(value)
                            }
                            C.SliderRow {
                                Layout.fillWidth: true
                                visible: Services.audioAvailable && !!Services.input
                                title: "Microphone"
                                showTitle: false
                                glyph: "mic"
                                mutedGlyph: "mic-off"
                                muteable: true
                                muted: Services.micMuted
                                onIconClicked: Services.toggleMicMute()
                                value: Services.micVolume
                                onMoved: value => Services.setMicVolume(value)
                            }
                            C.SliderRow {
                                Layout.fillWidth: true
                                title: "Brightness"
                                showTitle: false
                                glyph: "sun"
                                // Desktops have no backlight; setting it needs brightnessctl.
                                visible: ShellState.brightness >= 0 && Backend.has("brightnessctl", true)
                                value: Math.max(0, ShellState.brightness)
                                onMoved: value => {
                                    ShellState.brightness = value;
                                    brightnessDebounce.restart();
                                }
                            }
                        }
                    }
                    // The real sinks; the chosen one shows live bars. Apps playing now follow it and have their own levels.
                    C.Card {
                        visible: root.arrangement.sections.levels && Services.audioAvailable && Services.audioOutputs.length > 0
                        Layout.fillWidth: true
                        implicitHeight: outputModule.implicitHeight + 20
                        ColumnLayout {
                            id: outputModule
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            anchors.topMargin: 10
                            anchors.bottomMargin: 10
                            spacing: 10
                            ControlModuleHeader {
                                title: "Output"
                                // With one device there is nothing to choose: its name sits in the note instead.
                                note: Services.audioOutputs.length === 1 ? root.outputName(Services.audioOutputs[0]) + " · playing apps follow" : "playing apps follow"
                                Layout.minimumHeight: 0
                            }
                            GridLayout {
                                visible: Services.audioOutputs.length > 1
                                Layout.fillWidth: true
                                columns: Math.max(1, Math.min(3, Services.audioOutputs.length))
                                rowSpacing: 6
                                columnSpacing: 6
                                Accessible.role: Accessible.Grouping
                                Accessible.name: "Sound output"
                                Repeater {
                                    model: Services.audioOutputs
                                    OutputKey {}
                                }
                            }
                            Repeater {
                                model: Services.audioStreams
                                AppLevel {}
                            }
                        }
                    }
                    // A focus session: popups held, a ring in the bar, then one digest of what came in.
                    C.Card {
                        visible: root.arrangement.sections.focus
                        Layout.fillWidth: true
                        implicitHeight: focusModule.implicitHeight + 20
                        // Title and state on the left, the lengths on the right, in one line.
                        RowLayout {
                            id: focusModule
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            anchors.topMargin: 10
                            anchors.bottomMargin: 10
                            spacing: Theme.gapS
                            // The name and state open the Focus page: its ring, Pause, and what came in.
                            C.Button {
                                id: focusOpen
                                flat: true
                                hint: "Focus page"
                                Accessible.name: "Focus, " + focusState.text
                                Layout.fillWidth: true
                                Layout.leftMargin: -6
                                implicitHeight: 40
                                leftPadding: 6
                                rightPadding: 6
                                onClicked: ShellState.detail = "focus"
                                contentItem: RowLayout {
                                    spacing: 6
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        C.Label {
                                            text: "Focus"
                                            font.weight: Font.DemiBold
                                            Layout.fillWidth: true
                                        }
                                        C.Label {
                                            id: focusState
                                            text: Focus.paused ? "paused · " + Focus.minutesText(Focus.remainingSeconds) + " left" : Focus.active ? Focus.minutesText(Focus.remainingSeconds) + " left · held" : "not running"
                                            color: Theme.textDim
                                            font.pixelSize: 12
                                            Layout.fillWidth: true
                                        }
                                    }
                                    C.Icon {
                                        name: "chevron"
                                        size: 14
                                        color: focusOpen.hovered || focusOpen.visualFocus ? Theme.textSecondary : Theme.textDim
                                    }
                                }
                            }
                            ControlSmallKey {
                                visible: Focus.active
                                text: "+5"
                                hint: "Five more minutes"
                                onClicked: Focus.extend(5)
                            }
                            C.Segmented {
                                fill: false
                                trackColor: Theme.well
                                segmentHeight: 32
                                model: [{key: 0, text: "Off", hint: "No focus session"}, {key: 25, text: "25", hint: "Focus for 25 minutes"},
                                        {key: 50, text: "50", hint: "Focus for 50 minutes"}, {key: 90, text: "90", hint: "Focus for 90 minutes"}]
                                current: Focus.active ? Focus.lastMinutes : 0
                                onActivated: key => key === 0 ? Focus.end(true) : Focus.start(key)
                            }
                        }
                    }
                    C.ListRow {
                        visible: root.arrangement.sections.media
                        Layout.fillWidth: true
                        text: Services.player ? (Services.player.trackTitle || "Now playing") : "Nothing playing"
                        subtitle: Services.player ? (Services.player.trackArtist || Services.player.identity) : "Player"
                        glyph: "music"
                        hint: "Player"
                        onClicked: ShellState.detail = "media"
                        trailing: C.Button {
                            implicitWidth: 36
                            implicitHeight: 36
                            glyph: Services.player && Services.player.isPlaying ? "pause" : "play"
                            hint: Services.player && Services.player.isPlaying ? "Pause" : "Play"
                            accent: true
                            enabled: !!Services.player && Services.player.canTogglePlaying
                            onClicked: Services.player.togglePlaying()
                        }
                    }
                }
                // The mixer: channel strips for the output, each app and the microphone (scrolling sideways when
                // there are many), then the equalizer.
                ControlSound {
                    id: soundView
                    control: root
                }
                // Network · Wi-Fi: the switch, the current network as an "on" card, then the others by strength.
                ControlWifi {
                    id: wifiView
                    control: root
                }
                // Network · Bluetooth: the switch and Scan, a pairing prompt, then paired devices and nearby ones.
                ControlBluetooth {
                    id: bluetoothView
                    control: root
                }
                ControlPower {
                    id: powerView
                    control: root
                }
                UpdatePage {
                    visible: ShellState.detail === "update"
                    Layout.fillWidth: true
                }
                Media {
                    visible: ShellState.detail === "media"
                    Layout.fillWidth: true
                    active: visible
                }
                FocusView {
                    id: focusView
                    visible: ShellState.detail === "focus"
                    Layout.fillWidth: true
                }
                ColumnLayout {
                    visible: ShellState.detail === "tray"
                    Layout.fillWidth: true
                    spacing: Theme.gapS
                    C.EmptyState {
                        visible: Services.trayItems.length === 0
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.gapXl
                        glyph: "grid"
                        title: "No background apps"
                        description: "App indicators appear here"
                    }
                    Repeater {
                        model: Services.trayItems
                        C.ListRow {
                            id: trayRow
                            required property var modelData
                            Layout.fillWidth: true
                            image: modelData.icon
                            text: modelData.tooltipTitle || modelData.title || modelData.id
                            hint: "Open " + text
                            onClicked: modelData.onlyMenu ? trayMenuButton.openMenu() : modelData.activate()
                            trailing: C.Button {
                                id: trayMenuButton
                                glyph: "more"
                                flat: true
                                hint: "Menu for " + (trayRow.modelData.title || trayRow.modelData.id)
                                implicitWidth: 32
                                implicitHeight: 32
                                selected: trayMenu.shown && trayMenu.item === trayRow.modelData
                                function openMenu() {
                                    trayMenu.toggle(trayRow.modelData, trayMenuButton.QsWindow.window, trayMenuButton);
                                }
                                onClicked: openMenu()
                            }
                        }
                    }
                }
                Item {
                    Layout.preferredHeight: 4
                }
            }
        }
        // The power row, in the order Settings → Control center gives its buttons: Capture, Lock, and the session
        // keys (Sleep, Restart, which asks for a second press, and Hold to power off, which takes the rest of the
        // row). Settings sits in the header.
        RowLayout {
            id: actionFooter
            visible: ShellState.detail === ""
            Layout.fillWidth: true
            spacing: Theme.gapS
            Repeater {
                model: root.arrangement.footer.filter(item => item.shown).reduce((keys, item) => keys.concat(({
                        capture: ["capture"],
                        lock: ["lock"],
                        session: ["sleep", "restart", "poweroff"]
                    })[item.id] || []), [])
                Loader {
                    required property string modelData
                    Layout.fillWidth: modelData === "poweroff"
                    Layout.minimumWidth: 0
                    Layout.preferredHeight: 44
                    sourceComponent: ({
                            capture: captureKey,
                            lock: lockKey,
                            sleep: sleepKey,
                            restart: restartKey,
                            poweroff: powerOffKey
                        })[modelData]
                }
            }
        }
    }
    Component {
        id: captureKey
        ControlPowerKey {
            glyph: "camera"
            hint: "Capture"
            implicitWidth: 44
            onClicked: ShellState.open("capture")
        }
    }
    Component {
        id: lockKey
        ControlPowerKey {
            glyph: "lock"
            hint: "Lock"
            implicitWidth: 44
            enabled: !root.leaving
            onClicked: ShellState.action("lock")
        }
    }
    Component {
        id: sleepKey
        ControlPowerKey {
            glyph: "moon"
            hint: "Sleep · locks first"
            implicitWidth: 44
            enabled: !root.leaving
            onClicked: ShellState.action("suspend")
        }
    }
    Component {
        id: restartKey
        // Armed, it spells out the question until the second press or the timeout.
        ControlPowerKey {
            text: root.restartArmed ? "Restart?" : ""
            glyph: "refresh"
            implicitWidth: root.restartArmed ? implicitContentWidth + leftPadding + rightPadding : 44
            hint: root.restartArmed ? "Press again to restart" : "Restart"
            selected: root.restartArmed
            enabled: !root.leaving
            onClicked: {
                if (root.restartArmed) {
                    root.endSession("reboot");
                } else {
                    root.restartArmed = true;
                    restartDisarm.restart();
                }
            }
        }
    }
    Component {
        id: powerOffKey
        C.HoldButton {
            id: powerOff
            text: "Hold to power off"
            destructive: true
            implicitHeight: 44
            implicitWidth: holdRow.implicitWidth + leftPadding + rightPadding
            leftPadding: 12
            rightPadding: 12
            topPadding: 0
            bottomPadding: 0
            armed: !root.leaving && ShellState.panel === "control" && !ShellState.locked && root.Window.active
            onConfirmed: root.endSession("shutdown")
            contentItem: Item {
                implicitWidth: holdRow.implicitWidth
                implicitHeight: holdRow.implicitHeight
                Row {
                    id: holdRow
                    anchors.centerIn: parent
                    spacing: Theme.gapS
                    C.Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "power"
                        size: 17
                        color: Theme.dangerText
                    }
                    C.Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: powerOff.progress > 0 ? "Keep holding" : "Hold to power off"
                        color: Theme.dangerText
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }
    // A second press within a few seconds restarts; after that Restart asks again.
    Timer {
        id: restartDisarm
        interval: 4000
        onTriggered: root.restartArmed = false
    }
    Timer {
        id: scanWait
        interval: 1500
        onTriggered: root.refresh()
    }
    Timer {
        id: brightnessDebounce
        interval: 60
        onTriggered: ShellState.run("brightness.set", {
            value: ShellState.brightness
        }, r => ShellState.osd("Brightness", r.value, "sun"))
    }
}
