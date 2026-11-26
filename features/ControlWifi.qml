import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

// Control → Wi-Fi: the switch and Scan, the network in use, the others by strength with their password form, a hidden
// network, and the VPN profiles. The state and requests stay on the Control page (`control`), which keeps them while
// its pages change.
ColumnLayout {
    // The Control page this view belongs to: its state, requests and helpers.
    required property var control
    visible: ShellState.detail === "wifi"
    Layout.fillWidth: true
    spacing: 0
    // Network · Wi-Fi: the switch, the current network as an "on" card, then the others by strength.
    C.EmptyState {
        visible: ShellState.detail === "wifi" && !ShellState.wifiAvailable
        Layout.fillWidth: true
        Layout.topMargin: Theme.gapL
        glyph: "wifi-off"
        title: "Wi-Fi isn't managed here"
        description: (ShellState.wifi.reason || "") + " Shale controls Wi-Fi through NetworkManager."
    }
    C.Card {
        id: wifiModule
        readonly property var networks: ShellState.wifi.powered ? ShellState.wifi.networks || [] : []
        readonly property var current: networks.find(n => n.connected) || null
        // Where the network in use gets its DNS: "" when its profile couldn't be read.
        readonly property string dnsText: {
            const dns = current ? current.dns : null;
            if (!dns)
                return "";
            return ({auto: "Automatic", cloudflare: "Cloudflare", google: "Google"})[dns.mode] || dns.servers.join(", ");
        }
        visible: ShellState.detail === "wifi" && ShellState.wifiAvailable
        Layout.fillWidth: true
        implicitHeight: wifiColumn.implicitHeight + 24
        ColumnLayout {
            id: wifiColumn
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6
            ControlModuleHeader {
                title: "Wi-Fi"
                large: true
                note: !ShellState.wifi.powered ? "off" : control.pendingMethod === "wifi.power" ? "updating…"
                      : wifiModule.networks.length ? wifiModule.networks.length + (wifiModule.networks.length === 1 ? " network nearby" : " networks nearby")
                      : control.busy ? "looking for networks…" : "no networks found"
                Layout.leftMargin: 2
                Layout.bottomMargin: 4
                ControlSmallKey {
                    visible: ShellState.wifi.powered
                    text: control.pendingMethod === "wifi.scan" || control.scanTimer.running ? "Scanning…" : "Scan"
                    hint: "Look for networks again"
                    enabled: !control.acting && !control.scanTimer.running
                    onClicked: control.perform("wifi.scan", {}, () => control.scanTimer.restart())
                }
                C.Switch {
                    hint: ShellState.wifi.powered ? "Turn Wi-Fi off" : "Turn Wi-Fi on"
                    selected: ShellState.wifi.powered
                    enabled: !control.acting
                    onClicked: control.perform("wifi.power", {powered: !ShellState.wifi.powered}, () => control.refresh())
                }
            }
            // The network in use: a filled accent tile, its signal, Disconnect and Forget.
            Rectangle {
                visible: !!wifiModule.current
                Layout.fillWidth: true
                implicitHeight: currentColumn.implicitHeight + 24
                radius: Theme.radiusCard
                color: Theme.accentSoft
                border.width: 1
                border.color: Theme.accentLine
                ColumnLayout {
                    id: currentColumn
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.gapM
                        C.GlyphTile {
                            size: 36
                            glyph: "wifi"
                            selected: true
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            C.Label {
                                text: wifiModule.current ? wifiModule.current.name : ""
                                font.weight: Font.DemiBold
                                Layout.fillWidth: true
                            }
                            C.Label {
                                text: wifiModule.current ? [Math.round(wifiModule.current.signal) + "%", wifiModule.current.band, wifiModule.current.speed ? (wifiModule.current.speed >= 1000 ? (wifiModule.current.speed / 1000).toFixed(1) + " Gb/s" : wifiModule.current.speed + " Mb/s") : ""].filter(part => !!part).join(" · ") : ""
                                color: Theme.mix(Theme.textSecondary, Theme.text, 0.4)
                                font.pixelSize: 12
                                Layout.fillWidth: true
                            }
                        }
                        ControlSmallKey {
                            text: "Disconnect"
                            rest: Qt.rgba(0, 0, 0, 0.25)
                            enabled: !control.acting
                            onClicked: control.perform("wifi.disconnect", {}, () => control.refresh())
                        }
                        ControlSmallKey {
                            text: "Forget"
                            hint: "Forget this network"
                            rest: Qt.rgba(0, 0, 0, 0.25)
                            enabled: !control.acting
                            onClicked: {
                                control.dnsPath = "";
                                control.forgetPath = wifiModule.current.path;
                            }
                        }
                    }
                    RowLayout {
                        visible: !!wifiModule.current && control.forgetPath === wifiModule.current.path
                        Layout.fillWidth: true
                        spacing: Theme.gapS
                        C.Label {
                            text: "Forget saved credentials?"
                            font.pixelSize: Theme.small
                            Layout.fillWidth: true
                        }
                        ControlSmallKey {
                            text: "Cancel"
                            rest: Qt.rgba(0, 0, 0, 0.25)
                            onClicked: control.forgetPath = ""
                        }
                        C.Button {
                            text: "Forget"
                            danger: true
                            implicitHeight: 28
                            onClicked: control.perform("wifi.forget", {path: wifiModule.current.path}, () => {
                                control.forgetPath = "";
                                control.refresh();
                            })
                        }
                    }
                    // Its DNS, kept with this network only: other networks, and the sign-in pages of café and
                    // campus networks, keep the DNS they give out.
                    RowLayout {
                        visible: wifiModule.dnsText !== "" && control.forgetPath !== wifiModule.current.path && control.dnsPath !== wifiModule.current.path
                        Layout.fillWidth: true
                        spacing: Theme.gapS
                        C.Label {
                            text: "DNS"
                            color: Theme.mix(Theme.textSecondary, Theme.text, 0.4)
                            font.pixelSize: 12
                        }
                        C.Label {
                            text: wifiModule.dnsText
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        ControlSmallKey {
                            text: "Change"
                            hint: "Choose this network's DNS servers"
                            rest: Qt.rgba(0, 0, 0, 0.25)
                            enabled: !control.acting
                            onClicked: control.openDns(wifiModule.current)
                        }
                    }
                    ColumnLayout {
                        visible: !!wifiModule.current && control.dnsPath === wifiModule.current.path
                        Layout.fillWidth: true
                        spacing: 6
                        C.Segmented {
                            Layout.fillWidth: true
                            proportional: true
                            segmentHeight: 32
                            trackColor: Qt.rgba(0, 0, 0, 0.25)
                            enabled: !control.busy
                            model: [{key: "auto", text: "Automatic", hint: "The DNS this network gives out"},
                                    {key: "cloudflare", text: "Cloudflare", hint: "1.1.1.1 and 1.0.0.1"},
                                    {key: "google", text: "Google", hint: "8.8.8.8 and 8.8.4.4"},
                                    {key: "custom", text: "Custom", hint: "Servers you type in"}]
                            current: control.dnsMode
                            onActivated: key => {
                                control.dnsMode = key;
                                if (key === "custom")
                                    Qt.callLater(() => dnsField.forceActiveFocus());
                            }
                        }
                        C.Field {
                            id: dnsField
                            visible: control.dnsMode === "custom"
                            Layout.fillWidth: true
                            implicitHeight: 34
                            font.pixelSize: 14
                            placeholderText: "Servers, like 9.9.9.9 149.112.112.112"
                            Accessible.name: "DNS servers"
                            enabled: !control.busy
                            text: control.dnsDraft
                            onTextChanged: control.dnsDraft = text
                            onAccepted: control.saveDns()
                            Keys.onEscapePressed: event => {
                                control.dnsPath = "";
                                event.accepted = true;
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            C.Caption {
                                text: control.dnsMode === "auto" ? "Keep this on networks with a sign-in page."
                                      : control.dnsMode === "custom" ? "IPv4 or IPv6, separated by spaces."
                                      : "Encrypted where the network allows it."
                                color: Theme.mix(Theme.textSecondary, Theme.text, 0.4)
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                            ControlSmallKey {
                                text: "Cancel"
                                rest: Qt.rgba(0, 0, 0, 0.25)
                                enabled: !control.busy
                                onClicked: control.dnsPath = ""
                            }
                            ControlSmallKey {
                                accent: true
                                text: control.pendingMethod === "wifi.dns" ? "Saving…" : "Save"
                                enabled: !control.busy && (control.dnsMode !== "custom" || control.dnsDraft.trim() !== "")
                                onClicked: control.saveDns()
                            }
                        }
                    }
                }
            }
            Repeater {
                model: wifiModule.networks.filter(n => !n.connected)
                Rectangle {
                    id: networkRow
                    required property var modelData
                    readonly property bool secured: modelData.type !== "open"
                    readonly property bool asking: !!control.selectedNetwork && control.selectedNetwork.path === modelData.path
                    Layout.fillWidth: true
                    implicitHeight: networkColumn.implicitHeight
                    radius: Theme.radiusKey
                    color: asking ? Theme.mix(Theme.module, Theme.text, 0.04) : "transparent"
                    ColumnLayout {
                        id: networkColumn
                        width: parent.width
                        spacing: 0
                        C.Button {
                            id: networkKey
                            Layout.fillWidth: true
                            implicitHeight: 42
                            leftPadding: 10
                            rightPadding: 6
                            cornerRadius: Theme.radiusKey
                            hint: networkRow.modelData.name
                            enabled: !control.acting
                            Accessible.name: networkRow.modelData.name + (networkRow.secured ? ", secured" : ", open") + ", " + Math.round(networkRow.modelData.signal) + "% signal"
                            onClicked: {
                                const network = networkRow.modelData;
                                if (networkRow.asking)
                                    control.cancelPassword();
                                else if (!networkRow.secured || network.saved)
                                    control.perform("wifi.connect", {path: network.path}, () => control.refresh());
                                else {
                                    control.passwordDraft = "";
                                    control.passwordVisible = false;
                                    control.selectedNetwork = network;
                                }
                            }
                            background: Rectangle {
                                radius: networkKey.cornerRadius
                                color: networkKey.wash
                                opacity: networkKey.enabled && (networkKey.hovered || networkKey.down || networkKey.visualFocus) ? 1 : 0
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: Theme.fast
                                    }
                                }
                            }
                            contentItem: RowLayout {
                                spacing: Theme.gapM
                                ControlSignalIcon {
                                    bars: control.signalBars(networkRow.modelData.signal)
                                }
                                C.Label {
                                    text: networkRow.modelData.name
                                    Layout.fillWidth: true
                                }
                                C.Label {
                                    text: [networkRow.modelData.saved ? "saved" : networkRow.secured ? "" : "open", networkRow.modelData.band || ""].filter(part => !!part).join(" · ")
                                    visible: text !== ""
                                    color: Theme.textDim
                                    font.pixelSize: 12
                                }
                                C.Label {
                                    text: Math.round(networkRow.modelData.signal) + "%"
                                    color: Theme.textDim
                                    font.family: Theme.mono
                                    font.pixelSize: 11
                                    font.features: {"tnum": 1}
                                }
                                C.Icon {
                                    visible: networkRow.secured
                                    name: "lock"
                                    size: 13
                                    color: Theme.textDim
                                }
                                C.Button {
                                    visible: !!networkRow.modelData.saved
                                    glyph: "trash"
                                    flat: true
                                    hint: "Forget network"
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    onClicked: control.forgetPath = networkRow.modelData.path
                                }
                            }
                        }
                        // The password opens inline under the network.
                        Loader {
                            Layout.fillWidth: true
                            Layout.leftMargin: 40
                            Layout.rightMargin: 10
                            Layout.bottomMargin: 10
                            active: networkRow.asking
                            visible: active
                            sourceComponent: passwordForm
                            onLoaded: item.focusField()
                        }
                        RowLayout {
                            visible: control.forgetPath === networkRow.modelData.path
                            Layout.fillWidth: true
                            Layout.leftMargin: 40
                            Layout.rightMargin: 6
                            Layout.bottomMargin: 6
                            spacing: Theme.gapS
                            C.Label {
                                text: "Forget saved credentials?"
                                font.pixelSize: Theme.small
                                Layout.fillWidth: true
                            }
                            ControlSmallKey {
                                text: "Cancel"
                                onClicked: control.forgetPath = ""
                            }
                            C.Button {
                                text: "Forget"
                                danger: true
                                implicitHeight: 28
                                onClicked: control.perform("wifi.forget", {path: networkRow.modelData.path}, () => {
                                    control.forgetPath = "";
                                    control.refresh();
                                })
                            }
                        }
                    }
                }
            }
            C.Label {
                visible: wifiModule.networks.some(network => network.type === "8021x")
                text: "Enterprise networks use existing NetworkManager profiles. Configure new enterprise credentials externally."
                color: Theme.textDim
                font.pixelSize: Theme.small
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.leftMargin: 2
            }
            // A network that doesn't announce its name: typed in, with its password or none.
            ControlSmallKey {
                visible: ShellState.wifi.powered && !control.hiddenOpen
                text: "Join a hidden network"
                glyph: "plus"
                Layout.topMargin: 2
                onClicked: {
                    control.hiddenOpen = true;
                    hiddenName.forceActiveFocus();
                }
            }
            ColumnLayout {
                visible: control.hiddenOpen
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 6
                function join() {
                    if (control.busy || hiddenName.text.trim() === "")
                        return;
                    control.perform("wifi.hidden", {ssid: hiddenName.text.trim(), password: hiddenPassword.text}, () => {
                        hiddenName.text = "";
                        hiddenPassword.text = "";
                        control.hiddenOpen = false;
                        control.refresh();
                    });
                }
                C.Field {
                    id: hiddenName
                    Layout.fillWidth: true
                    implicitHeight: 34
                    font.pixelSize: 14
                    placeholderText: "Network name"
                    Accessible.name: "Hidden network name"
                    onAccepted: hiddenPassword.forceActiveFocus()
                    Keys.onEscapePressed: event => {
                        control.hiddenOpen = false;
                        event.accepted = true;
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    C.Field {
                        id: hiddenPassword
                        Layout.fillWidth: true
                        implicitHeight: 34
                        font.pixelSize: 14
                        placeholderText: "Password, or empty if open"
                        Accessible.name: "Hidden network password"
                        echoMode: TextInput.Password
                        onAccepted: parent.parent.join()
                        Keys.onEscapePressed: event => {
                            control.hiddenOpen = false;
                            event.accepted = true;
                        }
                    }
                    ControlSmallKey {
                        text: "Cancel"
                        implicitHeight: 34
                        enabled: !control.busy
                        onClicked: control.hiddenOpen = false
                    }
                    C.Button {
                        accent: true
                        text: control.busy && control.pendingMethod === "wifi.hidden" ? "Joining…" : "Join"
                        implicitHeight: 34
                        cornerRadius: 9
                        labelSize: 13
                        enabled: !control.busy && hiddenName.text.trim() !== ""
                        onClicked: parent.parent.join()
                    }
                }
            }
            // NetworkManager's VPN and WireGuard profiles; new ones are made in nm-connection-editor or nmcli.
            Flow {
                visible: (ShellState.vpn.connections || []).length > 0
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 6
                Repeater {
                    model: ShellState.vpn.connections || []
                    C.Chip {
                        required property var modelData
                        readonly property bool pending: control.busy && control.pendingVpn === modelData.path
                        readonly property string kind: modelData.kind === "wireguard" ? "WireGuard" : modelData.kind === "openvpn" ? "OpenVPN" : modelData.kind || ""
                        glyph: "shield"
                        rest: Theme.key
                        text: "VPN · " + modelData.name + (pending || modelData.state === "connecting" || modelData.state === "disconnecting" ? " · …" : "")
                        hint: (pending ? (modelData.state === "on" ? "Disconnecting…" : "Connecting… Enter any password NetworkManager asks for")
                               : ({on: "Connected", connecting: "Connecting…", disconnecting: "Disconnecting…"})[modelData.state] || "Off") + (kind ? " · " + kind : "")
                        selected: modelData.state !== "off"
                        enabled: !control.acting
                        Accessible.role: Accessible.CheckBox
                        Accessible.checkable: true
                        Accessible.checked: selected
                        onClicked: {
                            control.pendingVpn = modelData.path;
                            control.perform(modelData.state === "off" ? "vpn.connect" : "vpn.disconnect", {path: modelData.path}, () => ShellState.refreshVpn());
                        }
                    }
                }
            }
            C.Caption {
                visible: control.busy && control.pendingMethod === "vpn.connect"
                text: "Connecting… Enter any password NetworkManager asks for"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.leftMargin: 2
            }
        }
    }

    Component {
        id: passwordForm
        RowLayout {
            spacing: 6
            function focusField() {
                passwordField.forceActiveFocus();
            }
            C.Field {
                id: passwordField
                Layout.fillWidth: true
                implicitHeight: 34
                font.pixelSize: 14
                placeholderText: "Password"
                Accessible.name: "Password for " + (control.selectedNetwork ? control.selectedNetwork.name : "Wi-Fi")
                echoMode: control.passwordVisible ? TextInput.Normal : TextInput.Password
                text: control.passwordDraft
                onTextChanged: control.passwordDraft = text
                onAccepted: control.connectSelected()
                Keys.onEscapePressed: event => {
                    if (control.busy) {
                        event.accepted = false;
                        return;
                    }
                    control.cancelPassword();
                    event.accepted = true;
                }
                background: Rectangle {
                    radius: 9
                    color: Theme.well
                    border.width: 1
                    border.color: passwordField.activeFocus ? Theme.accentLine : Theme.edge
                    Behavior on border.color {
                        ColorAnimation {
                            duration: Theme.fast
                        }
                    }
                }
            }
            C.Button {
                glyph: control.passwordVisible ? "eye-off" : "eye"
                flat: true
                hint: control.passwordVisible ? "Hide password" : "Show password"
                implicitWidth: 34
                implicitHeight: 34
                onClicked: control.passwordVisible = !control.passwordVisible
            }
            C.Button {
                accent: true
                text: control.busy ? "Joining…" : "Join"
                implicitHeight: 34
                cornerRadius: 9
                labelSize: 13
                enabled: !control.busy && !!control.selectedNetwork
                onClicked: control.connectSelected()
            }
        }
    }
}
