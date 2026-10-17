import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../core"
import "../components" as C

PanelWindow {
    id: bar
    required property string outputName
    readonly property bool edge: ShellState.setting("barStyle", "floating") === "edge"
    IpcHandler {
        target: "bar-" + bar.outputName
        function status(): string {
            return JSON.stringify({control: content.controlActive(""), wifi: content.controlActive("wifi"), audio: content.controlActive("audio"), power: content.controlActive("power"), media: content.controlActive("media"), tray: content.controlActive("tray")});
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
    implicitHeight: 32
    color: "transparent"
    WlrLayershell.namespace: "shale-bar"
    WlrLayershell.layer: WlrLayer.Top
    exclusionMode: ExclusionMode.Auto
    // Stays mapped under the lock screen: unmapping would hand its space to the windows, and they would all
    // shrink back into place as the session unlocks.
    visible: !(ShellState.setting("hideFullscreen", true) && content.monitor && content.monitor.hasFullscreen) && ShellState.setting("hiddenOutputs", []).indexOf(bar.outputName) < 0
    BarContent {
        id: content
        anchors.fill: parent
        outputName: bar.outputName
        window: bar
        tooltip: barTooltip
        trayMenu: trayMenu
        onScreen: bar.visible && !ShellState.locked
        opacity: bar.arrival
        transform: Translate { y: -(1 - bar.arrival) * 14 }
    }
    // Hidden while locked; after an unlock it drops in just behind the desktop's reveal.
    property real arrival: 1
    Component.onCompleted: arrival = ShellState.locked ? 0 : 1
    Connections {
        target: ShellState
        function onLockedChanged() {
            arrive.stop();
            bar.arrival = 0;
            if (!ShellState.locked)
                arrive.restart();
        }
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
