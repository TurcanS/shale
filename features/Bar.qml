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
            bar.toggleDay(false);
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
    implicitHeight: hub.fullHeight + hub.shadowRoom
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
    // Exclusive only until the focus grab holds the keyboard: Hyprland ignores clicks on windows while a layer keeps
    // exclusive focus, so the grab would never see the click outside that closes the hub.
    WlrLayershell.keyboardFocus: !bar.dayOpen ? WlrKeyboardFocus.None : bar.dayGrab ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive
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
        onDayClicked: bar.toggleDay(false)
        onDayPeekClicked: bar.toggleDay(true)
        transform: Translate { y: -(1 - bar.arrival) * 14 }
    }
    // The Day hub. One number drives it; a click mid-way reverses from where it is.
    property bool dayOpen: false
    property real dayProgress: 0
    // `peek` opens only the quick-add row (a right-click on the pill).
    function toggleDay(peek) {
        if (dayOpen) {
            closeDay();
            return;
        }
        if (ShellState.locked || !bar.visible)
            return;
        // Only one overlay at a time: an open panel gives way to the hub.
        ShellState.close();
        hub.pill = pillRect();
        hub.peek = peek === true;
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
        hub.pill = pillRect();
        dayMotion.duration = Theme.leave;
        dayMotion.to = 0;
        dayMotion.restart();
    }
    // Taken as the hub opens and closes, not bound: the clock moves inside its zone's layout as its text changes.
    function pillRect() {
        const rect = content.dayRect();
        return Qt.rect(content.x + rect.x, content.y + rect.y, rect.width, rect.height);
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
    // Hyprland drops a grab that starts before the bar can take the keyboard, so it is armed a moment after opening.
    property bool dayGrab: false
    Timer {
        id: dayGrabArm
        interval: 100
        onTriggered: bar.dayGrab = bar.dayOpen
    }
    onDayOpenChanged: {
        dayGrab = false;
        if (dayOpen)
            dayGrabArm.restart();
    }
    HyprlandFocusGrab {
        windows: [bar]
        active: bar.dayGrab
        onCleared: bar.closeDay()
    }
    DayHub {
        id: hub
        anchors.fill: parent
        progress: bar.dayProgress
        opening: bar.dayOpen
        edge: bar.edge
        onDismissed: bar.closeDay()
        onPillClicked: bar.toggleDay(false)
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
