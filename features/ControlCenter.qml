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
    readonly property int preferredContentHeight: Math.ceil(controlContent.implicitHeight + (errorLabel.visible ? errorLabel.implicitHeight + 12 : 0) + (actionFooter.visible ? actionFooter.implicitHeight + 12 : 0))
    property string error: ""
    property bool busy: false
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
        spacing: 12
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
                spacing: 12
                ColumnLayout {
                    visible: ShellState.detail === ""
                    Layout.fillWidth: true
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        C.QuickTile {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.preferredHeight: Math.max(66, Theme.body * 4.6)
                            visible: ShellState.wifiAvailable
                            text: "Wi-Fi"
                            glyph: "wifi"
                            selected: ShellState.wifi.state === "connected"
                            subtitle: {
                                const current = (ShellState.wifi.networks || []).find(n => n.connected);
                                return root.pendingMethod === "wifi.power" ? "Updating…" : current ? current.name : ShellState.wifi.powered ? "Not connected" : "Off";
                            }
                            hint: ShellState.wifi.powered ? "Turn Wi-Fi off" : "Turn Wi-Fi on"
                            detailHint: "Wi-Fi networks"
                            enabled: !root.busy
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
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: levels.implicitHeight + 22
                        radius: Theme.controlRadius
                        color: Theme.surface
                        ColumnLayout {
                            id: levels
                            anchors.fill: parent
                            anchors.margins: 11
                            spacing: 5
                            C.SliderRow {
                                Layout.fillWidth: true
                                title: "Volume"
                                muteable: true
                                muted: Services.muted
                                onIconClicked: Services.toggleMute()
                                value: Services.volume
                                maximum: ShellState.setting("amplification", false) ? 1.5 : 1
                                enabled: Services.audioAvailable
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
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        C.Button {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 36
                            glyph: Services.muted ? "mute" : "volume"
                            text: "Sound"
                            onClicked: ShellState.detail = "audio"
                        }
                        C.Button {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 36
                            glyph: "battery"
                            text: Services.batteryAvailable ? Math.round(Services.batteryPercent) + "% · " + (Services.batteryCharging ? "Charging" : "Battery") : "Power"
                            onClicked: ShellState.detail = "power"
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 56
                        radius: Theme.controlRadius
                        color: Theme.surface
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8
                            C.Button {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                flat: true
                                hint: "Media"
                                contentItem: RowLayout {
                                    spacing: 8
                                    C.Icon { name: "music"; size: 20 }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3
                                        C.Label {
                                            Layout.fillWidth: true
                                            text: Services.player ? (Services.player.trackTitle || "Now playing") : "Nothing playing"
                                            font.pixelSize: Theme.label
                                            font.weight: Font.DemiBold
                                        }
                                        C.Label {
                                            Layout.fillWidth: true
                                            text: Services.player ? (Services.player.trackArtist || Services.player.identity) : "Media"
                                            color: Theme.muted
                                            font.pixelSize: Theme.caption
                                        }
                                    }
                                }
                                onClicked: ShellState.detail = "media"
                            }
                            C.Button {
                                implicitWidth: 38
                                implicitHeight: 38
                                glyph: Services.player && Services.player.isPlaying ? "pause" : "play"
                                hint: Services.player && Services.player.isPlaying ? "Pause" : "Play"
                                accent: true
                                enabled: !!Services.player && Services.player.canTogglePlaying
                                onClicked: Services.player.togglePlaying()
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        C.Button {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 36
                            text: "Do not disturb"
                            glyph: ShellState.setting("dnd", false) ? "bell-off" : "bell"
                            selected: ShellState.setting("dnd", false)
                            onClicked: ShellState.setSetting("dnd", !ShellState.setting("dnd", false))
                        }
                        C.Button {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 36
                            text: "Stay awake"
                            glyph: "moon"
                            selected: ShellState.presentation
                            onClicked: ShellState.presentation = !ShellState.presentation
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        C.Button {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 36
                            text: "Grayscale"
                            glyph: "palette"
                            selected: ShellState.grayscale
                            enabled: !ShellState.grayscaleBusy
                            onClicked: ShellState.toggleGrayscale()
                        }
                        C.Button {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 36
                            visible: Backend.capabilities.lid !== false
                            text: "Awake with lid closed"
                            glyph: "sun"
                            selected: ShellState.lidAwake
                            enabled: !ShellState.lidBusy
                            onClicked: ShellState.toggleLidAwake()
                        }
                    }
                }
                ColumnLayout {
                    visible: ShellState.detail === "audio"
                    Layout.fillWidth: true
                    spacing: 12
                    C.StatusCard {
                        visible: !Services.audioAvailable
                        Layout.fillWidth: true
                        glyph: "volume"
                        title: "Audio unavailable"
                        subtitle: "No output device or audio service"
                    }
                    C.SliderRow {
                        visible: Services.audioAvailable
                        Layout.fillWidth: true
                        title: "Output volume"
                        muteable: true
                        muted: Services.muted
                        onIconClicked: Services.toggleMute()
                        enabled: Services.audioAvailable
                        value: Services.volume
                        maximum: ShellState.setting("amplification", false) ? 1.5 : 1
                        onMoved: value => Services.setVolume(value)
                    }
                    C.Toggle {
                        visible: Services.audioAvailable
                        Layout.fillWidth: true
                        text: "Mute output"
                        selected: Services.muted
                        enabled: Services.audioAvailable
                        onClicked: Services.toggleMute()
                    }
                    C.Label {
                        visible: Services.audioAvailable
                        text: "Output device"
                        Layout.topMargin: 8
                        color: Theme.muted
                        font.pixelSize: Theme.caption
                    }
                    Repeater {
                        model: Services.audioAvailable ? Services.audioOutputs : []
                        C.QuickTile {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 66
                            text: modelData.description || modelData.name
                            subtitle: modelData === Services.output ? "Current output" : "Available"
                            glyph: "volume"
                            selected: modelData === Services.output
                            onClicked: Services.setOutput(modelData)
                        }
                    }
                    C.SliderRow {
                        visible: Services.audioAvailable
                        Layout.fillWidth: true
                        title: "Microphone"
                        Layout.topMargin: 8
                        enabled: !!Services.input
                        glyph: "mic"
                        mutedGlyph: "mic"
                        muteable: true
                        muted: Services.micMuted
                        onIconClicked: Services.toggleMicMute()
                        value: Services.micVolume
                        onMoved: value => Services.setMicVolume(value)
                    }
                    C.Toggle {
                        visible: Services.audioAvailable
                        Layout.fillWidth: true
                        text: "Mute microphone"
                        selected: Services.micMuted
                        enabled: !!Services.input
                        onClicked: Services.toggleMicMute()
                    }
                    C.Label {
                        visible: Services.audioAvailable
                        text: "Input device"
                        Layout.topMargin: 8
                        color: Theme.muted
                        font.pixelSize: Theme.caption
                    }
                    C.Label {
                        visible: Services.audioAvailable && Services.audioInputs.length === 0
                        text: "No microphone connected"
                        color: Theme.muted
                        Layout.fillWidth: true
                    }
                    Repeater {
                        model: Services.audioAvailable ? Services.audioInputs : []
                        C.QuickTile {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 66
                            text: modelData.description || modelData.name
                            subtitle: modelData === Services.input ? "Current microphone" : "Available"
                            glyph: "mic"
                            selected: modelData === Services.input
                            onClicked: Services.setInput(modelData)
                        }
                    }
                    C.Label {
                        visible: Services.audioAvailable
                        text: "Application volume"
                        Layout.topMargin: 8
                        color: Theme.muted
                        font.pixelSize: Theme.caption
                    }
                    C.Label {
                        visible: Services.audioAvailable && Services.audioStreams.length === 0
                        text: "No apps are playing audio"
                        color: Theme.muted
                        Layout.fillWidth: true
                    }
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
                ColumnLayout {
                    visible: ShellState.detail === "wifi"
                    Layout.fillWidth: true
                    spacing: 8
                    C.EmptyState {
                        visible: !ShellState.wifiAvailable
                        Layout.fillWidth: true
                        Layout.topMargin: 16
                        glyph: "wifi"
                        title: "Wi-Fi isn't managed here"
                        description: (ShellState.wifi.reason || "") + " Shale controls Wi-Fi through NetworkManager."
                    }
                    RowLayout {
                        visible: ShellState.wifiAvailable
                        Layout.fillWidth: true
                        // One header row: switch, icon, and current status together.
                        C.Toggle {
                            Layout.fillWidth: true
                            text: "Wi-Fi"
                            description: {
                                const network = (ShellState.wifi.networks || []).find(n => n.connected);
                                return network ? "Connected to " + network.name : ShellState.wifi.powered ? "Not connected" : "Off";
                            }
                            glyph: "wifi"
                            positive: ShellState.wifi.state === "connected"
                            selected: ShellState.wifi.powered
                            enabled: !root.busy
                            onClicked: root.perform("wifi.power", {
                                powered: !ShellState.wifi.powered
                            }, () => root.refresh())
                        }
                        C.Button {
                            text: root.pendingMethod === "wifi.scan" || scanWait.running ? "Scanning…" : "Scan"
                            glyph: "refresh"
                            enabled: !root.busy && !scanWait.running && !!ShellState.wifi.powered
                            onClicked: root.perform("wifi.scan", {}, () => scanWait.restart())
                        }
                    }
                    C.Label {
                        text: "Nearby networks"
                        visible: ShellState.wifi.powered
                        font.weight: Font.DemiBold
                        Layout.topMargin: 4
                    }
                    C.EmptyState {
                        visible: ShellState.wifi.powered && !(ShellState.wifi.networks || []).length
                        Layout.fillWidth: true
                        Layout.topMargin: 16
                        Layout.bottomMargin: 16
                        glyph: "wifi"
                        title: root.busy ? "Looking for networks…" : "No networks found"
                        description: root.busy ? "This may take a moment" : "No nearby networks"
                    }
                    Repeater {
                        model: ShellState.wifi.networks || []
                        ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                C.QuickTile {
                                    Layout.fillWidth: true
                                    implicitHeight: 70
                                    text: modelData.name
                                    subtitle: (modelData.connected ? "Connected · " : modelData.type === "open" ? "Open network · " : "Secured · ") + Math.round(modelData.signal) + "% signal"
                                    glyph: "wifi"
                                    selected: modelData.connected
                                    enabled: !root.busy
                                    onClicked: {
                                        if (modelData.connected)
                                            return;
                                        else if (modelData.type === "open" || modelData.saved)
                                            root.perform("wifi.connect", {
                                                path: modelData.path
                                            }, () => root.refresh());
                                        else {
                                            root.passwordDraft = "";
                                            root.passwordVisible = false;
                                            root.selectedNetwork = modelData;
                                        }
                                    }
                                }
                                C.Button {
                                    glyph: "trash"
                                    flat: true
                                    hint: "Forget network"
                                    visible: !!modelData.saved || modelData.connected
                                    enabled: !root.busy
                                    onClicked: root.forgetPath = modelData.path
                                }
                            }
                            Loader {
                                Layout.fillWidth: true
                                active: !!root.selectedNetwork && root.selectedNetwork.path === modelData.path
                                visible: active
                                sourceComponent: passwordForm
                                onLoaded: item.focusField()
                            }
                            C.Button {
                                visible: modelData.connected
                                text: "Disconnect"
                                flat: true
                                Layout.alignment: Qt.AlignRight
                                enabled: !root.busy
                                onClicked: root.perform("wifi.disconnect", {}, () => root.refresh())
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                visible: root.forgetPath === modelData.path
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
                                    enabled: !root.busy
                                    onClicked: root.perform("wifi.forget", {
                                        path: modelData.path
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
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
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
                        C.Button {
                            glyph: "refresh"
                            text: Services.bluetoothScanning ? "Stop scan" : "Scan"
                            enabled: Services.bluetoothEnabled
                            onClicked: Services.bluetoothScan(!Services.bluetoothScanning)
                        }
                    }
                    ColumnLayout {
                        visible: !!root.pairing
                        Layout.fillWidth: true
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
                            spacing: 8
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
                    C.Label {
                        text: Services.bluetoothScanning ? "Searching for devices…" : "Your devices"
                        font.weight: Font.DemiBold
                        Layout.topMargin: 4
                        visible: Services.bluetoothEnabled
                    }
                    C.EmptyState {
                        visible: Services.bluetoothEnabled && Services.bluetoothDevices.length === 0
                        Layout.fillWidth: true
                        Layout.topMargin: 16
                        Layout.bottomMargin: 16
                        glyph: "bluetooth"
                        title: Services.bluetoothScanning ? "Looking for devices…" : "No devices yet"
                        description: Services.bluetoothScanning ? "Discovering nearby accessories" : "No nearby devices"
                    }
                    Repeater {
                        model: root.shownDevices
                        Rectangle {
                            id: bluetoothDeviceRow
                            required property var modelData
                            readonly property bool pending: modelData.pairing || modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting
                            Layout.fillWidth: true
                            implicitHeight: deviceContent.implicitHeight + 20
                            radius: Theme.controlRadius
                            color: Theme.surface
                            ColumnLayout {
                                id: deviceContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 10
                                spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                Rectangle {
                                    Layout.preferredWidth: 32
                                    Layout.preferredHeight: 32
                                    radius: 10
                                    color: modelData.connected ? Theme.selection : Theme.raised
                                    C.Icon { anchors.centerIn: parent; name: "bluetooth"; size: 16 }
                                    Rectangle {
                                        visible: modelData.connected
                                        width: 7; height: 7; radius: 3.5
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        color: Theme.success
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    C.Label {
                                        text: root.unnamed(modelData) ? "Unnamed device" : modelData.name
                                        font.weight: Font.DemiBold
                                        Layout.fillWidth: true
                                    }
                                    C.Label {
                                        text: (bluetoothDeviceRow.pending ? "Updating…" : modelData.connected ? "Connected" : modelData.paired ? "Paired" : root.unnamed(modelData) ? modelData.address : "Available")
                                            + (modelData.batteryAvailable ? " · " + Math.round(modelData.battery * 100) + "% battery" : "")
                                        color: Theme.muted
                                        font.pixelSize: Theme.small
                                        Layout.fillWidth: true
                                    }
                                }
                                C.Button {
                                    text: modelData.state === BluetoothDeviceState.Connecting ? "Connecting…" : modelData.state === BluetoothDeviceState.Disconnecting ? "Disconnecting…" : modelData.pairing ? "Pairing…" : modelData.connected ? "Disconnect" : modelData.paired ? "Connect" : "Pair"
                                    implicitHeight: 32
                                    accent: !modelData.connected && !bluetoothDeviceRow.pending && modelData.paired
                                    enabled: !root.busy && !bluetoothDeviceRow.pending && Services.bluetoothEnabled
                                    onClicked: {
                                        if (root.busy || bluetoothDeviceRow.pending || !Services.bluetoothEnabled)
                                            return;
                                        if (modelData.connected)
                                            modelData.disconnect();
                                        else if (modelData.paired)
                                            modelData.connect();
                                        else
                                            root.perform("bluetooth.pair", {
                                                path: modelData.dbusPath
                                            }, () => {});
                                    }
                                }
                            }
                            RowLayout {
                                visible: modelData.paired && root.forgetPath !== modelData.dbusPath
                                Layout.fillWidth: true
                                Layout.leftMargin: 42
                                spacing: 6
                                C.Button {
                                    text: modelData.trusted ? "Trusted" : "Trust"
                                    glyph: modelData.trusted ? "check" : ""
                                    flat: true
                                    implicitHeight: 30
                                    enabled: !bluetoothDeviceRow.pending
                                    selected: modelData.trusted
                                    Accessible.role: Accessible.CheckBox
                                    Accessible.checkable: true
                                    Accessible.checked: modelData.trusted
                                    onClicked: modelData.trusted = !modelData.trusted
                                }
                                Item { Layout.fillWidth: true }
                                C.Button {
                                    text: "Forget"
                                    glyph: "trash"
                                    flat: true
                                    implicitHeight: 30
                                    enabled: !root.busy && !bluetoothDeviceRow.pending
                                    onClicked: root.forgetPath = modelData.dbusPath
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                visible: root.forgetPath === modelData.dbusPath
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
                                    enabled: !root.busy && !bluetoothDeviceRow.pending
                                    danger: true
                                    onClicked: {
                                        modelData.forget();
                                        root.forgetPath = "";
                                    }
                                }
                            }
                            }
                        }
                    }
                    C.Button {
                        visible: root.hiddenDevices > 0 && !root.showAllDevices
                        text: "Show " + root.hiddenDevices + (root.hiddenDevices === 1 ? " unnamed device" : " unnamed devices")
                        flat: true
                        Layout.fillWidth: true
                        onClicked: root.showAllDevices = true
                    }
                }
                ColumnLayout {
                    visible: ShellState.detail === "power"
                    Layout.fillWidth: true
                    spacing: 12
                    C.StatusCard {
                        Layout.fillWidth: true
                        glyph: Services.batteryCharging ? "bolt" : "battery"
                        title: Services.batteryAvailable ? Math.round(Services.batteryPercent) + "%" : "AC power"
                        subtitle: {
                            const state = Services.batteryCharging ? "Charging" : Services.onBattery ? "On battery" : "Plugged in";
                            const seconds = Services.batterySeconds;
                            return state + (seconds > 0 ? " · " + (seconds >= 3600 ? Math.floor(seconds / 3600) + "h " : "") + Math.floor(seconds % 3600 / 60) + "m " + (Services.batteryCharging ? "until full" : "remaining") : "");
                        }
                        level: Services.batteryAvailable ? Services.batteryPercent / 100 : -1
                        positive: Services.batteryCharging
                    }
                    C.Label {
                        text: "Power mode"
                        font.weight: Font.DemiBold
                        Layout.topMargin: 6
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
                        C.QuickTile {
                            required property string modelData
                            Layout.fillWidth: true
                            implicitHeight: 76
                            text: ({"power-saver": "Power saver", "balanced": "Balanced", "performance": "Performance"})[modelData] || modelData
                            subtitle: ({"power-saver": "Longest battery life, quiet fans", "balanced": "Fast when needed, efficient at idle", "performance": "Full CPU and GPU power"})[modelData] || "System power profile"
                            glyph: modelData === "power-saver" ? "battery" : modelData === "performance" ? "bolt" : "sun"
                            selected: ShellState.profiles.active === modelData
                            enabled: !root.busy
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
                        text: "Lower refresh rate in power saver"
                        selected: ShellState.setting("saverRefresh", true)
                        onClicked: ShellState.setSetting("saverRefresh", !ShellState.setting("saverRefresh", true))
                    }
                    C.Toggle {
                        Layout.fillWidth: true
                        text: "Reduce visual effects in every mode"
                        selected: ShellState.setting("batterySaving", false)
                        onClicked: ShellState.setSetting("batterySaving", !ShellState.setting("batterySaving", false))
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
                    spacing: 8
                    C.EmptyState {
                        visible: Services.trayItems.length === 0
                        Layout.fillWidth: true
                        Layout.topMargin: 24
                        glyph: "grid"
                        title: "No background apps"
                        description: "App indicators appear here"
                    }
                    Repeater {
                        model: Services.trayItems
                        RowLayout {
                            id: trayRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8
                            C.Button {
                                Layout.fillWidth: true
                                implicitHeight: Math.max(44, Theme.body + 28)
                                hint: "Open " + (trayRow.modelData.tooltipTitle || trayRow.modelData.title || trayRow.modelData.id)
                                onClicked: trayRow.modelData.onlyMenu ? trayMenuButton.openMenu() : trayRow.modelData.activate()
                                contentItem: RowLayout {
                                    spacing: 12
                                    Image {
                                        source: trayRow.modelData.icon
                                        sourceSize.width: 20
                                        sourceSize.height: 20
                                        Layout.preferredWidth: 20
                                        Layout.preferredHeight: 20
                                        fillMode: Image.PreserveAspectFit
                                    }
                                    C.Label {
                                        text: trayRow.modelData.tooltipTitle || trayRow.modelData.title || trayRow.modelData.id
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                            C.Button {
                                id: trayMenuButton
                                glyph: "more"
                                hint: "Menu for " + (trayRow.modelData.title || trayRow.modelData.id)
                                implicitWidth: Math.max(44, Theme.body + 28)
                                implicitHeight: implicitWidth
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
            spacing: 4
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.surface
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
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
            spacing: 8
            function focusField() {
                passwordField.forceActiveFocus();
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
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
                    implicitHeight: 44
                    onClicked: root.passwordVisible = !root.passwordVisible
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
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
