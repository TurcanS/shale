import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import "../core"
import "../components" as C

PanelWindow {
    id: bar
    required property string outputName
    readonly property bool edge: ShellState.setting("barStyle", "floating") === "edge"
    IpcHandler {
        target: "bar-" + bar.outputName
        function status(): string {
            return JSON.stringify({day: bar.dayOpen, dayProgress: bar.dayProgress, control: content.controlActive(""), wifi: content.controlActive("wifi"), audio: content.controlActive("audio"), power: content.controlActive("power"), media: content.controlActive("media"), tray: content.controlActive("tray")});
        }
    }
    IpcHandler {
        target: "day-" + bar.outputName
        function toggle(): void {
            bar.toggleDay();
        }
    }
    anchors {
        top: true
        left: true
        right: true
    }
    margins {
        top: bar.edge ? 0 : 5
        left: bar.edge ? 0 : 8
        right: bar.edge ? 0 : 8
    }
    // Tall enough for the open Day hub, but transparent and click-through outside the visible shapes; the space kept
    // from windows stays the bar's own 32 px, so opening the hub never moves a window.
    implicitHeight: hub.openHeight
    color: "transparent"
    mask: Region {
        item: content
        Region {
            item: hub.shape
        }
    }
    WlrLayershell.namespace: "shale-bar"
    WlrLayershell.layer: WlrLayer.Top
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 32
    WlrLayershell.keyboardFocus: bar.dayOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // Stays mapped under the lock screen: unmapping would hand its space to the windows, and they would all
    // shrink back into place as the session unlocks.
    visible: !(ShellState.setting("hideFullscreen", true) && content.monitor && content.monitor.hasFullscreen) && ShellState.setting("hiddenOutputs", []).indexOf(bar.outputName) < 0
    BarContent {
        id: content
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: 32
        outputName: bar.outputName
        window: bar
        tooltip: barTooltip
        trayMenu: trayMenu
        onScreen: bar.visible && !ShellState.locked
        // The rest of the bar steps back a little while the hub opens.
        opacity: bar.arrival * (1 - 0.25 * Math.min(1, bar.dayProgress / 0.3))
        dayOpen: bar.dayOpen
        onDayClicked: bar.toggleDay()
        transform: Translate { y: -(1 - bar.arrival) * 14 }
    }
    // Placeholder Day hub (morph spike). One number drives it; a click mid-way reverses from where it is.
    property bool dayOpen: false
    property real dayProgress: 0
    function toggleDay() {
        if (dayOpen) {
            closeDay();
            return;
        }
        if (ShellState.locked || !bar.visible)
            return;
        // Only one overlay at a time: an open panel gives way to the hub.
        ShellState.close();
        dayOpen = true;
        dayMotion.duration = Theme.reduced ? 0 : Theme.lowPower ? 200 : 420;
        dayMotion.to = 1;
        dayMotion.restart();
        hub.focusCapture();
    }
    function closeDay() {
        if (!dayOpen)
            return;
        dayOpen = false;
        dayMotion.duration = Theme.leave;
        dayMotion.to = 0;
        dayMotion.restart();
    }
    // Locking or hiding the bar must not leave a half-open hub behind, so it snaps shut.
    function dropDay() {
        dayMotion.stop();
        dayOpen = false;
        dayProgress = 0;
    }
    onVisibleChanged: if (!visible) dropDay()
    NumberAnimation {
        id: dayMotion
        target: bar
        property: "dayProgress"
    }
    HyprlandFocusGrab {
        windows: [bar]
        active: bar.dayOpen
        onCleared: bar.closeDay()
    }
    DayHub {
        id: hub
        anchors.fill: parent
        progress: bar.dayProgress
        opening: bar.dayOpen
        edge: bar.edge
        pill: Qt.rect(content.x + content.dayPill.x, content.y + content.dayPill.y, content.dayPill.width, content.dayPill.height)
        onDismissed: bar.closeDay()
    }
    // Lifts away as the desktop folds into the lock screen, and drops back in just behind the reveal after an unlock.
    property real arrival: 1
    Component.onCompleted: arrival = ShellState.locked ? 0 : 1
    Connections {
        target: ShellState
        function onPanelChanged() {
            if (ShellState.panel !== "")
                bar.closeDay();
        }
        function onLockedChanged() {
            if (ShellState.locked)
                bar.dropDay();
            arrive.stop();
            leave.stop();
            if (ShellState.locked) {
                leave.restart();
            } else {
                bar.arrival = 0;
                arrive.restart();
            }
        }
    }
    NumberAnimation {
        id: leave
        target: bar
        property: "arrival"
        to: 0
        duration: Theme.reduced ? 0 : Theme.lowPower ? 140 : 240
        easing.type: Easing.InCubic
    }
    SequentialAnimation {
        id: arrive
        PauseAnimation { duration: Theme.reduced ? 0 : 180 }
        NumberAnimation {
            target: bar
            property: "arrival"
            to: 1
            duration: Theme.reduced ? 0 : Theme.lowPower ? 200 : 420
            easing.type: Easing.OutCubic
        }
    }
    TrayMenu {
        id: trayMenu
    }
    C.Tooltip {
        id: barTooltip
        anchor.window: bar
    }
    Item {
        id: mediaFallback
        width: 1
        height: 1
    }
    MediaHoverCard {
        bar: bar
        button: content.mediaButton || mediaFallback
        buttonHovered: content.mediaHovered && !!content.mediaButton && content.mediaButton.visible && bar.visible
    }
}
