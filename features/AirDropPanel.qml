pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import "../core"
import "../services"
import "../core/format.js" as Format
import "../core/airdrop.js" as Words
import "../components" as C

// AirDrop, top to bottom: how this computer receives (a strip with Off, Visible for ten minutes, Background), Send
// (a drop well until something is chosen, then the chosen things and the devices nearby to pick from), and Recent.
// Looking for devices takes the radio, so it starts only once something is chosen, or when asked; the devices part
// shows only then.
FocusScope {
    id: root
    readonly property string title: "AirDrop"
    readonly property bool showHeader: false
    readonly property int panelWidth: 600
    readonly property int panelHeight: browsing ? 640 : Math.ceil(body.implicitHeight) + Theme.casePadding * 2
    property bool browsing: false
    readonly property bool canGoBack: browsing
    function back() {
        browsing = false;
        forceActiveFocus();
    }
    readonly property bool busy: !!AirDrop.sending && (AirDrop.sending.phase === "asking" || AirDrop.sending.phase === "sending")
    readonly property string clipboard: String(Quickshell.clipboardText || "").trim()
    readonly property bool clipboardLink: /^https?:\/\/\S+$/i.test(clipboard) && clipboard !== AirDrop.stagedUrl
    function paste() {
        const lines = clipboard.split("\n").map(line => line.trim()).filter(line => line);
        if (lines.length && lines.every(line => line.startsWith("/") || line.startsWith("file://")))
            AirDrop.stage(lines);
        else if (!AirDrop.stageUrl(clipboard))
            ShellState.message("The clipboard holds no link or file to send", "error");
    }
    // Something chosen: look for devices to send it to.
    function lookIfReady() {
        if (AirDrop.available && AirDrop.hasStaged && !AirDrop.looking)
            AirDrop.search();
    }
    Connections {
        target: AirDrop
        function onHasStagedChanged() {
            root.lookIfReady();
        }
    }
    // What an earlier search left goes; something already chosen starts a new one.
    Component.onCompleted: {
        AirDrop.clearPeers();
        lookIfReady();
    }
    Component.onDestruction: AirDrop.endSearch()
    Keys.onPressed: event => {
        if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_V) {
            paste();
            event.accepted = true;
        } else if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_O) {
            browsing = true;
            event.accepted = true;
        } else if (event.key === Qt.Key_Delete && (AirDrop.staged.length || AirDrop.stagedUrl) && !busy) {
            AirDrop.unstage(AirDrop.stagedUrl ? -1 : AirDrop.staged.length - 1);
            event.accepted = true;
        }
    }
    // "just now", "5 min ago", "14:20" today, "16 Nov" before.
    function ago(time) {
        const minutes = Math.floor((Date.now() - time) / 60000);
        const when = new Date(time);
        if (when.toDateString() !== new Date().toDateString())
            return Qt.formatDate(when, "d MMM");
        return minutes < 1 ? "just now" : minutes < 60 ? minutes + " min ago" : Qt.formatTime(when, ShellState.timeFormat);
    }
    readonly property string countdown: Format.clock(AirDrop.visibleLeft)
    // The mode the strip shows: while a send holds the radio, the one that comes back after it.
    readonly property string shownMode: AirDrop.looking && AirDrop.resumeMode ? AirDrop.resumeMode : AirDrop.mode
    readonly property string modeTitle: AirDrop.recovering ? "Giving Wi-Fi back…"
        : shownMode === "visible" ? (AirDrop.receiverState === "starting" ? "Becoming visible…" : "Visible · " + countdown + " left")
        : shownMode === "background" ? (AirDrop.receiverState === "waking" ? "An iPhone opened AirDrop" : "Receiving in the background")
        : "Not receiving"
    readonly property string statusText: {
        if (AirDrop.looking && AirDrop.resumeMode && AirDrop.resumeMode !== "off")
            return "Paused while you send; it comes back after";
        if (AirDrop.mode === "visible")
            return "Devices nearby see “" + AirDrop.deviceName + "”" + (AirDrop.wifiPaused ? " · Wi-Fi paused meanwhile" : "");
        if (AirDrop.mode === "background")
            return AirDrop.receiverState === "waking" ? "Visible to it now" : "Shows up when an iPhone nearby opens AirDrop";
        return "Hidden from devices nearby";
    }
    // Words for the devices part while there is no device to show: [title, hint].
    readonly property var searchWords: {
        if (AirDrop.looking)
            return ["Looking for iPhones, iPads and Macs", "On the other device: AirDrop → Everyone for 10 Minutes, with its screen on and unlocked."];
        if (AirDrop.sendState === "ended" && AirDrop.lastFound > 0)
            return ["Stopped looking", "Nothing was picked for a minute and a half, so Wi-Fi got the radio back."];
        if (AirDrop.sendState === "ended")
            return ["No one answered", AirDrop.searchHint || "On the other device: AirDrop → Everyone for 10 Minutes, with its screen on and unlocked."];
        return ["Not looking", "Looking pauses Wi-Fi unless it is on AirDrop's channel."];
    }
    readonly property string sendStatus: {
        const s = AirDrop.sending;
        if (s && s.phase === "asking")
            return "Waiting for " + s.name + " to accept";
        if (s && s.phase === "sending")
            return [Format.bytes(s.done) + " of " + Format.bytes(s.total), s.rate > 0 ? Format.bytes(s.rate) + "/s" : "",
                    Words.left(s.done, s.total, s.rate)].filter(part => part).join(" · ");
        if (AirDrop.sendState === "starting")
            return "Starting…";
        if (AirDrop.looking)
            return AirDrop.senderWifi ? "Looking · Wi-Fi paused meanwhile" : "Looking…";
        return "";
    }
    function kindGlyph(kind) {
        return ({folder: "folder", image: "image", video: "film", audio: "music", text: "text", link: "link"})[kind] || "file";
    }
    ColumnLayout {
        id: body
        anchors.fill: parent
        spacing: 10
        // Title and close; Back while choosing files.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            spacing: 10
            C.Button {
                visible: root.browsing
                glyph: "back"
                flat: true
                hint: "Back · Escape"
                implicitWidth: 32
                implicitHeight: 32
                onClicked: root.back()
            }
            AirDropRadar {
                visible: !root.browsing
                size: 32
                rings: false
                live: AirDrop.looking || AirDrop.mode === "visible" || AirDrop.receiverState === "waking" || root.busy
            }
            C.Label {
                text: root.browsing ? "Choose files" : root.title
                font.pixelSize: 17
                font.weight: 650
                elide: Text.ElideNone
                Layout.fillWidth: true
            }
            C.Button {
                glyph: "close"
                implicitWidth: 32
                implicitHeight: 32
                flat: true
                hint: "Close · Escape"
                onClicked: ShellState.close()
            }
        }
        // Without the command there is nothing to drive: say what to install.
        C.EmptyState {
            visible: !AirDrop.available
            Layout.fillWidth: true
            Layout.topMargin: 40
            Layout.bottomMargin: 40
            glyph: "airdrop"
            title: AirDrop.command ? "This airdrop is too old for Shale" : "AirDrop needs the airdrop command"
            description: AirDrop.command ? "Shale talks to it with --json, which came later. Update it from its source folder (cargo build --release) and install it again."
                                         : "Install AirDrop for Linux (the airdrop command and its helper), then open this again. Shale finds it on your PATH or in ~/.local/bin."
        }
        AirDropBrowse {
            visible: root.browsing
            focus: root.browsing
            Layout.fillWidth: true
            Layout.fillHeight: true
            onPicked: paths => {
                AirDrop.stage(paths);
                root.back();
            }
            onCancelled: root.back()
        }
        // What went wrong, and the one thing to do about it.
        Rectangle {
            visible: AirDrop.available && !root.browsing && !!AirDrop.error
            Layout.fillWidth: true
            implicitHeight: problemRow.implicitHeight + 24
            radius: Theme.radiusCard + 2
            color: Theme.dangerWash
            border.width: 1
            border.color: Theme.dangerLine
            RowLayout {
                id: problemRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 12
                C.Icon {
                    name: "alert"
                    size: 20
                    color: Theme.dangerText
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 1
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    C.Label {
                        text: AirDrop.error ? AirDrop.error.message : ""
                        color: Theme.dangerText
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                        Layout.fillWidth: true
                    }
                    C.Label {
                        visible: text !== ""
                        text: AirDrop.error ? AirDrop.error.hint : ""
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                        Layout.fillWidth: true
                    }
                    // The one thing most likely to help first: Try again, or Wi-Fi back when that is what is wrong.
                    Flow {
                        spacing: 8
                        Layout.topMargin: 4
                        Layout.fillWidth: true
                        C.Button {
                            visible: AirDrop.canRetry
                            text: "Try again"
                            glyph: "refresh"
                            accent: true
                            implicitHeight: 28
                            onClicked: AirDrop.retry()
                        }
                        C.Button {
                            visible: !!AirDrop.error && ["link", "exit", "wifi"].indexOf(AirDrop.error.code) >= 0
                            text: AirDrop.recovering ? "Giving Wi-Fi back…" : "Give Wi-Fi back"
                            glyph: "wifi"
                            accent: !!AirDrop.error && AirDrop.error.code === "wifi"
                            enabled: !AirDrop.recovering && !AirDrop.looking
                            implicitHeight: 28
                            onClicked: AirDrop.recover()
                        }
                        C.Button {
                            visible: !!AirDrop.error && AirDrop.error.code !== "wifi"
                            text: "Check this computer"
                            flat: AirDrop.canRetry
                            implicitHeight: 28
                            onClicked: ShellState.openSettings("AirDrop")
                        }
                    }
                }
                C.Button {
                    glyph: "close"
                    flat: true
                    hint: "Dismiss"
                    implicitWidth: 28
                    implicitHeight: 28
                    Layout.alignment: Qt.AlignTop
                    onClicked: AirDrop.error = null
                }
            }
        }
        // Receiving: what it is now in words, the extra ten minutes, and the choice.
        Rectangle {
            visible: AirDrop.available && !root.browsing
            Layout.fillWidth: true
            implicitHeight: 60
            radius: Theme.radiusCard + 2
            color: root.shownMode === "off" ? Theme.moduleAlt : Theme.accentSoft
            border.width: 1
            border.color: root.shownMode === "off" ? Theme.hairline : Theme.accentLine
            Behavior on color {
                ColorAnimation {
                    duration: Theme.fast
                }
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12
                C.GlyphTile {
                    glyph: root.shownMode === "off" ? "eye-off" : "eye"
                    size: 34
                    selected: root.shownMode !== "off"
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    C.Label {
                        text: root.modeTitle
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        font.features: ({"tnum": 1})
                        color: root.shownMode === "off" ? Theme.text : Theme.accentText
                        Layout.fillWidth: true
                    }
                    C.Label {
                        text: root.statusText
                        color: Theme.textDim
                        font.pixelSize: 12
                        Layout.fillWidth: true
                    }
                }
                C.Chip {
                    visible: AirDrop.mode === "visible" && AirDrop.receiverState === "ready"
                    text: "+10 min"
                    hint: "Stay visible ten more minutes"
                    onClicked: AirDrop.extend()
                }
                C.Segmented {
                    fill: false
                    segmentHeight: 32
                    trackColor: Theme.well
                    enabled: !AirDrop.recovering
                    model: [{key: "off", text: "Off", hint: "Receive nothing"},
                            {key: "visible", text: "Visible", hint: "Visible to everyone nearby for 10 minutes"},
                            {key: "background", text: "Background", hint: "Show up when an iPhone nearby opens AirDrop"}]
                    current: root.shownMode
                    onActivated: key => AirDrop.setMode(key)
                }
            }
        }
        // Send: a drop well, or what is chosen; then the devices to send it to. Files or a link dropped anywhere here
        // are taken.
        Rectangle {
            id: send
            visible: AirDrop.available && !root.browsing
            Layout.fillWidth: true
            implicitHeight: sendColumn.implicitHeight + 28
            radius: Theme.radiusModule
            color: Theme.module
            border.width: 1
            border.color: drop.containsDrag ? Theme.accentLine : "transparent"
            Behavior on border.color {
                ColorAnimation {
                    duration: Theme.fast
                }
            }
            DropArea {
                id: drop
                anchors.fill: parent
                keys: ["text/uri-list"]
                // Files, or a link dragged from a browser.
                onDropped: event => {
                    const urls = (event.urls || []).map(url => String(url));
                    const paths = urls.filter(url => url.startsWith("file://"));
                    const links = urls.filter(url => /^https?:\/\//i.test(url));
                    if (paths.length)
                        AirDrop.stage(paths);
                    else if (!links.length || !AirDrop.stageUrl(links[0]))
                        return;
                    event.acceptProposedAction();
                }
            }
            ColumnLayout {
                id: sendColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    spacing: 8
                    C.Label {
                        text: "Send"
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    C.Label {
                        visible: AirDrop.hasStaged
                        text: AirDrop.stagedUrl ? "a link" : (AirDrop.staged.length === 1 ? "1 item" : AirDrop.staged.length + " items") + " · " + Format.bytes(AirDrop.stagedBytes)
                        color: Theme.textDim
                        font.pixelSize: 12
                        font.features: ({"tnum": 1})
                        Layout.fillWidth: true
                    }
                    Item {
                        visible: !AirDrop.hasStaged
                        Layout.fillWidth: true
                    }
                    C.Button {
                        visible: AirDrop.hasStaged && !AirDrop.stagedUrl
                        text: "Add"
                        glyph: "plus"
                        flat: true
                        hint: "Add files · Ctrl+O"
                        implicitHeight: 28
                        enabled: !root.busy
                        onClicked: root.browsing = true
                    }
                    C.Button {
                        visible: AirDrop.hasStaged
                        text: "Clear"
                        flat: true
                        implicitHeight: 28
                        enabled: !root.busy
                        onClicked: AirDrop.clearStaged()
                    }
                }
                // Nothing chosen yet: where to drop, and the quick ways to choose.
                Rectangle {
                    visible: !AirDrop.hasStaged
                    Layout.fillWidth: true
                    implicitHeight: 156
                    radius: Theme.radiusCard
                    color: drop.containsDrag ? Theme.accentSoft : Theme.well
                    border.width: 1
                    border.color: drop.containsDrag ? Theme.accentLine : Theme.edge
                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.fast
                        }
                    }
                    Column {
                        anchors.centerIn: parent
                        spacing: 6
                        C.Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: "send"
                            size: 26
                            color: drop.containsDrag ? Theme.accentText : Theme.textDim
                            transform: Translate {
                                y: drop.containsDrag && !Theme.reduced ? -4 : 0
                                Behavior on y {
                                    NumberAnimation {
                                        duration: Theme.reduced ? 0 : Theme.enter
                                        easing.type: Easing.OutBack
                                    }
                                }
                            }
                        }
                        C.Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: drop.containsDrag ? "Drop to share" : "Drop files or a link here"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            color: drop.containsDrag ? Theme.accentText : Theme.text
                        }
                        C.Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Ctrl+O to browse · Ctrl+V to paste a link"
                            color: Theme.textDim
                            font.pixelSize: 12
                        }
                        Item {
                            width: 1
                            height: 4
                        }
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 8
                            C.Button {
                                text: "Browse"
                                glyph: "folder"
                                implicitHeight: 32
                                onClicked: root.browsing = true
                            }
                            C.Button {
                                visible: root.latestShot !== ""
                                text: "Latest screenshot"
                                glyph: "image"
                                implicitHeight: 32
                                onClicked: AirDrop.stage([root.latestShot])
                            }
                            C.Button {
                                visible: root.clipboardLink
                                text: "Link from clipboard"
                                glyph: "link"
                                implicitHeight: 32
                                onClicked: AirDrop.stageUrl(root.clipboard)
                            }
                        }
                    }
                }
                // What is chosen, a row each; four at most, then how many more.
                ColumnLayout {
                    visible: AirDrop.hasStaged
                    Layout.fillWidth: true
                    spacing: 2
                    Repeater {
                        model: AirDrop.stagedUrl ? [{name: AirDrop.stagedUrl, kind: "link", size: -1}] : AirDrop.staged.slice(0, 4)
                        RowLayout {
                            id: item
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            Layout.preferredHeight: 36
                            spacing: 10
                            opacity: 0
                            Component.onCompleted: opacity = 1
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Theme.reduced ? 0 : Theme.enter
                                }
                            }
                            C.GlyphTile {
                                glyph: root.kindGlyph(item.modelData.kind)
                                size: 28
                                color: Theme.keyTile
                            }
                            C.Label {
                                text: item.modelData.name
                                font.pixelSize: 13
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }
                            C.Label {
                                visible: item.modelData.size >= 0
                                text: Format.bytes(item.modelData.size)
                                color: Theme.textDim
                                font.pixelSize: 12
                                font.features: ({"tnum": 1})
                            }
                            C.Button {
                                glyph: "close"
                                flat: true
                                hint: "Remove"
                                implicitWidth: 28
                                implicitHeight: 28
                                enabled: !root.busy
                                onClicked: AirDrop.unstage(AirDrop.stagedUrl ? -1 : item.index)
                            }
                        }
                    }
                    C.Label {
                        visible: !AirDrop.stagedUrl && AirDrop.staged.length > 4
                        text: "and " + (AirDrop.staged.length - 4) + " more"
                        color: Theme.textDim
                        font.pixelSize: 12
                        Layout.leftMargin: 38
                        Layout.topMargin: 2
                    }
                }
                // The devices nearby, once there is something to send.
                Rectangle {
                    visible: AirDrop.hasStaged || AirDrop.looking || AirDrop.peers.count > 0
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Theme.hairline
                }
                RowLayout {
                    visible: AirDrop.hasStaged || AirDrop.looking || AirDrop.peers.count > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    spacing: 8
                    C.Label {
                        text: "Send to"
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    C.Label {
                        text: root.sendStatus
                        color: root.busy ? Theme.accentText : Theme.textDim
                        font.pixelSize: 12
                        font.features: ({"tnum": 1})
                        Layout.fillWidth: true
                    }
                    C.Button {
                        visible: root.busy
                        text: "Cancel"
                        implicitHeight: 28
                        onClicked: AirDrop.cancel(AirDrop.sending.peerId)
                    }
                    C.Button {
                        visible: AirDrop.looking && !root.busy
                        text: "Stop"
                        flat: true
                        hint: "Stop looking; Wi-Fi gets the radio back"
                        implicitHeight: 28
                        onClicked: AirDrop.endSearch()
                    }
                    C.Button {
                        visible: !AirDrop.looking
                        text: AirDrop.sendState === "ended" ? "Look again" : "Look for devices"
                        glyph: "search"
                        accent: AirDrop.hasStaged
                        enabled: !AirDrop.recovering
                        implicitHeight: 28
                        onClicked: AirDrop.search()
                    }
                }
                // No device yet: the radar while looking, else why not and what to do.
                RowLayout {
                    visible: AirDrop.peers.count === 0 && (AirDrop.hasStaged || AirDrop.looking)
                    Layout.fillWidth: true
                    Layout.leftMargin: -6
                    spacing: 8
                    // Room for the rings to widen without reaching the edge or the row above.
                    Item {
                        implicitWidth: 60
                        implicitHeight: 60
                        AirDropRadar {
                            anchors.centerIn: parent
                            size: 28
                            live: AirDrop.looking
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        C.Label {
                            text: root.searchWords[0]
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                        }
                        C.Label {
                            text: root.searchWords[1]
                            color: Theme.textDim
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            elide: Text.ElideNone
                            Layout.fillWidth: true
                        }
                    }
                }
                // Four to a row, each filling its share.
                Flow {
                    id: peerFlow
                    visible: AirDrop.peers.count > 0
                    Layout.fillWidth: true
                    spacing: 4
                    readonly property real cell: Math.floor((width - spacing * 3) / 4)
                    Repeater {
                        model: AirDrop.peers
                        AirDropPeer {
                            required property int index
                            width: peerFlow.cell
                            order: index
                            ready: AirDrop.hasStaged && !root.busy && AirDrop.looking
                            onClicked: moving ? AirDrop.cancel(peerId) : AirDrop.sendTo(peerId)
                        }
                    }
                }
            }
        }
        // What came and went this session, else the newest files in the AirDrop folder. A row opens what it names.
        Rectangle {
            visible: AirDrop.available && !root.browsing && (AirDrop.recent.length > 0 || root.folderRows.length > 0)
            Layout.fillWidth: true
            implicitHeight: recentColumn.implicitHeight + 20
            radius: Theme.radiusModule
            color: Theme.module
            ColumnLayout {
                id: recentColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    Layout.bottomMargin: 2
                    C.Label {
                        text: "Recent"
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                    }
                    C.Button {
                        text: "Open folder"
                        glyph: "folder"
                        flat: true
                        implicitHeight: 28
                        onClicked: ShellState.openPath(AirDrop.folderPath)
                    }
                }
                Repeater {
                    model: AirDrop.recent.length ? AirDrop.recent.slice(0, 3) : root.folderRows
                    AbstractButton {
                        id: entry
                        required property var modelData
                        readonly property string target: modelData.url || (modelData.paths && modelData.paths.length ? modelData.paths[0] : "")
                        readonly property bool good: modelData.phase === "done"
                        readonly property bool picture: good && !modelData.url && /\.(jpe?g|png|webp|gif)$/i.test(target)
                        Layout.fillWidth: true
                        implicitHeight: 48
                        enabled: good && target !== ""
                        hoverEnabled: true
                        Accessible.name: (modelData.url ? "Open link " : "Open ") + modelData.title
                        onClicked: modelData.url ? AirDrop.openLink(modelData.url) : ShellState.openPath(target)
                        background: Rectangle {
                            radius: Theme.radiusKey
                            color: entry.hovered || entry.visualFocus ? Theme.rowWash(entry.down) : "transparent"
                            Behavior on color {
                                ColorAnimation {
                                    duration: Theme.fast
                                }
                            }
                        }
                        contentItem: RowLayout {
                            spacing: 10
                            // A picture shows itself; anything else its direction.
                            Rectangle {
                                implicitWidth: 34
                                implicitHeight: 34
                                radius: 9
                                color: Theme.keyTile
                                clip: true
                                Layout.leftMargin: 4
                                C.Icon {
                                    anchors.centerIn: parent
                                    visible: thumb.status !== Image.Ready
                                    name: entry.modelData.url ? "link" : entry.modelData.dir === "out" ? "send" : "download"
                                    size: 16
                                    color: entry.good ? Theme.text : Theme.dangerText
                                }
                                Image {
                                    id: thumb
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    source: entry.picture ? "file://" + entry.target.split("/").map(encodeURIComponent).join("/") : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize: Qt.size(68, 68)
                                }
                            }
                            ColumnLayout {
                                spacing: 0
                                Layout.fillWidth: true
                                C.Label {
                                    text: entry.modelData.title
                                    font.pixelSize: 13
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                }
                                C.Label {
                                    readonly property var m: entry.modelData
                                    text: [m.who ? (m.dir === "out" ? "to " : "from ") + m.who : "",
                                           m.phase === "done" ? (m.bytes ? Format.bytes(m.bytes) : "")
                                           : ({declined: "declined", failed: m.dir === "in" ? "didn't arrive" : "didn't send", cancelled: "cancelled"})[m.phase] || "",
                                           m.time ? root.ago(m.time) : ""].filter(part => part).join(" · ")
                                    color: entry.good ? Theme.textDim : Theme.dangerText
                                    font.pixelSize: 12
                                    Layout.fillWidth: true
                                }
                            }
                            C.Label {
                                visible: entry.enabled && entry.hovered
                                text: entry.modelData.url ? "Open link" : "Open"
                                color: Theme.textDim
                                font.pixelSize: 12
                            }
                            C.Button {
                                visible: entry.good && !entry.modelData.url && entry.target !== ""
                                glyph: "folder"
                                hint: "Show in folder"
                                flat: true
                                implicitWidth: 28
                                implicitHeight: 28
                                Layout.rightMargin: 4
                                onClicked: ShellState.openPath(entry.target.slice(0, entry.target.lastIndexOf("/")))
                            }
                        }
                    }
                }
            }
        }
    }
    // The newest files received before this session, for Recent. A folder that doesn't exist yet leaves a folder model
    // on the working directory, so only paths inside the folder count. Read when the model changes: a binding over
    // get() ran once, before the folder had loaded, and stayed empty.
    property var folderRows: []
    function readFolder() {
        const rows = [];
        const inside = AirDrop.folderPath.replace(/\/+$/, "") + "/";
        for (let i = 0; i < received.count && rows.length < 3; i++) {
            const path = String(received.get(i, "filePath"));
            if (!path.startsWith(inside))
                continue;
            const modified = received.get(i, "fileModified");
            rows.push({dir: "in", title: received.get(i, "fileName"), paths: [path], phase: "done", who: "",
                       bytes: received.get(i, "fileIsDir") ? 0 : received.get(i, "fileSize"), time: modified ? modified.getTime() : 0});
        }
        folderRows = rows;
    }
    FolderListModel {
        id: received
        folder: "file://" + AirDrop.folderPath.split("/").map(encodeURIComponent).join("/")
        showDirs: true
        sortField: FolderListModel.Time
        onCountChanged: Qt.callLater(root.readFolder)
        onStatusChanged: Qt.callLater(root.readFolder)
    }
    readonly property string screenshots: String(ShellState.setting("screenshotDirectory", "~/Pictures/Screenshots")).replace(/^~(?=\/)/, AirDrop.home).replace(/\/+$/, "")
    readonly property string latestShot: latest.count > 0 && String(latest.get(0, "filePath")).startsWith(screenshots + "/") ? latest.get(0, "filePath") : ""
    FolderListModel {
        id: latest
        folder: "file://" + root.screenshots.split("/").map(encodeURIComponent).join("/")
        nameFilters: ["*.png", "*.jpg", "*.jpeg"]
        showDirs: false
        sortField: FolderListModel.Time
    }
}
