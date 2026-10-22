pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import "../core"
import "../core/barItems.js" as BarItems
import "../core/station.js" as Station
import "../services"
import "../components" as C

// The bar's items in their zones. Bar.qml puts it in a layer-shell window; previews put it in a plain one.
Item {
    id: bar
    component BarButton: C.Button {
        // Whether the item has something to show; the zone hides its slot otherwise.
        property bool shown: true
        labelSize: Theme.barText
        implicitHeight: 30
    }
    required property string outputName
    // The window it is in, the tooltip its buttons share and the tray menu, which open next to it.
    property var window: null
    property var tooltip: null
    property var trayMenu: null
    // False while the bar is hidden (fullscreen, lock): live visuals pause.
    property bool onScreen: true
    readonly property bool compact: width < 760
    readonly property bool edge: ShellState.setting("barStyle", "floating") === "edge"
    // Settings → Bar arranges the items; anything the saved layout doesn't mention keeps its default place.
    readonly property var layout: BarItems.layout(ShellState.setting("barLayout", {}))
    readonly property var items: ({
            launcher: launcherItem, workspaces: workspacesItem, windowTitle: windowTitleItem, clock: clockItem, media: mediaItem,
            tray: trayItem, recording: recordingItem, privacy: privacyItem, focus: focusItem, timer: timerItem, stayAwake: stayAwakeItem,
            keyboard: keyboardItem, vpn: vpnItem, wifi: wifiItem, audio: audioItem, battery: batteryItem, notifications: notificationsItem,
            control: controlItem
        })
    // The now-playing button while it exists, for the hover card.
    property Item mediaButton: null
    // Whether the Day hub is open; the clock, which is the Day pill, shows it selected.
    property bool dayOpen: false
    // The clock; null when the clock is not in the bar.
    property Item dayAnchor: null
    // Whether the pointer is on the Day pill.
    property bool dayHovered: false
    signal dayClicked()
    // A right-click: the quick-add row.
    signal dayPeekClicked()
    // Where the Day hub grows from, in this item's coordinates: the clock, or the middle of the bar without one.
    function dayRect() {
        if (!dayAnchor || !dayAnchor.visible)
            return Qt.rect(Math.round(width / 2) - 40, 3, 80, height - 6);
        const point = dayAnchor.mapToItem(bar, 0, 0);
        return Qt.rect(point.x, point.y, dayAnchor.width, dayAnchor.height);
    }
    property bool mediaHovered: false
    readonly property var monitor: Services.workspaces.find(w => w.monitor && w.monitor.name === bar.outputName && w.active)
    function controlActive(detail) {
        return ShellState.panel === "control" && ShellState.detail === detail && ShellState.screenName === outputName;
    }
    function toggleControl(detail) {
        if (controlActive(detail)) {
            ShellState.close();
        } else {
            ShellState.open("control", bar.outputName);
            ShellState.detail = detail;
        }
    }
    SystemClock {
        id: clock
        precision: ShellState.setting("clockSeconds", false) ? SystemClock.Seconds : SystemClock.Minutes
    }
    // One quiet rail gives the independent controls a shared visual baseline.
    Rectangle {
        anchors.fill: parent
        radius: bar.edge ? 0 : Theme.radiusSmall + 2
        color: Theme.panel
    }
    // The three zones; each slot loads its item and hides while the item has nothing to show.
    Repeater {
        model: ["left", "center", "right"]
        RowLayout {
            id: zone
            required property string modelData
            anchors.verticalCenter: parent.verticalCenter
            x: modelData === "left" ? 5 : modelData === "center" ? Math.round((bar.width - width) / 2) : bar.width - width - 5
            height: parent.height
            spacing: modelData === "left" ? Theme.gapS : Theme.gapXs
            Repeater {
                model: bar.layout[zone.modelData]
                Loader {
                    required property string modelData
                    sourceComponent: bar.items[modelData] || null
                    visible: !!item && item.shown
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: item ? item.implicitWidth : 0
                    Layout.preferredHeight: item ? item.implicitHeight : 0
                }
            }
        }
    }
    Component {
        id: launcherItem
        BarButton {
            glyph: "grid"
            selected: ShellState.panel === "launcher" && ShellState.screenName === bar.outputName
            flat: true
            hint: "Applications"
            tooltip: bar.tooltip
            onClicked: ShellState.toggle("launcher", bar.outputName)
        }
    }
    Component {
        id: workspacesItem
        ListView {
            id: workspaceStrip
            readonly property bool shown: true
            readonly property bool dots: ShellState.setting("workspaceStyle", "numbers") === "dots"
            readonly property int slotWidth: dots ? 16 : 22
            // Empty workspaces 1…N shown as well, unless they belong to another screen.
            readonly property int slots: ShellState.setting("workspaceSlots", 0)
            implicitWidth: Math.min(Math.max(78, bar.width / 2 - 170), dots ? 200 : 238, workspaceModel.count * (slotWidth + spacing))
            implicitHeight: bar.height
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
                const entries = occupied.map(w => ({ workspaceId: w.id, workspaceName: w.name || String(w.id), urgent: !!w.urgent, empty: false }));
                if (!entries.some(w => w.workspaceId === activeId) && activeId > 0)
                    entries.push({ workspaceId: activeId, workspaceName: String(activeId), urgent: false, empty: false });
                for (let id = 1; id <= slots; ++id)
                    if (!entries.some(w => w.workspaceId === id) && !Services.workspaces.some(w => w.id === id && w.monitor && w.monitor.name !== bar.outputName))
                        entries.push({ workspaceId: id, workspaceName: String(id), urgent: false, empty: true });
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
            onSlotsChanged: syncWorkspaces()
            Component.onCompleted: syncWorkspaces()
            model: ListModel { id: workspaceModel }
            highlightMoveDuration: Theme.reduced ? 0 : 220
            highlightResizeDuration: 0
            highlight: Item {
                Rectangle {
                    visible: !workspaceStrip.dots
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
                required property bool empty
                readonly property bool current: workspaceStrip.activeId === workspaceId
                // The app whose window sits on this workspace, as a lamp in its mineral.
                readonly property string lampApp: {
                    const window = Services.windows.find(w => w.workspace && w.workspace.id === workspaceId);
                    return window ? (window.wayland ? window.wayland.appId || "" : (window.lastIpcObject || {}).class || "") : "";
                }
                readonly property color tint: current ? Theme.accentText : urgent ? Theme.warning : empty ? Theme.disabled : Theme.muted
                width: workspaceStrip.slotWidth
                height: workspaceStrip.height
                padding: 0
                flat: true
                hint: "Workspace " + workspaceName
                contentItem: Item {
                    C.Label {
                        visible: !workspaceStrip.dots
                        anchors.centerIn: parent
                        text: workspaceButton.workspaceName
                        horizontalAlignment: Text.AlignHCenter
                        color: workspaceButton.tint
                        font.pixelSize: Theme.barText - 1
                        font.family: Theme.mono
                    }
                    Rectangle {
                        visible: workspaceStrip.dots
                        anchors.centerIn: parent
                        width: workspaceButton.current ? 14 : 6
                        height: 6
                        radius: 3
                        color: workspaceButton.tint
                        Behavior on width { NumberAnimation { duration: Theme.reduced ? 0 : Theme.fast; easing.type: Easing.OutCubic } }
                    }
                    Rectangle {
                        visible: workspaceButton.lampApp !== ""
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        width: 4
                        height: 4
                        radius: 2
                        color: Theme.mineral(workspaceButton.lampApp)
                    }
                }
                background: Rectangle {
                    anchors.centerIn: parent
                    width: workspaceStrip.slotWidth
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
    }
    Component {
        id: windowTitleItem
        RowLayout {
            readonly property bool shown: bar.width > 1400
            spacing: Theme.gapS
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 12
                color: Theme.hover
            }
            BarButton {
                Layout.preferredWidth: 150
                clip: true
                flat: true
                hint: Services.activeWindow ? Services.activeWindow.title : "Workspace overview"
                contentItem: C.Label {
                    text: Services.activeWindow ? Services.activeWindow.title : "Shale"
                    color: Theme.muted
                    font.pixelSize: Theme.barText
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignLeft
                }
                onClicked: ShellState.toggle("overview", bar.outputName)
            }
        }
    }
    Component {
        id: clockItem
        BarButton {
            id: clockButton
            readonly property string format: {
                const time = ShellState.setting("clock24h", true) ? (ShellState.setting("clockSeconds", false) ? "HH:mm:ss" : "HH:mm")
                    : (ShellState.setting("clockSeconds", false) ? "h:mm:ss AP" : "h:mm AP");
                const style = ShellState.setting("clockFormat", "day-time");
                return style === "time" ? time : style === "date-time" ? "ddd d MMM   " + time : "ddd   " + time;
            }
            // Measure before laying out: an eliding Text can report a constrained
            // implicit width when it is used directly as a button content item.
            implicitWidth: Math.ceil(clockMetrics.advanceWidth) + 28 + 16
            implicitHeight: 28
            TextMetrics {
                id: clockMetrics
                text: clockButton.text
                font.family: Theme.instrument
                font.pixelSize: Theme.barText
                font.letterSpacing: 0.8
            }
            flat: true
            // A recessed instrument plate with a lit top edge and its two screws, instead of a bare button.
            background: Rectangle {
                radius: 7
                color: clockButton.down || clockButton.selected ? Theme.selection : clockButton.hovered ? Theme.hover : Qt.rgba(0, 0, 0, 0.28)
                border.width: 1
                border.color: clockButton.selected ? Theme.accent : Theme.border
                Behavior on color {
                    ColorAnimation { duration: Theme.fast }
                }
                Rectangle {
                    x: 8
                    y: 1
                    width: parent.width - 16
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.07)
                }
                Repeater {
                    model: 2
                    Rectangle {
                        required property int index
                        x: index ? parent.width - 6 : 3
                        y: 3
                        width: 3
                        height: 3
                        radius: 1.5
                        color: Theme.raised
                    }
                }
            }
            selected: bar.dayOpen
            readonly property real nowMs: clock.date.getTime()
            // Reminders still to come, soonest first; the next one may be on a later day. Scrolling over the capsule
            // moves the countdown along them, three at most.
            readonly property var upcoming: {
                const list = Day.items.filter(item => item.kind === "reminder" && !item.doneAt && item.at > clockButton.nowMs);
                if (Day.nextItem && Day.nextItem.at > clockButton.nowMs && !list.some(item => item.id === Day.nextItem.id))
                    list.push(Day.nextItem);
                return list.sort((a, b) => a.at - b.at).slice(0, 3);
            }
            property int eventIndex: 0
            readonly property var shownEvent: upcoming.length ? upcoming[Math.min(eventIndex, upcoming.length - 1)] : null
            // Something due within the hour rides along as a countdown.
            readonly property real eventIn: shownEvent ? shownEvent.at - nowMs : -1
            readonly property string soon: {
                if (eventIn < 0 || eventIn > 3600000 || !ShellState.setting("capsuleCountdown", true))
                    return "";
                const text = shownEvent.text.length > 24 ? shownEvent.text.slice(0, 23) + "…" : shownEvent.text;
                return Station.countdown(shownEvent.at, nowMs) + " " + text;
            }
            readonly property bool quiet: Focus.active
            Accessible.name: (quiet ? "Focus, " + Focus.clockText(Focus.remainingSeconds) + " left, " : "") + (arrived ? "Reminder arrived, " : soon ? "Next reminder, " : "") + "Day hub"
            // An event that arrived stays on the capsule until it is snoozed, cleared or dismissed; the newest shows.
            readonly property var arrived: Day.arrived.length ? Day.arrived[Day.arrived.length - 1] : null
            readonly property string arrivedText: arrived ? "▲ " + (arrived.text.length > 24 ? arrived.text.slice(0, 23) + "…" : arrived.text) : ""
            text: Qt.formatDateTime(clock.date, format) + (quiet ? "  ·  " + Station.word("quiet", ShellState.setting("stationWords", true)) + " " + Focus.clockText(Focus.remainingSeconds) + (Focus.orderText ? " " + (Focus.orderText.length > 22 ? Focus.orderText.slice(0, 21) + "…" : Focus.orderText) : "") : arrived ? "  ·  " + arrivedText : soon ? "  ·  " + soon : "")
            // Open to-dos due today, as a small count on the pill; amber with a mark when one is already late.
            readonly property int dueToday: Day.todos.filter(item => item.dueAt && new Date(item.dueAt).toDateString() === clock.date.toDateString()).length
            readonly property int overdue: Day.todos.filter(item => item.dueAt && item.dueAt < clockButton.nowMs).length
            readonly property bool recording: ShellState.setting("activityTracking", "ask") === "on"
            readonly property string openText: Day.todos.length + " open to-do" + (Day.todos.length === 1 ? "" : "s")
            Component.onCompleted: bar.dayAnchor = clockButton
            // Today's Line runs along the bottom of the pill.
            StrataLine {
                id: todayLine
                x: 0
                y: parent.height - height - 1
                width: parent.width
                onScreen: bar.onScreen
                open: bar.dayOpen
            }
            TargetMeter {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 2
            }
            onHoveredChanged: bar.dayHovered = hovered
            onUpcomingChanged: eventIndex = Math.min(eventIndex, Math.max(0, upcoming.length - 1))
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: bar.dayPeekClicked()
            }
            // Quiet starts or ends on a middle click.
            TapHandler {
                acceptedButtons: Qt.MiddleButton
                onTapped: Focus.active ? Focus.end(true) : Focus.start(25)
            }
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    if (clockButton.upcoming.length > 1)
                        clockButton.eventIndex = (clockButton.eventIndex + (event.angleDelta.y < 0 ? 1 : clockButton.upcoming.length - 1)) % clockButton.upcoming.length;
                }
            }
            Rectangle {
                visible: ShellState.setting("capsuleCount", true) && (clockButton.dueToday > 0 || clockButton.overdue > 0)
                anchors.right: parent.right
                anchors.top: parent.top
                width: Math.max(14, dueLabel.implicitWidth + 6)
                height: 14
                radius: 7
                color: clockButton.overdue > 0 ? Theme.warning : Theme.accent
                C.Label {
                    id: dueLabel
                    anchors.centerIn: parent
                    text: String(clockButton.dueToday) + (clockButton.overdue > 0 ? "!" : "")
                    color: Theme.background
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                }
            }
            Component.onDestruction: if (bar.dayAnchor === clockButton) bar.dayAnchor = null
            // One shake when an event arrives, unless Quiet holds it.
            Connections {
                target: Day
                function onArrival(item) {
                    if (!Theme.reduced && !Theme.lowPower && (!Focus.active || item.breaksQuiet))
                        shake.restart();
                }
            }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: shakeShift; property: "x"; to: 3; duration: 50 }
                NumberAnimation { target: shakeShift; property: "x"; to: -3; duration: 75 }
                NumberAnimation { target: shakeShift; property: "x"; to: 2; duration: 75 }
                NumberAnimation { target: shakeShift; property: "x"; to: 0; duration: 100; easing.type: Easing.OutCubic }
            }
            contentItem: Row {
                spacing: 8
                transform: Translate { id: shakeShift }
                // The recording lamp is lit while Activity records; with an event inside the hour it turns to the
                // event's colour and breathes in the last five minutes, and stays lit in it once the event arrived.
                // Quiet puts it out: nothing gets through.
                C.Lamp {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 7
                    lit: !clockButton.quiet && (clockButton.recording || !!clockButton.soon || !!clockButton.arrived)
                    color: clockButton.soon || clockButton.arrived ? Theme.accent2 : Theme.accent
                    breathing: !clockButton.arrived && clockButton.eventIn >= 0 && clockButton.eventIn <= 300000
                }
                C.Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: clockButton.text
                    font.family: Theme.instrument
                    font.pixelSize: Theme.barText
                    font.letterSpacing: 0.8
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideNone
                }
            }
            // The hover card: the next three events and what is open.
            hint: Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy")
                + (Day.arrived.length ? "\n" + Day.arrived.map(item => "Arrived  " + item.text).join("\n") : "")
                + (clockButton.upcoming.length ? "\n" + clockButton.upcoming.map(item => Station.countdown(item.at, clockButton.nowMs) + "  " + item.text).join("\n") : "")
                + (clockButton.recording && todayLine.activity ? "\nRecorded " + Station.duration(todayLine.recorded) : "")
                + "\n" + clockButton.openText + (clockButton.overdue ? ", " + clockButton.overdue + " late" : "")
                + "\nClick for your day · Middle-click for Quiet" + (clockButton.upcoming.length > 1 ? " · Scroll for the next event" : "")
            tooltip: bar.tooltip
            onClicked: bar.dayClicked()
        }
    }
    Component {
        id: mediaItem
        BarButton {
            id: mediaButton
            // Narrow bars keep the cover and visualizer but drop the title.
            readonly property bool wide: bar.width > 1600
            readonly property var player: NowPlaying.player
            shown: !!player && bar.width > 1100 && ShellState.setting("barMedia", true)
            flat: true
            leftPadding: 6
            rightPadding: wide ? 10 : 8
            implicitWidth: Math.min(Math.max(28, contentItem.implicitWidth + leftPadding + rightPadding), wide ? 210 : 60)
            hint: "Media controls"
            Accessible.name: player ? "Now playing: " + (player.trackTitle || player.identity) : "Media controls"
            selected: bar.controlActive("media")
            onClicked: bar.toggleControl("media")
            Component.onCompleted: bar.mediaButton = mediaButton
            Component.onDestruction: if (bar.mediaButton === mediaButton) {
                bar.mediaButton = null;
                bar.mediaHovered = false;
            }
            HoverHandler {
                onHoveredChanged: bar.mediaHovered = hovered
            }
            contentItem: RowLayout {
                spacing: Theme.gapS
                C.CoverArt {
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                    radius: 5
                    glyphSize: 11
                    source: NowPlaying.artFile
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
                    active: bar.onScreen && mediaButton.visible && NowPlaying.playing && ShellState.setting("visualizer", true) && !Theme.reduced && !Theme.lowPower
                }
            }
        }
    }
    Component {
        id: trayItem
        RowLayout {
            id: tray
            // How many apps get their own icon; the rest open from the tray page. Narrow bars show none.
            readonly property int count: {
                const chosen = ShellState.setting("trayIcons", -1);
                return bar.width <= 1100 ? 0 : chosen >= 0 ? chosen : bar.width > 1700 ? 3 : 2;
            }
            readonly property bool shown: Services.trayItems.length > 0
            spacing: Theme.gapXs
            Repeater {
                model: Services.trayItems.slice(0, tray.count)
                BarButton {
                    id: trayButton
                    required property var modelData
                    flat: true
                    hint: modelData.tooltipTitle || modelData.title || modelData.id
                    tooltip: bar.tooltip
                    contentItem: Image {
                        source: trayButton.modelData.icon
                        sourceSize.width: 18
                        sourceSize.height: 18
                        fillMode: Image.PreserveAspectFit
                    }
                    implicitWidth: 26
                    selected: !!bar.trayMenu && bar.trayMenu.shown && bar.trayMenu.item === modelData
                    onClicked: modelData.onlyMenu ? bar.trayMenu.toggle(modelData, bar.window, trayButton) : modelData.activate()
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: {
                            bar.tooltip.hide(trayButton, true);
                            bar.trayMenu.toggle(trayButton.modelData, bar.window, trayButton);
                        }
                    }
                    TapHandler {
                        acceptedButtons: Qt.MiddleButton
                        onTapped: {
                            bar.tooltip.hide(trayButton, true);
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
                visible: Services.trayItems.length > tray.count
                glyph: "grid"
                flat: true
                hint: "System tray"
                tooltip: bar.tooltip
                selected: bar.controlActive("tray")
                onClicked: bar.toggleControl("tray")
            }
        }
    }
    Component {
        id: recordingItem
        BarButton {
            shown: ShellState.recording.active
            accent: true
            glyph: "record"
            text: "REC " + Math.floor(ShellState.recordingSeconds / 60) + ":" + String(ShellState.recordingSeconds % 60).padStart(2, "0")
            flat: true
            hint: "Stop recording"
            tooltip: bar.tooltip
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
    }
    Component {
        id: privacyItem
        BarButton {
            id: privacyButton
            readonly property bool mic: Services.micUsers.length > 0
            readonly property bool sharing: Services.screenSharers.length > 0
            shown: mic || sharing
            accent: true
            flat: true
            hint: [mic ? "Microphone in use: " + Services.micUsers.join(", ") : "",
                   sharing ? "Sharing your screen with " + Services.screenSharers.join(", ") : ""].filter(line => line).join("\n")
            tooltip: bar.tooltip
            contentItem: Row {
                spacing: Theme.gapXs
                C.Icon { visible: privacyButton.mic; name: "mic"; size: 16; color: Theme.background; anchors.verticalCenter: parent.verticalCenter }
                C.Icon { visible: privacyButton.sharing; name: "cast"; size: 16; color: Theme.background; anchors.verticalCenter: parent.verticalCenter }
            }
            onClicked: bar.toggleControl("audio")
        }
    }
    Component {
        id: focusItem
        BarButton {
            id: focusButton
            shown: Focus.active
            accent: true
            flat: true
            readonly property string remaining: Focus.remainingSeconds < 60 ? Focus.remainingSeconds + "s" : Focus.minutesText(Focus.remainingSeconds)
            hint: "Focus · " + remaining + " left\nClick to end · Scroll to add or take 5 min"
            tooltip: bar.tooltip
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
    }
    Component {
        id: timerItem
        BarButton {
            id: timerButton
            readonly property var timer: Focus.nextTimer
            readonly property int remaining: timer ? Math.max(0, Math.ceil((timer.endsAt - Focus.now) / 1000)) : 0
            shown: !!timer
            flat: true
            hint: Focus.timers.map(t => (t.label || Focus.minutesText(t.seconds) + " timer") + " · " + Focus.clockText(Math.max(0, Math.ceil((t.endsAt - Focus.now) / 1000)))).join("\n") + "\nClick to cancel the first"
            tooltip: bar.tooltip
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
    }
    Component {
        id: stayAwakeItem
        BarButton {
            shown: ShellState.presentation
            glyph: "moon"
            flat: true
            hint: "Stay awake is on"
            tooltip: bar.tooltip
            onClicked: ShellState.presentation = false
        }
    }
    Component {
        id: keyboardItem
        BarButton {
            readonly property var layouts: ShellState.keyboard.layouts || []
            readonly property var current: layouts[ShellState.keyboard.index] || null
            shown: layouts.length > 1
            flat: true
            text: current ? current.code.toUpperCase().slice(0, 3) : ""
            hint: (ShellState.keyboard.name || "Keyboard layout") + "\n" + layouts.map((l, i) => (i === ShellState.keyboard.index ? "● " : "○ ") + l.code + (l.variant ? " (" + l.variant + ")" : "")).join("\n") + "\nClick for the next layout"
            tooltip: bar.tooltip
            Accessible.name: "Keyboard layout, " + (ShellState.keyboard.name || text)
            onClicked: ShellState.nextKeyboardLayout()
        }
    }
    Component {
        id: vpnItem
        BarButton {
            shown: !!ShellState.activeVpn
            glyph: "shield"
            flat: true
            hint: ShellState.activeVpn ? "VPN · " + ShellState.activeVpn.name : ""
            tooltip: bar.tooltip
            selected: bar.controlActive("wifi")
            onClicked: bar.toggleControl("wifi")
        }
    }
    Component {
        id: wifiItem
        BarButton {
            shown: bar.width >= 560 && ShellState.wifiAvailable
            glyph: "wifi"
            flat: true
            // Dimmed while disconnected so a dropped network is visible at a glance.
            opacity: ShellState.wifi.state === "connected" || bar.controlActive("wifi") ? 1 : 0.45
            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
            hint: {
                const network = (ShellState.wifi.networks || []).find(n => n.connected);
                return ShellState.wifi.state === "connected" ? "Wi-Fi" + (network ? " · " + network.name : "") : ShellState.wifi.powered ? "Wi-Fi · Not connected" : "Wi-Fi · Off";
            }
            tooltip: bar.tooltip
            selected: bar.controlActive("wifi")
            onClicked: bar.toggleControl("wifi")
        }
    }
    Component {
        id: audioItem
        BarButton {
            glyph: Services.muted ? "mute" : "volume"
            selected: bar.controlActive("audio")
            flat: true
            hint: "Audio · " + Math.round(Services.volume * 100) + "%"
            tooltip: bar.tooltip
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
    }
    Component {
        id: batteryItem
        BarButton {
            readonly property bool low: !Services.batteryCharging && Services.onBattery && Services.batteryPercent <= 20
            // Low charge always shows its number, even when the percentage is turned off.
            readonly property bool percent: {
                const choice = ShellState.setting("batteryPercent", "auto");
                return low || choice === "always" || (choice === "auto" && !bar.compact);
            }
            shown: Services.batteryAvailable
            implicitWidth: percent ? 76 : 36
            glyph: Services.batteryCharging ? "bolt" : "battery"
            text: percent ? Math.round(Services.batteryPercent) + "%" : ""
            tone: !low ? "" : Services.batteryPercent <= 10 ? "danger" : "warning"
            flat: true
            hint: "Battery " + Math.round(Services.batteryPercent) + "% · Power profiles"
            tooltip: bar.tooltip
            Accessible.name: "Battery " + Math.round(Services.batteryPercent) + "%" + (Services.batteryCharging ? ", charging" : "")
            selected: bar.controlActive("power")
            onClicked: bar.toggleControl("power")
        }
    }
    Component {
        id: notificationsItem
        BarButton {
            // Do not disturb swaps the bell so suppressed popups are never a surprise.
            glyph: ShellState.setting("dnd", false) ? "bell-off" : "bell"
            implicitWidth: bar.compact ? 36 : 58
            selected: ShellState.panel === "notifications" && ShellState.screenName === bar.outputName
            flat: true
            text: !bar.compact && Services.notifications.length ? (Services.notifications.length > 99 ? "99+" : String(Services.notifications.length)) : ""
            hint: "Notifications"
            tooltip: bar.tooltip
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
            onClicked: ShellState.toggle("notifications", bar.outputName)
        }
    }
    Component {
        id: controlItem
        BarButton {
            glyph: "settings"
            selected: bar.controlActive("")
            implicitHeight: 26
            flat: false
            hint: Updates.available ? "Control center · Update available" : "Control center"
            tooltip: bar.tooltip
            Accessible.name: hint
            onClicked: bar.toggleControl("")
            // A newer Shale is waiting; the control center's first row says what it changes.
            Rectangle {
                visible: Updates.available
                anchors.right: parent.right
                anchors.rightMargin: 3
                anchors.top: parent.top
                anchors.topMargin: 3
                width: 6
                height: 6
                radius: 3
                color: Theme.accent
            }
        }
    }
}
