import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../core"
import "../services"
import "../components" as C

PanelWindow {
    id: bar
    component BarButton: C.Button {
        labelSize: Theme.barText
        implicitHeight: 30
        Layout.maximumHeight: 30
        Layout.alignment: Qt.AlignVCenter
    }
    required property string outputName
    readonly property bool compact: width < 760
    IpcHandler {
        target: "bar-" + bar.outputName
        function status(): string {
            return JSON.stringify({control: bar.controlActive(""), wifi: bar.controlActive("wifi"), audio: bar.controlActive("audio"), power: bar.controlActive("power"), media: bar.controlActive("media"), tray: bar.controlActive("tray")});
        }
    }
    function controlActive(detail) {
        return ShellState.panel === "control" && ShellState.detail === detail && ShellState.screenName === outputName;
    }
    function toggleControl(detail) {
        if (controlActive(detail)) {
            ShellState.close();
        } else {
            ShellState.open("control", bar.screen.name);
            ShellState.detail = detail;
        }
    }
    anchors {
        top: true
        left: true
        right: true
    }
    margins {
        top: 5
        left: 8
        right: 8
    }
    implicitHeight: 32
    color: "transparent"
    WlrLayershell.namespace: "shale-bar"
    WlrLayershell.layer: WlrLayer.Top
    exclusionMode: ExclusionMode.Auto
    readonly property var monitor: Services.workspaces.find(w => w.monitor && w.monitor.name === bar.outputName && w.active)
    visible: !ShellState.locked && !(ShellState.setting("hideFullscreen", true) && monitor && monitor.hasFullscreen) && ShellState.setting("hiddenOutputs", []).indexOf(bar.outputName) < 0
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
    // One quiet rail gives the independent controls a shared visual baseline.
    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSmall + 2
        color: Theme.panel
    }
    RowLayout {
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
            leftMargin: 5
        }
        width: implicitWidth
        spacing: Theme.gapS
        BarButton {
            glyph: "grid"
            selected: ShellState.panel === "launcher" && ShellState.screenName === bar.outputName
            flat: true
            hint: "Applications"
            tooltip: barTooltip
            onClicked: ShellState.toggle("launcher", bar.screen.name)
        }
        ListView {
            id: workspaceStrip
            Layout.preferredWidth: Math.min(Math.max(78, bar.width / 2 - 170), 238, workspaceModel.count * 26)
            Layout.fillHeight: true
            clip: true
            orientation: ListView.Horizontal
            spacing: Theme.gapXs
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentWidth > width
            readonly property int activeId: bar.monitor ? bar.monitor.id : (Services.focusedWorkspace ? Services.focusedWorkspace.id : 1)
            readonly property var occupied: Services.workspaces.filter(w => w.id > 0 && w.monitor && w.monitor.name === bar.outputName && (w.id === activeId || Services.windows.some(win => win.workspace && win.workspace.id === w.id))).sort((a, b) => a.id - b.id)
            function syncWorkspaces() {
                if (!workspaceModel)
                    return;
                const entries = occupied.map(w => ({ workspaceId: w.id, workspaceName: w.name || String(w.id), urgent: !!w.urgent }));
                if (!entries.some(w => w.workspaceId === activeId) && activeId > 0)
                    entries.push({ workspaceId: activeId, workspaceName: String(activeId), urgent: false });
                entries.sort((a, b) => a.workspaceId - b.workspaceId);
                for (let i = workspaceModel.count - 1; i >= 0; --i)
                    if (!entries.some(w => w.workspaceId === workspaceModel.get(i).workspaceId))
                        workspaceModel.remove(i);
                for (let i = 0; i < entries.length; ++i) {
                    if (i >= workspaceModel.count || workspaceModel.get(i).workspaceId !== entries[i].workspaceId)
                        workspaceModel.insert(i, entries[i]);
                    else
                        workspaceModel.set(i, entries[i]);
                }
                currentIndex = entries.findIndex(w => w.workspaceId === activeId);
            }
            onOccupiedChanged: syncWorkspaces()
            onActiveIdChanged: syncWorkspaces()
            Component.onCompleted: syncWorkspaces()
            model: ListModel { id: workspaceModel }
            highlightMoveDuration: Theme.reduced ? 0 : 220
            highlightResizeDuration: 0
            highlight: Item {
                Rectangle {
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    radius: 6
                    color: Theme.selection
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                }
            }
            delegate: BarButton {
                id: workspaceButton
                required property int workspaceId
                required property string workspaceName
                required property bool urgent
                width: 22
                height: workspaceStrip.height
                padding: 0
                flat: true
                hint: "Workspace " + workspaceName
                contentItem: C.Label {
                    text: workspaceButton.workspaceName
                    horizontalAlignment: Text.AlignHCenter
                    color: workspaceStrip.activeId === workspaceButton.workspaceId ? Theme.accentText : workspaceButton.urgent ? Theme.warning : Theme.muted
                    font.pixelSize: Theme.barText - 1
                    font.family: Theme.mono
                }
                background: Rectangle {
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    radius: 6
                    color: workspaceButton.hovered || workspaceButton.visualFocus ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12) : "transparent"
                }
                onClicked: Services.workspace(workspaceId)
            }
            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.fast }
            }
            remove: Transition {
                NumberAnimation { property: "opacity"; to: 0; duration: Theme.fast }
            }
            displaced: Transition {
                NumberAnimation { property: "x"; duration: Theme.reduced ? 0 : 200; easing.type: Easing.OutCubic }
            }
            WheelHandler {
                onWheel: event => {
                    if (!workspaceModel.count || event.angleDelta.y === 0)
                        return;
                    const next = (workspaceStrip.currentIndex + (event.angleDelta.y < 0 ? 1 : -1) + workspaceModel.count) % workspaceModel.count;
                    Services.workspace(workspaceModel.get(next).workspaceId);
                }
            }
        }
        Rectangle {
            visible: bar.width > 1400
            Layout.preferredWidth: 1
            Layout.preferredHeight: 12
            color: Theme.hover
        }
        BarButton {
            Layout.preferredWidth: 150
            Layout.maximumWidth: 150
            clip: true
            visible: bar.width > 1400
            flat: true
            hint: Services.activeWindow ? Services.activeWindow.title : "Workspace overview"
            contentItem: C.Label {
                text: Services.activeWindow ? Services.activeWindow.title : "Shale"
                color: Theme.muted
                font.pixelSize: Theme.barText
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignLeft
            }
            onClicked: ShellState.toggle("overview", bar.screen.name)
        }
    }
    BarButton {
        id: clockButton
        anchors.centerIn: parent
        // Measure before laying out: an eliding Text can report a constrained
        // implicit width when it is used directly as a button content item.
        implicitWidth: Math.ceil(clockMetrics.advanceWidth) + 24
        width: implicitWidth
        implicitHeight: 26
        TextMetrics {
            id: clockMetrics
            text: clockButton.text
            font.family: Theme.mono
            font.pixelSize: Theme.barText
        }
        flat: true
        text: Qt.formatDateTime(clock.date, "ddd   " + ShellState.timeFormat)
        contentItem: C.Label {
            text: clockButton.text
            font.family: Theme.mono
            font.pixelSize: Theme.barText
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideNone
        }
        hint: Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy")
        tooltip: barTooltip
        onClicked: ShellState.toggle("calendar", bar.screen.name)
    }
    RowLayout {
        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
            rightMargin: 5
        }
        spacing: Theme.gapXs
        BarButton {
            id: mediaButton
            // Narrow bars keep the cover and visualizer but drop the title.
            readonly property bool wide: bar.width > 1600
            readonly property var player: NowPlaying.player
            visible: !!player && bar.width > 1100 && ShellState.setting("barMedia", true)
            flat: true
            leftPadding: 6
            rightPadding: wide ? 10 : 8
            Layout.maximumWidth: wide ? 210 : 60
            hint: "Media controls"
            Accessible.name: player ? "Now playing: " + (player.trackTitle || player.identity) : "Media controls"
            selected: bar.controlActive("media")
            onClicked: bar.toggleControl("media")
            HoverHandler {
                id: mediaHover
            }
            contentItem: RowLayout {
                spacing: Theme.gapS
                C.CoverArt {
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                    radius: 5
                    glyphSize: 11
                    source: NowPlaying.artUrl
                }
                C.Label {
                    visible: mediaButton.wide
                    text: mediaButton.player ? mediaButton.player.trackTitle || mediaButton.player.identity : ""
                    color: NowPlaying.playing || mediaButton.selected ? Theme.text : Theme.muted
                    font.pixelSize: Theme.barText
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    Layout.maximumWidth: 140
                }
                C.Spectrum {
                    visible: NowPlaying.playing && available
                    Layout.preferredWidth: 17
                    Layout.preferredHeight: 12
                    Layout.alignment: Qt.AlignVCenter
                    bars: 6
                    spacing: 1
                    floor: 1.5
                    maxRadius: 1
                    curve: 0.6
                    color: NowPlaying.artColors[0]
                    secondary: NowPlaying.artColors[1]
                    active: bar.visible && mediaButton.visible && NowPlaying.playing && ShellState.setting("visualizer", true) && !Theme.reduced && !Theme.lowPower
                }
            }
        }
        Repeater {
            model: Services.trayItems.slice(0, bar.width > 1700 ? 3 : bar.width > 1100 ? 2 : 0)
            BarButton {
                id: trayButton
                required property var modelData
                flat: true
                hint: modelData.tooltipTitle || modelData.title || modelData.id
                tooltip: barTooltip
                contentItem: Image {
                    source: modelData.icon
                    sourceSize.width: 18
                    sourceSize.height: 18
                    fillMode: Image.PreserveAspectFit
                }
                implicitWidth: 26
                selected: trayMenu.shown && trayMenu.item === modelData
                onClicked: modelData.onlyMenu ? trayMenu.toggle(modelData, bar, trayButton) : modelData.activate()
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: {
                        barTooltip.hide(trayButton, true);
                        trayMenu.toggle(modelData, bar, trayButton);
                    }
                }
                TapHandler {
                    acceptedButtons: Qt.MiddleButton
                    onTapped: {
                        barTooltip.hide(trayButton, true);
                        trayButton.modelData.secondaryActivate();
                    }
                }
                // Apps such as volume mixers act on scrolling; deltas are Qt's, as Plasma sends them.
                WheelHandler {
                    onWheel: event => {
                        if (event.angleDelta.y !== 0)
                            trayButton.modelData.scroll(event.angleDelta.y, false);
                        if (event.angleDelta.x !== 0)
                            trayButton.modelData.scroll(event.angleDelta.x, true);
                    }
                }
            }
        }
        BarButton {
            visible: Services.trayItems.length > (bar.width > 1700 ? 3 : bar.width > 1100 ? 2 : 0)
            glyph: "grid"
            flat: true
            hint: "System tray"
            tooltip: barTooltip
            selected: bar.controlActive("tray")
            onClicked: bar.toggleControl("tray")
        }
        BarButton {
            visible: ShellState.recording.active
            accent: true
            glyph: "record"
            text: "REC " + Math.floor(ShellState.recordingSeconds / 60) + ":" + String(ShellState.recordingSeconds % 60).padStart(2, "0")
            flat: true
            hint: "Stop recording"
            tooltip: barTooltip
            onClicked: ShellState.action("stop-recording")
            contentItem: Item {
                // Mono digits keep the chip from jittering every second.
                implicitWidth: recordingRow.implicitWidth
                implicitHeight: recordingRow.implicitHeight
                RowLayout {
                    id: recordingRow
                    anchors.centerIn: parent
                    spacing: Theme.gapS
                    C.Icon { name: "record"; size: 16; color: Theme.background }
                    C.Label {
                        text: "REC " + Math.floor(ShellState.recordingSeconds / 60) + ":" + String(ShellState.recordingSeconds % 60).padStart(2, "0")
                        color: Theme.background
                        font.family: Theme.mono
                        font.pixelSize: Theme.barText
                    }
                }
            }
        }
        BarButton {
            id: privacyButton
            readonly property bool mic: Services.micUsers.length > 0
            readonly property bool sharing: Services.screenSharers.length > 0
            visible: mic || sharing
            accent: true
            flat: true
            hint: [mic ? "Microphone in use: " + Services.micUsers.join(", ") : "",
                   sharing ? "Sharing your screen with " + Services.screenSharers.join(", ") : ""].filter(line => line).join("\n")
            tooltip: barTooltip
            contentItem: Row {
                spacing: Theme.gapXs
                C.Icon { visible: privacyButton.mic; name: "mic"; size: 16; color: Theme.background; anchors.verticalCenter: parent.verticalCenter }
                C.Icon { visible: privacyButton.sharing; name: "cast"; size: 16; color: Theme.background; anchors.verticalCenter: parent.verticalCenter }
            }
            onClicked: bar.toggleControl("audio")
        }
        BarButton {
            id: focusButton
            visible: Focus.active
            accent: true
            flat: true
            readonly property string remaining: Focus.remainingSeconds < 60 ? Focus.remainingSeconds + "s" : Focus.minutesText(Focus.remainingSeconds)
            hint: "Focus · " + remaining + " left\nClick to end · Scroll to add or take 5 min"
            tooltip: barTooltip
            Accessible.name: "Focus, " + remaining + " left"
            onClicked: Focus.end(true)
            WheelHandler {
                onWheel: event => {
                    if (event.angleDelta.y !== 0)
                        Focus.extend(event.angleDelta.y > 0 ? 5 : -5);
                }
            }
            contentItem: Item {
                implicitWidth: focusRow.implicitWidth
                implicitHeight: focusRow.implicitHeight
                RowLayout {
                    id: focusRow
                    anchors.centerIn: parent
                    spacing: Theme.gapS
                    // The ring empties as the session runs out.
                    Shape {
                        Layout.preferredWidth: 16
                        Layout.preferredHeight: 16
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.3)
                            strokeWidth: 2
                            fillColor: "transparent"
                            PathAngleArc { centerX: 8; centerY: 8; radiusX: 6.5; radiusY: 6.5; startAngle: 0; sweepAngle: 360 }
                        }
                        ShapePath {
                            strokeColor: Theme.background
                            strokeWidth: 2
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathAngleArc { centerX: 8; centerY: 8; radiusX: 6.5; radiusY: 6.5; startAngle: -90; sweepAngle: 360 * Focus.progress }
                        }
                    }
                    C.Label {
                        text: focusButton.remaining
                        color: Theme.background
                        font.family: Theme.mono
                        font.pixelSize: Theme.barText
                    }
                }
            }
        }
        BarButton {
            id: timerButton
            readonly property var timer: Focus.nextTimer
            readonly property int remaining: timer ? Math.max(0, Math.ceil((timer.endsAt - Focus.now) / 1000)) : 0
            visible: !!timer
            flat: true
            hint: Focus.timers.map(t => (t.label || Focus.minutesText(t.seconds) + " timer") + " · " + Focus.clockText(Math.max(0, Math.ceil((t.endsAt - Focus.now) / 1000)))).join("\n") + "\nClick to cancel the first"
            tooltip: barTooltip
            Accessible.name: "Timer, " + Focus.clockText(remaining) + " left"
            onClicked: {
                const timer = timerButton.timer, left = timerButton.remaining;
                Focus.cancelTimer(timer.id);
                ShellState.message("Timer cancelled", "info", {label: "Undo", run: () => Focus.addTimer(left, timer.label)});
            }
            contentItem: Item {
                implicitWidth: timerRow.implicitWidth
                implicitHeight: timerRow.implicitHeight
                RowLayout {
                    id: timerRow
                    anchors.centerIn: parent
                    spacing: Theme.gapS
                    C.Icon { name: "timer"; size: 16; color: timerButton.foreground }
                    C.Label {
                        text: Focus.clockText(timerButton.remaining)
                        color: timerButton.foreground
                        font.family: Theme.mono
                        font.pixelSize: Theme.barText
                    }
                }
            }
        }
        BarButton {
            visible: ShellState.presentation
            glyph: "moon"
            flat: true
            hint: "Stay awake is on"
            tooltip: barTooltip
            onClicked: ShellState.presentation = false
        }
        BarButton {
            visible: bar.width >= 560 && ShellState.wifiAvailable
            glyph: "wifi"
            flat: true
            // Dimmed while disconnected so a dropped network is visible at a glance.
            opacity: ShellState.wifi.state === "connected" || bar.controlActive("wifi") ? 1 : 0.45
            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
            hint: {
                const network = (ShellState.wifi.networks || []).find(n => n.connected);
                return ShellState.wifi.state === "connected" ? "Wi-Fi" + (network ? " · " + network.name : "") : ShellState.wifi.powered ? "Wi-Fi · Not connected" : "Wi-Fi · Off";
            }
            tooltip: barTooltip
            selected: bar.controlActive("wifi")
            onClicked: bar.toggleControl("wifi")
        }
        BarButton {
            glyph: Services.muted ? "mute" : "volume"
            selected: bar.controlActive("audio")
            flat: true
            hint: "Audio · " + Math.round(Services.volume * 100) + "%"
            tooltip: barTooltip
            onClicked: bar.toggleControl("audio")
            WheelHandler {
                onWheel: event => {
                    if (Services.audioAvailable && event.angleDelta.y !== 0)
                        Services.setVolume(Services.volume + (event.angleDelta.y > 0 ? 0.05 : -0.05));
                }
            }
            TapHandler {
                acceptedButtons: Qt.MiddleButton
                onTapped: Services.toggleMute()
            }
        }
        BarButton {
            readonly property bool low: !Services.batteryCharging && Services.onBattery && Services.batteryPercent <= 20
            visible: Services.batteryAvailable
            // Low charge always shows its number, even on compact bars.
            Layout.preferredWidth: bar.compact && !low ? 36 : 76
            glyph: Services.batteryCharging ? "bolt" : "battery"
            text: bar.compact && !low ? "" : Math.round(Services.batteryPercent) + "%"
            tone: !low ? "" : Services.batteryPercent <= 10 ? "danger" : "warning"
            flat: true
            hint: "Battery and power profiles"
            tooltip: barTooltip
            Accessible.name: "Battery " + Math.round(Services.batteryPercent) + "%" + (Services.batteryCharging ? ", charging" : "")
            selected: bar.controlActive("power")
            onClicked: bar.toggleControl("power")
        }
        BarButton {
            // Do not disturb swaps the bell so suppressed popups are never a surprise.
            glyph: ShellState.setting("dnd", false) ? "bell-off" : "bell"
            Layout.preferredWidth: bar.compact ? 36 : 58
            selected: ShellState.panel === "notifications" && ShellState.screenName === bar.outputName
            flat: true
            text: !bar.compact && Services.notifications.length ? (Services.notifications.length > 99 ? "99+" : String(Services.notifications.length)) : ""
            hint: "Notifications"
            tooltip: barTooltip
            Accessible.name: "Notifications" + (ShellState.setting("dnd", false) ? ", do not disturb" : "") + (Services.notifications.length ? ", " + Services.notifications.length + " waiting" : "")
            Rectangle {
                visible: bar.compact && Services.notifications.length > 0
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.top: parent.top
                anchors.topMargin: 4
                width: 5
                height: 5
                radius: 2.5
                color: Theme.accent
            }
            onClicked: ShellState.toggle("notifications", bar.screen.name)
        }
        BarButton {
            glyph: "settings"
            selected: bar.controlActive("")
            implicitHeight: 26
            flat: false
            hint: "Control center"
            tooltip: barTooltip
            onClicked: bar.toggleControl("")
        }
    }
    TrayMenu {
        id: trayMenu
    }
    C.Tooltip {
        id: barTooltip
        anchor.window: bar
    }
    MediaHoverCard {
        bar: bar
        button: mediaButton
        buttonHovered: mediaHover.hovered && mediaButton.visible && bar.visible
    }
}
