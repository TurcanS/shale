import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import "../core"
import "../core/barItems.js" as BarItems
import "../services"

// The bar's items in their zones. Bar.qml puts it in a layer-shell window; previews put it in a plain one.
Item {
    id: bar
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
            workspaces: workspacesItem, windowTitle: windowTitleItem, clock: clockItem, media: mediaItem,
            tray: trayItem, recording: recordingItem, privacy: privacyItem, focus: focusItem, timer: timerItem, stayAwake: stayAwakeItem, airdrop: airdropItem,
            keyboard: keyboardItem, vpn: vpnItem, wifi: wifiItem, audio: audioItem, battery: batteryItem, notifications: notificationsItem,
            control: controlItem
        })
    // The now-playing button while it exists, for the hover card.
    property Item mediaButton: null
    property bool mediaHovered: false
    readonly property var monitor: Services.workspaces.find(w => w.monitor && w.monitor.name === bar.outputName && w.active)
    // Apps reading a camera through PipeWire: a video source with a device behind it (screen casts have none).
    readonly property var cameraUsers: Services.captureApps(Services.captureLinks.filter(g => (g.source.type & PwNodeType.Video) && g.source.ready && !!g.source.properties["device.api"]))
    // Empty pages: a step above the key colour, so they read as slots rather than as pages.
    readonly property color emptyPage: Theme.mix(Theme.key, Theme.textFaint, 0.25)
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
    // Coming on, after start-up and after an unlock: the items light one after another from left to right, like the
    // LEDs on a rack unit warming up, and the page pill runs across the pages (bootStarted). sweep is how far the
    // light has got across the bar; Calm skips it.
    property real sweep: Motion.calm ? 2 : 0
    signal bootStarted()
    function boot() {
        if (Motion.calm) {
            sweep = 2;
            return;
        }
        sweeping.restart();
        bootStarted();
    }
    NumberAnimation {
        id: sweeping
        target: bar
        property: "sweep"
        from: 0
        to: 1.3
        duration: Motion.ms(760)
        onFinished: bar.sweep = 2
    }
    Timer {
        id: bootDelay
        // Just as the bar lands (Bar.qml drops it in after an unlock).
        interval: 320
        onTriggered: bar.boot()
    }
    // Items that come and go slide out from beside their neighbour, but not while the bar first fills in.
    property bool settledIn: false
    Timer {
        interval: 1500
        running: true
        onTriggered: bar.settledIn = true
    }
    Component.onCompleted: bootDelay.start()
    Connections {
        target: ShellState
        function onLockedChanged() {
            if (!ShellState.locked && !Motion.calm) {
                bar.sweep = 0;
                bootDelay.restart();
            }
        }
    }
    // This page, for its items: in their own bindings `bar` names their own property.
    readonly property Item content: bar
    // The time every item on this bar shows.
    readonly property date now: clock.date
    SystemClock {
        id: clock
        precision: ShellState.setting("clockSeconds", false) ? SystemClock.Seconds : SystemClock.Minutes
    }
    // Today's weather beside the clock, from the forecast Clock and sky shows (the backend keeps it for 30 minutes).
    // Nothing is requested until a city is chosen there.
    readonly property var weather: Weather.forecast
    // The case: floating, it is a rounded strip with a hairline edge; edge to edge, a hairline under it.
    Rectangle {
        anchors.fill: parent
        radius: bar.edge ? 0 : 12
        color: Theme.caseColor
        border.width: bar.edge ? 0 : 1
        border.color: Theme.hairline
        Rectangle {
            visible: bar.edge
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.hairline
        }
    }
    // One zone; each slot loads its item and hides while the item has nothing to show. Status items next to each
    // other share one key.
    component Zone: RowLayout {
        id: zoneRow
        required property string name
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        spacing: 5
        Repeater {
            model: BarItems.runs(bar.layout[zoneRow.name])
            Loader {
                id: slot
                required property var modelData
                readonly property var run: modelData
                readonly property string zone: zoneRow.name
                sourceComponent: run.status ? statusKey : bar.items[run.ids[0]] || null
                // Coming and going: a slot opens out from beside its neighbour and seats; it goes at once.
                readonly property bool wanted: !!item && item.shown
                property real reveal: wanted ? 1 : 0
                onWantedChanged: {
                    opening.stop();
                    if (wanted && bar.settledIn && !Motion.calm) {
                        reveal = 0;
                        opening.start();
                    } else {
                        reveal = wanted ? 1 : 0;
                    }
                }
                NumberAnimation {
                    id: opening
                    target: slot
                    property: "reveal"
                    from: 0
                    to: 1
                    duration: Motion.ms(320)
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.seatCurve(Motion.ov(0.6))
                }
                // The start-up light reaching this slot.
                readonly property real lit: bar.sweep >= 1.3 || Motion.calm ? 1 : Motion.clamp((bar.sweep * bar.width - zoneRow.x - x) / 240, 0, 1)
                visible: reveal > 0.02
                clip: reveal < 0.999
                opacity: Math.min(1, reveal * 1.5) * lit
                transform: Translate {
                    y: slot.lit < 1 ? -3 * Motion.travel * (1 - Motion.seat(Motion.ov(1), slot.lit)) : 0
                }
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: item ? item.implicitWidth * Math.min(1, reveal) : 0
                Layout.preferredHeight: item ? item.implicitHeight : 0
            }
        }
    }
    Zone {
        id: leftZone
        name: "left"
        x: 5
    }
    Zone {
        id: rightZone
        name: "right"
        x: bar.width - width - 5
    }
    // Room between the side zones. The middle zone stays centred while it fits there, and moves aside rather than
    // run into a busy side; the clock drops the weather, then the date, when even that is too tight.
    readonly property real centerRoom: rightZone.x - leftZone.x - leftZone.width - 12
    Zone {
        name: "center"
        x: Math.round(Math.max(leftZone.x + leftZone.width + 5, Math.min((bar.width - width) / 2, rightZone.x - 6 - width)))
    }
    Component {
        id: statusKey
        Rectangle {
            id: status
            readonly property var ids: parent && parent.run ? parent.run.ids : []
            readonly property bool shown: parts.implicitWidth > 0
            implicitWidth: parts.implicitWidth + 12
            implicitHeight: 28
            radius: Theme.radiusKey
            color: Theme.module
            Row {
                id: parts
                x: 6
                height: parent.height
                Repeater {
                    model: status.ids
                    Loader {
                        required property string modelData
                        sourceComponent: bar.items[modelData] || null
                        visible: !!item && item.shown
                    }
                }
            }
        }
    }
    Component {
        id: workspacesItem
        BarWorkspaces {
            bar: content
        }
    }
    Component {
        id: windowTitleItem
        BarWindowTitle {
            bar: content
        }
    }
    Component {
        id: clockItem
        BarClock {
            bar: content
        }
    }
    Component {
        id: mediaItem
        BarMedia {
            bar: content
        }
    }
    Component {
        id: trayItem
        BarTray {
            bar: content
        }
    }
    Component {
        id: recordingItem
        BarRecording {
            bar: content
        }
    }
    Component {
        id: privacyItem
        BarPrivacy {
            bar: content
        }
    }
    Component {
        id: focusItem
        BarFocus {
            bar: content
        }
    }
    Component {
        id: timerItem
        BarTimer {
            bar: content
        }
    }
    Component {
        id: airdropItem
        BarAirDrop {
            bar: content
        }
    }
    Component {
        id: stayAwakeItem
        BarStayAwake {
            bar: content
        }
    }
    Component {
        id: keyboardItem
        BarKeyboard {
            bar: content
        }
    }
    Component {
        id: vpnItem
        BarVpn {
            bar: content
        }
    }
    Component {
        id: wifiItem
        BarWifi {
            bar: content
        }
    }
    Component {
        id: audioItem
        BarAudio {
            bar: content
        }
    }
    Component {
        id: batteryItem
        BarBattery {
            bar: content
        }
    }
    Component {
        id: controlItem
        BarControl {
            bar: content
        }
    }
    Component {
        id: notificationsItem
        BarNotifications {
            bar: content
        }
    }
}
