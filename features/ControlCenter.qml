import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import "../core"
import "../core/paths.js" as Paths
import "../services"
import "../components" as C

FocusScope {
    id: root
    readonly property string title: ({wifi: "Wi-Fi", bluetooth: "Bluetooth", audio: "Sound", power: "Battery & power", media: "Now playing", tray: "System tray"})[ShellState.detail] || "Control center"
    readonly property bool canGoBack: ShellState.detail !== ""
    function back() {
        ShellState.detail = "";
    }
    readonly property int panelWidth: 420
    // Fits the page, header and padding included, within a 620 px ceiling.
    readonly property int panelHeight: preferredContentHeight > 0 ? Math.max(200, Math.min(620, preferredContentHeight + 88)) : 620
    readonly property Component headerTools: ["wifi", "power"].indexOf(ShellState.detail) >= 0 ? refreshTool : null
    Component {
        id: refreshTool
        C.Button {
            glyph: "refresh"
            flat: true
            hint: "Refresh"
            implicitWidth: 32
            implicitHeight: 32
            enabled: !root.busy
            onClicked: root.refresh()
        }
    }
    readonly property int preferredContentHeight: Math.ceil(controlContent.implicitHeight + (errorLabel.visible ? errorLabel.implicitHeight + 12 : 0) + (actionFooter.visible ? actionFooter.implicitHeight + 12 : 0))
    property string error: ""
    property bool busy: false
    // Busy with something the user asked for; background list refreshes don't dim the page.
    readonly property bool acting: busy && ["wifi.list", "power.profiles"].indexOf(pendingMethod) < 0
    property string pendingMethod: ""
    property int requestGeneration: 0
    property bool alive: true
    property var selectedNetwork: null
    // Kept outside the network rows: refreshes recreate them while you type.
    property string passwordDraft: ""
    TrayMenu {
        id: trayMenu
    }
    property bool passwordVisible: false
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
    property var pairing: null
    property string forgetPath: ""
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
        busy = true;
        pendingMethod = method;
        error = "";
        Backend.request(method, params, (r, e) => {
            if (!root.alive || generation !== root.requestGeneration || page !== ShellState.detail)
                return;
            busy = false;
            pendingMethod = "";
            if (e) {
                if (method !== "power.profiles")
                    error = method === "wifi.list" ? "Wi-Fi service unavailable" : e.message;
            }
            else if (callback)
                callback(r);
        });
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
    function refresh() {
        if (busy)
            return;
        if (ShellState.detail === "wifi")
            perform("wifi.list", {}, r => ShellState.wifi = r);
        if (ShellState.detail === "power")
            perform("power.profiles", {}, r => ShellState.profiles = r);
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
        alive = false;
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
            root.busy = false;
            root.pendingMethod = "";
            root.error = "";
            root.selectedNetwork = null;
            root.forgetPath = "";
            root.passwordDraft = "";
            root.passwordVisible = false;
            root.showAllDevices = false;
            scanWait.stop();
            if (root.pairing && ShellState.detail !== "bluetooth") {
                Backend.request("bluetooth.reply", { accept: false });
                root.pairing = null;
                pin.clear();
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
        running: ShellState.detail === "wifi" && !root.busy && !root.selectedNetwork
        repeat: true
        onTriggered: root.refresh()
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.gapM
        C.Label {
            id: errorLabel
            visible: root.error !== ""
            text: root.error
            color: Theme.danger
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
                spacing: Theme.gapM
                ColumnLayout {
                    visible: ShellState.detail === ""
                    Layout.fillWidth: true
                    spacing: Theme.gapS
                    // Every tile here is an on/off switch; pages open from chevrons and the power row below.
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: Theme.gapS
                        columnSpacing: Theme.gapS
                        C.QuickTile {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.preferredHeight: Math.max(66, Theme.body * 4.6)
                            visible: ShellState.wifiAvailable
                            text: "Wi-Fi"
                            glyph: ShellState.wifi.powered ? "wifi" : "wifi-off"
                            selected: ShellState.wifi.state === "connected"
                            subtitle: {
                                const current = (ShellState.wifi.networks || []).find(n => n.connected);
                                return root.pendingMethod === "wifi.power" ? "Updating…" : current ? current.name : ShellState.wifi.powered ? "Not connected" : "Off";
                            }
                            hint: ShellState.wifi.powered ? "Turn Wi-Fi off" : "Turn Wi-Fi on"
                            detailHint: "Wi-Fi networks"
                            enabled: !root.acting
                            onClicked: root.perform("wifi.power", {
                                powered: !ShellState.wifi.powered
                            }, () => ShellState.refreshWifi())
                            onDetailRequested: ShellState.detail = "wifi"
                        }
                        C.QuickTile {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.preferredHeight: Math.max(66, Theme.body * 4.6)
                            text: "Bluetooth"
                            glyph: "bluetooth"
                            selected: Services.bluetoothEnabled
                            subtitle: {
                                const count = Services.bluetoothDevices.filter(d => d.connected).length;
                                return !Services.bluetoothAvailable ? "Unavailable" : count ? count + " connected" : Services.bluetoothEnabled ? "On" : "Off";
                            }
                            hint: Services.bluetoothEnabled ? "Turn Bluetooth off" : "Turn Bluetooth on"
                            detailHint: "Bluetooth devices"
                            enabled: Services.bluetoothAvailable
                            onClicked: Services.bluetoothPower(!Services.bluetoothEnabled)
                            onDetailRequested: ShellState.detail = "bluetooth"
                        }
                        Repeater {
                            model: [
                                {key: "dnd", text: "Do not disturb", glyph: "bell-off", on: ShellState.setting("dnd", false), subtitle: "Popups hidden", busy: false},
                                {key: "awake", text: "Stay awake", glyph: "moon", on: ShellState.presentation, subtitle: "Screen stays on", busy: false},
                                {key: "grayscale", text: "Grayscale", glyph: "palette", on: ShellState.grayscale, subtitle: "Colors off", busy: ShellState.grayscaleBusy},
                                {key: "lid", text: "Lid closed", glyph: "laptop", on: ShellState.lidAwake, subtitle: "Stays awake", busy: ShellState.lidBusy}
                            ].filter(tile => tile.key !== "lid" || Backend.capabilities.lid !== false)
                            C.QuickTile {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.preferredHeight: Math.max(58, Theme.body * 4)
                                text: modelData.text
                                glyph: modelData.glyph
                                selected: modelData.on
                                subtitle: modelData.on ? modelData.subtitle : "Off"
                                enabled: !modelData.busy
                                Accessible.role: Accessible.CheckBox
                                Accessible.checkable: true
                                Accessible.checked: selected
                                onClicked: {
                                    if (modelData.key === "dnd")
                                        ShellState.setSetting("dnd", !ShellState.setting("dnd", false));
                                    else if (modelData.key === "awake")
                                        ShellState.presentation = !ShellState.presentation;
                                    else if (modelData.key === "grayscale")
                                        ShellState.toggleGrayscale();
                                    else
                                        ShellState.toggleLidAwake();
                                }
                            }
                        }
                    }
                    // A focus session: popups held, a ring in the bar, then one digest of what came in.
                    C.ListRow {
                        Layout.fillWidth: true
                        text: "Focus"
                        glyph: "focus"
                        selected: Focus.active
                        checkmark: false
                        subtitle: Focus.active ? Focus.minutesText(Focus.remainingSeconds) + " left · Notifications held" : "Holds notifications, then sums them up"
                        hint: Focus.active ? "End focus" : "Focus for " + Focus.lastMinutes + " minutes"
                        Accessible.role: Accessible.CheckBox
                        Accessible.checkable: true
                        Accessible.checked: Focus.active
                        onClicked: Focus.active ? Focus.end(true) : Focus.start(Focus.lastMinutes)
                        trailing: [
                            C.Segmented {
                                visible: !Focus.active
                                fill: false
                                segmentHeight: 30
                                model: [{key: 25, text: "25m", hint: "Focus for 25 minutes"}, {key: 50, text: "50m", hint: "Focus for 50 minutes"}, {key: 90, text: "90m", hint: "Focus for 90 minutes"}]
                                current: Focus.lastMinutes
                                onActivated: key => Focus.start(key)
                            },
                            C.Button {
                                visible: Focus.active
                                text: "+5 min"
                                implicitHeight: 30
                                onClicked: Focus.extend(5)
                            }
                        ]
                    }
                    C.Card {
                        Layout.fillWidth: true
                        implicitHeight: levels.implicitHeight + 2 * Theme.gapM
                        ColumnLayout {
                            id: levels
                            anchors.fill: parent
                            anchors.margins: Theme.gapM
                            spacing: Theme.gapS
                            C.SliderRow {
                                Layout.fillWidth: true
                                title: "Volume"
                                muteable: true
                                muted: Services.muted
                                onIconClicked: Services.toggleMute()
                                value: Services.volume
                                maximum: ShellState.setting("amplification", false) ? 1.5 : 1
                                enabled: Services.audioAvailable
                                detailHint: "Sound settings"
                                onDetailRequested: ShellState.detail = "audio"
                                onMoved: value => Services.setVolume(value)
                            }
                            C.SliderRow {
                                Layout.fillWidth: true
                                title: "Brightness"
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
                    C.ListRow {
                        Layout.fillWidth: true
                        text: Services.player ? (Services.player.trackTitle || "Now playing") : "Nothing playing"
                        subtitle: Services.player ? (Services.player.trackArtist || Services.player.identity) : "Media"
                        glyph: "music"
                        hint: "Media"
                        onClicked: ShellState.detail = "media"
                        trailing: C.Button {
                            implicitWidth: 36
                            implicitHeight: Theme.controlHeight
                            glyph: Services.player && Services.player.isPlaying ? "pause" : "play"
                            hint: Services.player && Services.player.isPlaying ? "Pause" : "Play"
                            accent: true
                            enabled: !!Services.player && Services.player.canTogglePlaying
                            onClicked: Services.player.togglePlaying()
                        }
                    }
                    C.ListRow {
                        readonly property string mode: ({"power-saver": "Power saver", "balanced": "Balanced", "performance": "Performance"})[ShellState.profiles.active] || ""
                        Layout.fillWidth: true
                        text: Services.batteryAvailable ? "Battery & power" : "Power"
                        subtitle: [Services.batteryAvailable ? Math.round(Services.batteryPercent) + "%" + (Services.batteryCharging ? " · Charging" : "") : "", mode].filter(part => part).join(" · ") || "Power modes"
                        glyph: Services.batteryCharging ? "bolt" : Services.batteryAvailable ? "battery" : "gauge"
                        hint: "Battery and power modes"
                        onClicked: ShellState.detail = "power"
                        trailing: C.Icon { name: "chevron"; color: Theme.muted; Layout.rightMargin: 4 }
                    }
                }
                ColumnLayout {
                    visible: ShellState.detail === "audio"
                    Layout.fillWidth: true
                    spacing: Theme.gapS
                    C.StatusCard {
                        visible: !Services.audioAvailable
                        Layout.fillWidth: true
                        glyph: "volume"
                        title: "Audio unavailable"
                        subtitle: "No output device or audio service"
                    }
                    C.Card {
                        visible: Services.audioAvailable
                        Layout.fillWidth: true
                        implicitHeight: audioLevels.implicitHeight + 2 * Theme.gapM
                        ColumnLayout {
                            id: audioLevels
                            anchors.fill: parent
                            anchors.margins: Theme.gapM
                            spacing: Theme.gapS
                            C.SliderRow {
                                Layout.fillWidth: true
                                title: "Output"
                                muteable: true
                                muted: Services.muted
                                onIconClicked: Services.toggleMute()
                                value: Services.volume
                                maximum: ShellState.setting("amplification", false) ? 1.5 : 1
                                onMoved: value => Services.setVolume(value)
                            }
                            C.SliderRow {
                                Layout.fillWidth: true
                                title: "Microphone"
                                enabled: !!Services.input
                                glyph: "mic"
                                mutedGlyph: "mic"
                                muteable: true
                                muted: Services.micMuted
                                onIconClicked: Services.toggleMicMute()
                                value: Services.micVolume
                                onMoved: value => Services.setMicVolume(value)
                            }
                        }
                    }
                    C.SectionHeader {
                        visible: Services.audioAvailable
                        text: "Output device"
                        Layout.topMargin: Theme.gapXs
                    }
                    Repeater {
                        model: Services.audioAvailable ? Services.audioOutputs : []
                        C.ListRow {
                            required property var modelData
                            readonly property string name: modelData.description || modelData.name
                            Layout.fillWidth: true
                            text: name
                            glyph: /head(phone|set)|earbud|earphone|airpods|buds/i.test(name) ? "headphones" : "speaker"
                            selected: modelData === Services.output
                            onClicked: Services.setOutput(modelData)
                        }
                    }
                    C.SectionHeader {
                        visible: Services.audioAvailable
                        text: "Input device"
                        Layout.topMargin: Theme.gapXs
                    }
                    C.Label {
                        visible: Services.audioAvailable && Services.audioInputs.length === 0
                        text: "No microphone connected"
                        color: Theme.muted
                        Layout.fillWidth: true
                    }
                    Repeater {
                        model: Services.audioAvailable ? Services.audioInputs : []
                        C.ListRow {
                            required property var modelData
                            Layout.fillWidth: true
                            text: modelData.description || modelData.name
                            glyph: "mic"
                            selected: modelData === Services.input
                            onClicked: Services.setInput(modelData)
                        }
                    }
                    C.SectionHeader {
                        visible: Services.audioAvailable
                        text: "Applications"
                        Layout.topMargin: Theme.gapXs
                    }
                    C.Label {
                        visible: Services.audioAvailable && Services.audioStreams.length === 0
                        text: "No apps are playing audio"
                        color: Theme.muted
                        Layout.fillWidth: true
                    }
                    C.Card {
                        visible: Services.audioAvailable && Services.audioStreams.length > 0
                        Layout.fillWidth: true
                        implicitHeight: streamLevels.implicitHeight + 2 * Theme.gapM
                        ColumnLayout {
                            id: streamLevels
                            anchors.fill: parent
                            anchors.margins: Theme.gapM
                            spacing: Theme.gapS
                            Repeater {
                                model: Services.audioAvailable ? Services.audioStreams : []
                                C.SliderRow {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    title: modelData.properties && modelData.properties["application.name"] || modelData.description || modelData.name
                                    muteable: !!modelData.audio
                                    muted: !!modelData.audio && modelData.audio.muted
                                    onIconClicked: if (modelData.audio) modelData.audio.muted = !modelData.audio.muted
                                    value: modelData.audio ? modelData.audio.volume : 0
                                    onMoved: value => Services.setStreamVolume(modelData, value)
                                }
                            }
                        }
                    }
                }
                ColumnLayout {
                    visible: ShellState.detail === "wifi"
                    Layout.fillWidth: true
                    spacing: Theme.gapS
                    C.EmptyState {
                        visible: !ShellState.wifiAvailable
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.gapL
                        glyph: "wifi-off"
                        title: "Wi-Fi isn't managed here"
                        description: (ShellState.wifi.reason || "") + " Shale controls Wi-Fi through NetworkManager."
                    }
                    C.Toggle {
                        visible: ShellState.wifiAvailable
                        Layout.fillWidth: true
                        text: "Wi-Fi"
                        description: {
                            const network = (ShellState.wifi.networks || []).find(n => n.connected);
                            return network ? "Connected to " + network.name : ShellState.wifi.powered ? "Not connected" : "Off";
                        }
                        glyph: ShellState.wifi.powered ? "wifi" : "wifi-off"
                        positive: ShellState.wifi.state === "connected"
                        selected: ShellState.wifi.powered
                        enabled: !root.acting
                        onClicked: root.perform("wifi.power", {
                            powered: !ShellState.wifi.powered
                        }, () => root.refresh())
                    }
                    C.SectionHeader {
                        visible: ShellState.wifi.powered
                        text: "Nearby networks"
                        Layout.topMargin: Theme.gapXs
                        C.Button {
                            text: root.pendingMethod === "wifi.scan" || scanWait.running ? "Scanning…" : "Scan"
                            flat: true
                            implicitHeight: Theme.controlSmall
                            enabled: !root.acting && !scanWait.running
                            onClicked: root.perform("wifi.scan", {}, () => scanWait.restart())
                        }
                    }
                    C.EmptyState {
                        visible: ShellState.wifi.powered && !(ShellState.wifi.networks || []).length
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.gapL
                        Layout.bottomMargin: Theme.gapL
                        glyph: "wifi"
                        title: root.busy ? "Looking for networks…" : "No networks found"
                        description: root.busy ? "This may take a moment" : "No nearby networks"
                    }
                    Repeater {
                        model: ShellState.wifi.powered ? ShellState.wifi.networks || [] : []
                        C.ListRow {
                            id: networkRow
                            required property var modelData
                            readonly property bool secured: modelData.type !== "open"
                            Layout.fillWidth: true
                            text: modelData.name
                            glyph: modelData.signal >= 67 ? "wifi" : modelData.signal >= 34 ? "wifi-2" : "wifi-1"
                            subtitle: (modelData.connected ? "Connected" : modelData.saved ? "Saved" : secured ? "Secured" : "Open network") + " · " + Math.round(modelData.signal) + "% signal"
                            selected: modelData.connected
                            checkmark: false
                            enabled: !root.acting
                            onClicked: {
                                if (modelData.connected)
                                    return;
                                else if (!secured || modelData.saved)
                                    root.perform("wifi.connect", {
                                        path: modelData.path
                                    }, () => root.refresh());
                                else {
                                    root.passwordDraft = "";
                                    root.passwordVisible = false;
                                    root.selectedNetwork = modelData;
                                }
                            }
                            trailing: [
                                C.Icon {
                                    visible: networkRow.secured && !networkRow.modelData.connected && !networkRow.modelData.saved
                                    name: "lock"
                                    size: Theme.iconSmall
                                    color: Theme.muted
                                    Layout.rightMargin: 6
                                },
                                C.Button {
                                    visible: networkRow.modelData.connected
                                    text: "Disconnect"
                                    flat: true
                                    implicitHeight: 32
                                    onClicked: root.perform("wifi.disconnect", {}, () => root.refresh())
                                },
                                C.Button {
                                    glyph: "trash"
                                    flat: true
                                    hint: "Forget network"
                                    implicitWidth: 32
                                    implicitHeight: 32
                                    visible: !!networkRow.modelData.saved || networkRow.modelData.connected
                                    onClicked: root.forgetPath = networkRow.modelData.path
                                }
                            ]
                            Loader {
                                Layout.fillWidth: true
                                active: !!root.selectedNetwork && root.selectedNetwork.path === networkRow.modelData.path
                                visible: active
                                sourceComponent: passwordForm
                                onLoaded: item.focusField()
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.gapS
                                visible: root.forgetPath === networkRow.modelData.path
                                C.Label {
                                    text: "Forget saved credentials?"
                                    Layout.fillWidth: true
                                    font.pixelSize: Theme.small
                                }
                                C.Button {
                                    text: "Cancel"
                                    onClicked: root.forgetPath = ""
                                }
                                C.Button {
                                    text: "Forget"
                                    danger: true
                                    onClicked: root.perform("wifi.forget", {
                                        path: networkRow.modelData.path
                                    }, () => {
                                        root.forgetPath = "";
                                        root.refresh();
                                    })
                                }
                            }
                        }
                    }
                    C.Label {
                        visible: (ShellState.wifi.networks || []).some(network => network.type === "8021x")
                        text: "Enterprise networks use existing NetworkManager profiles. Configure new enterprise credentials externally."
                        color: Theme.disabled
                        font.pixelSize: Theme.small
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
                ColumnLayout {
                    visible: ShellState.detail === "bluetooth"
                    Layout.fillWidth: true
                    spacing: Theme.gapS
                    C.Toggle {
                        Layout.fillWidth: true
                        text: "Bluetooth"
                        description: {
                            const count = Services.bluetoothDevices.filter(d => d.connected).length;
                            return !Services.bluetoothAvailable ? "No adapter detected" : count ? count + (count === 1 ? " device connected" : " devices connected") : Services.bluetoothScanning ? "Searching nearby" : Services.bluetoothEnabled ? "On" : "Off";
                        }
                        positive: Services.bluetoothDevices.some(d => d.connected)
                        selected: Services.bluetoothEnabled
                        glyph: "bluetooth"
                        enabled: Services.bluetoothAvailable
                        onClicked: Services.bluetoothPower(!Services.bluetoothEnabled)
                    }
                    C.Card {
                        visible: !!root.pairing
                        Layout.fillWidth: true
                        implicitHeight: pairingContent.implicitHeight + 2 * Theme.gapM
                        ColumnLayout {
                            id: pairingContent
                            anchors.fill: parent
                            anchors.margins: Theme.gapM
                            spacing: Theme.gapS
                            C.Label {
                                text: root.pairing ? root.pairing.message : ""
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                            C.Field {
                                id: pin
                                Layout.fillWidth: true
                                placeholderText: "PIN or passkey"
                                visible: root.pairing && root.pairing.input
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.gapS
                                C.Button {
                                    text: "Reject"
                                    onClicked: {
                                        ShellState.run("bluetooth.reply", {
                                            accept: false
                                        });
                                        root.pairing = null;
                                    }
                                }
                                C.Button {
                                    text: "Accept"
                                    accent: true
                                    Layout.fillWidth: true
                                    enabled: !!root.pairing && (!root.pairing.input || pin.text.trim().length > 0)
                                    onClicked: {
                                        ShellState.run("bluetooth.reply", {
                                            accept: true,
                                            value: pin.text
                                        });
                                        pin.clear();
                                        root.pairing = null;
                                    }
                                }
                            }
                        }
                    }
                    C.SectionHeader {
                        visible: Services.bluetoothEnabled
                        text: Services.bluetoothScanning ? "Searching for devices…" : "Devices"
                        Layout.topMargin: Theme.gapXs
                        C.Button {
                            text: Services.bluetoothScanning ? "Stop" : "Scan"
                            flat: true
                            implicitHeight: Theme.controlSmall
                            onClicked: Services.bluetoothScan(!Services.bluetoothScanning)
                        }
                    }
                    C.EmptyState {
                        visible: Services.bluetoothEnabled && Services.bluetoothDevices.length === 0
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.gapL
                        Layout.bottomMargin: Theme.gapL
                        glyph: "bluetooth"
                        title: Services.bluetoothScanning ? "Looking for devices…" : "No devices yet"
                        description: Services.bluetoothScanning ? "Discovering nearby accessories" : "Scan to find nearby devices"
                    }
                    Repeater {
                        model: Services.bluetoothEnabled ? root.shownDevices : []
                        C.ListRow {
                            id: bluetoothDeviceRow
                            required property var modelData
                            readonly property bool pending: modelData.pairing || modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting
                            Layout.fillWidth: true
                            interactive: false
                            checkmark: false
                            selected: modelData.connected
                            positive: modelData.connected
                            glyph: /head(phone|set)|earbud|airpods|buds/i.test(modelData.name || "") ? "headphones" : "bluetooth"
                            text: root.unnamed(modelData) ? "Unnamed device" : modelData.name
                            subtitle: (pending ? "Updating…" : modelData.connected ? "Connected" : modelData.paired ? "Paired" : root.unnamed(modelData) ? modelData.address : "Available")
                                + (modelData.batteryAvailable ? " · " + Math.round(modelData.battery * 100) + "% battery" : "")
                            trailing: C.Button {
                                text: bluetoothDeviceRow.modelData.state === BluetoothDeviceState.Connecting ? "Connecting…" : bluetoothDeviceRow.modelData.state === BluetoothDeviceState.Disconnecting ? "Disconnecting…" : bluetoothDeviceRow.modelData.pairing ? "Pairing…" : bluetoothDeviceRow.modelData.connected ? "Disconnect" : bluetoothDeviceRow.modelData.paired ? "Connect" : "Pair"
                                implicitHeight: 32
                                accent: !bluetoothDeviceRow.modelData.connected && !bluetoothDeviceRow.pending && bluetoothDeviceRow.modelData.paired
                                enabled: !root.acting && !bluetoothDeviceRow.pending && Services.bluetoothEnabled
                                onClicked: {
                                    const device = bluetoothDeviceRow.modelData;
                                    if (root.acting || bluetoothDeviceRow.pending || !Services.bluetoothEnabled)
                                        return;
                                    if (device.connected)
                                        device.disconnect();
                                    else if (device.paired)
                                        device.connect();
                                    else
                                        root.perform("bluetooth.pair", {
                                            path: device.dbusPath
                                        }, () => {});
                                }
                            }
                            RowLayout {
                                visible: bluetoothDeviceRow.modelData.paired && root.forgetPath !== bluetoothDeviceRow.modelData.dbusPath
                                Layout.fillWidth: true
                                Layout.leftMargin: 44
                                spacing: Theme.gapXs
                                C.Button {
                                    text: bluetoothDeviceRow.modelData.trusted ? "Trusted" : "Trust"
                                    glyph: bluetoothDeviceRow.modelData.trusted ? "check" : ""
                                    flat: true
                                    implicitHeight: Theme.controlSmall + 2
                                    enabled: !bluetoothDeviceRow.pending
                                    selected: bluetoothDeviceRow.modelData.trusted
                                    Accessible.role: Accessible.CheckBox
                                    Accessible.checkable: true
                                    Accessible.checked: bluetoothDeviceRow.modelData.trusted
                                    onClicked: bluetoothDeviceRow.modelData.trusted = !bluetoothDeviceRow.modelData.trusted
                                }
                                Item { Layout.fillWidth: true }
                                C.Button {
                                    text: "Forget"
                                    glyph: "trash"
                                    flat: true
                                    implicitHeight: Theme.controlSmall + 2
                                    enabled: !root.acting && !bluetoothDeviceRow.pending
                                    onClicked: root.forgetPath = bluetoothDeviceRow.modelData.dbusPath
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.gapS
                                visible: root.forgetPath === bluetoothDeviceRow.modelData.dbusPath
                                C.Label {
                                    text: "Forget this device?"
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }
                                C.Button {
                                    text: "Cancel"
                                    onClicked: root.forgetPath = ""
                                }
                                C.Button {
                                    text: "Forget"
                                    enabled: !root.acting && !bluetoothDeviceRow.pending
                                    danger: true
                                    onClicked: {
                                        bluetoothDeviceRow.modelData.forget();
                                        root.forgetPath = "";
                                    }
                                }
                            }
                        }
                    }
                    C.Button {
                        visible: Services.bluetoothEnabled && root.hiddenDevices > 0 && !root.showAllDevices
                        text: "Show " + root.hiddenDevices + (root.hiddenDevices === 1 ? " unnamed device" : " unnamed devices")
                        flat: true
                        Layout.fillWidth: true
                        onClicked: root.showAllDevices = true
                    }
                }
                ColumnLayout {
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
                            return state + (seconds > 0 ? " · " + (seconds >= 3600 ? Math.floor(seconds / 3600) + "h " : "") + Math.floor(seconds % 3600 / 60) + "m " + (Services.batteryCharging ? "until full" : "remaining") : "");
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
                        text: root.busy ? "Loading power modes…" : "Power modes are unavailable on this device."
                        color: Theme.muted
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
                            selected: ShellState.profiles.active === modelData
                            enabled: !root.acting
                            Accessible.role: Accessible.RadioButton
                            Accessible.checkable: true
                            Accessible.checked: selected
                            onClicked: root.perform("power.set", {
                                profile: modelData
                            }, r => ShellState.profiles = r)
                        }
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
                        color: Theme.muted
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
                Media {
                    visible: ShellState.detail === "media"
                    Layout.fillWidth: true
                    active: visible
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
        ColumnLayout {
            id: actionFooter
            visible: ShellState.detail === ""
            Layout.fillWidth: true
            spacing: Theme.gapXs
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.surface
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapS
                Repeater {
                    model: [
                        { title: "Capture", glyph: "camera", action: "capture" },
                        { title: "Settings", glyph: "settings", action: "settings" },
                        { title: "Lock", glyph: "lock", action: "lock" },
                        { title: "Session", glyph: "power", action: "power" }
                    ]
                    C.Button {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: Math.max(58, Theme.body * 3.8)
                        flat: true
                        hint: modelData.title
                        padding: 3
                        contentItem: Item {
                            implicitWidth: 72
                            implicitHeight: Math.max(46, Theme.body * 3)
                            C.Icon {
                                name: modelData.glyph
                                size: 17
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.topMargin: 3
                            }
                            C.Label {
                                text: modelData.title
                                font.pixelSize: Theme.caption
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                        }
                        onClicked: modelData.action === "lock" ? ShellState.action("lock") : ShellState.open(modelData.action)
                    }
                }
            }
        }
    }
    Component {
        id: passwordForm
        ColumnLayout {
            spacing: Theme.gapS
            function focusField() {
                passwordField.forceActiveFocus();
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapS
                C.Field {
                    id: passwordField
                    Layout.fillWidth: true
                    placeholderText: "Password"
                    Accessible.name: "Password for " + (root.selectedNetwork ? root.selectedNetwork.name : "Wi-Fi")
                    echoMode: root.passwordVisible ? TextInput.Normal : TextInput.Password
                    text: root.passwordDraft
                    onTextChanged: root.passwordDraft = text
                    onAccepted: root.connectSelected()
                    Keys.onEscapePressed: event => {
                        if (root.busy) {
                            event.accepted = false;
                            return;
                        }
                        root.cancelPassword();
                        event.accepted = true;
                    }
                }
                C.Button {
                    glyph: root.passwordVisible ? "eye-off" : "eye"
                    flat: true
                    hint: root.passwordVisible ? "Hide password" : "Show password"
                    implicitWidth: 44
                    implicitHeight: Theme.controlLarge
                    onClicked: root.passwordVisible = !root.passwordVisible
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapS
                C.Button {
                    text: "Cancel"
                    onClicked: root.cancelPassword()
                }
                C.Button {
                    accent: true
                    Layout.fillWidth: true
                    text: root.busy ? "Connecting…" : "Connect"
                    enabled: !root.busy && !!root.selectedNetwork
                    onClicked: root.connectSelected()
                }
            }
        }
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
