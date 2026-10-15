import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../core"
import "../services"
import "../components" as C

Scope {
    id: root
    required property var screen
    readonly property bool target: ShellState.targetScreen() === screen.name
    PanelWindow {
        id: popups
        screen: root.screen
        anchors {
            top: true
            right: true
        }
        margins {
            top: 48
            right: 12
        }
        implicitWidth: Math.min(380, screen.width - 24)
        implicitHeight: Math.max(1, Math.min(screen.height - 96, popupList.contentHeight))
        property int retiring: 0
        readonly property bool wanted: root.target && !ShellState.locked && (Services.popupModel.count > 0 || retiring > 0) && ShellState.panel !== "notifications"
        // Applied after the change settles: mapping the window as the session unlocks updates the focused
        // output (and so `target`) while `visible` is still being set, which Qt reports as a binding loop.
        visible: false
        onWantedChanged: Qt.callLater(() => popups.visible = popups.wanted)
        Component.onCompleted: visible = wanted
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "shale-notifications"
        WlrLayershell.layer: WlrLayer.Overlay
        ListView {
            id: popupList
            anchors.fill: parent
            spacing: Theme.gapS
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            model: Services.popupModel
            delegate: NotificationCard {
                id: popupCard
                required property var notificationData
                notification: notificationData
                popup: true
                width: popupList.width
                ListView.onRemove: {
                    popups.retiring++;
                    removal.start();
                }
                SequentialAnimation {
                    id: removal
                    PropertyAction { target: popupCard; property: "ListView.delayRemove"; value: true }
                    NumberAnimation { target: popupCard; property: "opacity"; to: 0; duration: Theme.leave }
                    ScriptAction { script: popups.retiring-- }
                    PropertyAction { target: popupCard; property: "ListView.delayRemove"; value: false }
                }
            }
            add: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.enter }
                    NumberAnimation { property: "x"; from: Theme.reduced ? 0 : 10; to: 0; duration: Theme.enter; easing.type: Easing.OutCubic }
                }
            }
            displaced: Transition {
                NumberAnimation { property: "y"; duration: Theme.reduced ? 0 : Theme.enter; easing.type: Easing.OutCubic }
            }
        }
    }
    PanelWindow {
        id: osdWindow
        readonly property bool level: ShellState.osdValue >= 0
        property real reveal: root.target && ShellState.osdVisible && !ShellState.locked ? 1 : 0
        Behavior on reveal { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }
        screen: root.screen
        anchors {
            bottom: true
        }
        margins.bottom: ShellState.toast !== "" ? 92 : 64
        implicitWidth: 300
        implicitHeight: 44
        visible: root.target && !ShellState.locked && reveal > 0
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "shale-osd"
        WlrLayershell.layer: WlrLayer.Overlay
        // Nothing here is clickable, so clicks reach the windows underneath.
        mask: Region {}
        // A pill that fills with the level; countdowns show only their label.
        Rectangle {
            id: pill
            anchors.fill: parent
            radius: height / 2
            color: Theme.panel
            border.width: 1
            border.color: Theme.border
            opacity: osdWindow.reveal
            clip: true
            transform: [
                Scale {
                    origin.x: pill.width / 2
                    origin.y: pill.height / 2
                    xScale: Theme.reduced ? 1 : 0.94 + 0.06 * osdWindow.reveal
                    yScale: xScale
                },
                Translate { y: Theme.reduced ? 0 : (1 - osdWindow.reveal) * 6 }
            ]
            Rectangle {
                visible: osdWindow.level
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.margins: 1
                // Never narrower than the round end, so low levels still read as a filled cap.
                width: Math.max(height, (parent.width - 2) * Math.max(0, Math.min(1, ShellState.osdValue)))
                opacity: ShellState.osdValue > 0 ? 1 : 0.5
                radius: height / 2
                // Muted keeps the real level visible, just quieter.
                color: ShellState.osdMuted ? Theme.raised : Theme.selection
                Behavior on color { ColorAnimation { duration: Theme.fast } }
                Behavior on width { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 13
                anchors.rightMargin: 16
                spacing: Theme.gapM
                C.Icon {
                    id: osdIcon
                    name: ShellState.osdGlyph
                    size: 18
                    opacity: ShellState.osdMuted ? 0.6 : 1
                    // A small bump on every change confirms the key press even at 0% or 100%.
                    SequentialAnimation {
                        id: bump
                        NumberAnimation { target: osdIcon; property: "scale"; to: 1.2; duration: 70; easing.type: Easing.OutQuad }
                        NumberAnimation { target: osdIcon; property: "scale"; to: 1; duration: 160; easing.type: Easing.OutBack }
                    }
                    Connections {
                        target: ShellState
                        function onOsdSerialChanged() {
                            if (!Theme.reduced && osdWindow.reveal > 0)
                                bump.restart();
                        }
                    }
                }
                C.Label {
                    text: ShellState.osdLabel
                    font.pixelSize: Theme.small
                    color: osdWindow.level ? Theme.muted : Theme.text
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    horizontalAlignment: osdWindow.level ? Text.AlignLeft : Text.AlignHCenter
                }
                C.Label {
                    visible: osdWindow.level
                    text: Math.round(ShellState.osdValue * 100) + "%"
                    font.family: Theme.mono
                    font.pixelSize: Theme.small
                    color: ShellState.osdMuted ? Theme.muted : Theme.text
                }
            }
        }
    }
    // Brief "now playing" card when the track changes in the background.
    PanelWindow {
        id: trackWindow
        property string title: ""
        property string artist: ""
        property string art: ""
        property bool shown: false
        readonly property var workspace: Services.workspaces.find(w => w.monitor && w.monitor.name === root.screen.name && w.active)
        readonly property bool allowed: root.target && !ShellState.locked && ShellState.setting("trackChangeCard", true) && !Focus.digest
            && !(workspace && workspace.hasFullscreen) && !(ShellState.panel === "control" && ShellState.detail === "media")
        property real reveal: shown && allowed ? 1 : 0
        Behavior on reveal { NumberAnimation { duration: trackWindow.shown ? Theme.enter : Theme.leave; easing.type: Easing.OutCubic } }
        Connections {
            target: NowPlaying
            function onTrackChanged() {
                const player = NowPlaying.player;
                if (!trackWindow.allowed || !player)
                    return;
                trackWindow.title = player.trackTitle || "";
                trackWindow.artist = player.trackArtist || player.identity || "";
                trackWindow.art = player.trackArtUrl || "";
                trackWindow.shown = true;
                if (!trackHover.hovered)
                    trackTimer.restart();
            }
        }
        Timer {
            id: trackTimer
            interval: 3500
            onTriggered: trackWindow.shown = false
        }
        screen: root.screen
        anchors {
            top: true
        }
        margins.top: 46
        implicitWidth: 340
        implicitHeight: 64
        visible: reveal > 0
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "shale-track"
        WlrLayershell.layer: WlrLayer.Overlay
        Rectangle {
            anchors.fill: parent
            radius: Theme.panelRadius
            color: Theme.panel
            border.width: 1
            border.color: Theme.border
            opacity: trackWindow.reveal
            transform: Translate { y: Theme.reduced ? 0 : (1 - trackWindow.reveal) * -8 }
            HoverHandler {
                id: trackHover
                // Reading the card keeps it open; leaving gives a moment before it goes.
                onHoveredChanged: if (hovered)
                    trackTimer.stop();
                else if (trackWindow.shown)
                    trackTimer.restart()
            }
            TapHandler {
                onTapped: {
                    trackWindow.shown = false;
                    ShellState.open("control", root.screen.name);
                    ShellState.detail = "media";
                }
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: Theme.gapM
                C.CoverArt {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    radius: Theme.radiusSmall + 2
                    source: trackWindow.art
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    C.Label {
                        text: trackWindow.title
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    C.Label {
                        text: trackWindow.artist
                        color: Theme.muted
                        font.pixelSize: Theme.small
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
                C.Button {
                    glyph: "next"
                    flat: true
                    implicitWidth: 36
                    implicitHeight: Theme.controlHeight
                    cornerRadius: 18
                    hint: "Next track"
                    visible: !!NowPlaying.player && NowPlaying.player.canGoNext
                    onClicked: NowPlaying.player.next()
                }
            }
        }
    }
    // What came in during a focus session, grouped by app. Stays until dismissed.
    PanelWindow {
        id: digestWindow
        readonly property var digest: Focus.digest
        property var retained: null
        onDigestChanged: if (digest)
            retained = digest
        readonly property var groups: retained ? retained.groups : []
        property real reveal: root.target && !!digest && !ShellState.locked ? 1 : 0
        Behavior on reveal { NumberAnimation { duration: digestWindow.digest ? Theme.enter : Theme.leave; easing.type: Easing.OutCubic } }
        screen: root.screen
        anchors {
            top: true
        }
        margins.top: 46
        implicitWidth: Math.min(380, screen.width - 24)
        implicitHeight: digestColumn.implicitHeight + 2 * Theme.gapM
        visible: reveal > 0
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "shale-digest"
        WlrLayershell.layer: WlrLayer.Overlay
        Rectangle {
            anchors.fill: parent
            radius: Theme.panelRadius
            color: Theme.panel
            border.width: 1
            border.color: Theme.border
            opacity: digestWindow.reveal
            transform: Translate { y: Theme.reduced ? 0 : (1 - digestWindow.reveal) * -8 }
            ColumnLayout {
                id: digestColumn
                anchors.fill: parent
                anchors.margins: Theme.gapM
                spacing: Theme.gapS
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.gapM
                    C.GlyphTile { glyph: "focus" }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        C.Label {
                            text: digestWindow.retained ? "While you focused · " + digestWindow.retained.minutes + " min" : ""
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        C.Caption {
                            readonly property int total: digestWindow.retained ? digestWindow.retained.total : 0
                            text: total + (total === 1 ? " notification" : " notifications") + " from " + digestWindow.groups.length + (digestWindow.groups.length === 1 ? " app" : " apps")
                            Layout.fillWidth: true
                        }
                    }
                    C.Button {
                        glyph: "close"
                        flat: true
                        hint: "Dismiss"
                        onClicked: Focus.digest = null
                    }
                }
                Repeater {
                    model: digestWindow.groups.slice(0, 4)
                    RowLayout {
                        id: digestRow
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: 2
                        spacing: Theme.gapM
                        Item {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            Image {
                                id: digestIcon
                                anchors.centerIn: parent
                                visible: status === Image.Ready
                                source: digestRow.modelData.appIcon ? Quickshell.iconPath(digestRow.modelData.appIcon, "dialog-information") : ""
                                sourceSize.width: 24
                                sourceSize.height: 24
                                width: 24
                                height: 24
                            }
                            C.Icon {
                                anchors.centerIn: parent
                                visible: !digestIcon.visible
                                name: "bell"
                                size: 16
                                color: Theme.muted
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            C.Label {
                                text: digestRow.modelData.appName
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            C.Caption {
                                text: digestRow.modelData.latest
                                visible: text !== ""
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                Layout.fillWidth: true
                            }
                        }
                        C.Label {
                            text: String(digestRow.modelData.count)
                            font.family: Theme.mono
                            font.pixelSize: Theme.small
                            color: Theme.muted
                        }
                    }
                }
                C.Caption {
                    visible: digestWindow.groups.length > 4
                    text: "and " + (digestWindow.groups.length - 4) + " more"
                    Layout.leftMargin: 42
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.gapXs
                    spacing: Theme.gapS
                    Item { Layout.fillWidth: true }
                    C.Button {
                        text: "Dismiss"
                        flat: true
                        onClicked: Focus.digest = null
                    }
                    C.Button {
                        text: "Open notifications"
                        onClicked: {
                            Focus.digest = null;
                            ShellState.open("notifications", root.screen.name);
                        }
                    }
                }
            }
        }
    }
    PanelWindow {
        id: messageWindow
        property string retainedText: ""
        property string retainedKind: "info"
        property var retainedAction: null
        property real reveal: root.target && ShellState.toast !== "" && !ShellState.locked ? 1 : 0
        Connections {
            target: ShellState
            function onToastChanged() {
                if (ShellState.toast === "")
                    return;
                messageWindow.retainedText = ShellState.toast;
                messageWindow.retainedKind = ShellState.toastKind;
                messageWindow.retainedAction = ShellState.toastAction;
            }
        }
        Behavior on reveal { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }
        screen: root.screen
        anchors {
            bottom: true
        }
        margins.bottom: 18
        TextMetrics {
            id: messageMetrics
            font.family: Theme.font
            font.pixelSize: Theme.body
            text: messageWindow.retainedText
        }
        implicitWidth: Math.min(560, screen.width - 40, Math.max(240, messageMetrics.advanceWidth + 100 + (retainedAction ? actionMetrics.advanceWidth + 36 : 0)))
        TextMetrics {
            id: actionMetrics
            font.family: Theme.font
            font.pixelSize: Theme.body
            text: messageWindow.retainedAction ? messageWindow.retainedAction.label : ""
        }
        implicitHeight: Math.max(60, messageLabel.implicitHeight + 24)
        visible: root.target && !ShellState.locked && reveal > 0
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "shale-message"
        WlrLayershell.layer: WlrLayer.Overlay
        Rectangle {
            anchors.fill: parent
            color: Theme.raised
            opacity: messageWindow.reveal
            transform: Translate { y: Theme.reduced ? 0 : (1 - messageWindow.reveal) * 6 }
            radius: Theme.controlRadius
            border.width: 0
            Rectangle {
                visible: messageWindow.retainedKind === "error"
                x: 0
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: 20
                radius: 1.5
                color: Theme.danger
            }
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                C.Icon {
                    name: messageWindow.retainedKind === "error" ? "alert" : messageWindow.retainedKind === "success" ? "check" : "info"
                }
                C.Label {
                    id: messageLabel
                    text: messageWindow.retainedText
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    color: messageWindow.retainedKind === "error" ? Theme.danger : Theme.text
                }
                C.Button {
                    visible: !!messageWindow.retainedAction
                    text: messageWindow.retainedAction ? messageWindow.retainedAction.label : ""
                    implicitHeight: 32
                    onClicked: {
                        const action = messageWindow.retainedAction;
                        ShellState.toast = "";
                        if (action)
                            action.run();
                    }
                }
                C.Button {
                    glyph: "close"
                    flat: true
                    hint: "Dismiss message"
                    onClicked: ShellState.toast = ""
                }
            }
        }
    }
}
