import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../core"

PanelWindow {
    id: host
    required property string outputName
    readonly property bool showing: ShellState.panel !== "" && ShellState.screenName === outputName && !ShellState.locked
    property string retainedPanel: "launcher"
    property real progress: showing ? 1 : 0
    IpcHandler {
        target: "surface-" + host.outputName
        function status(): string {
            return JSON.stringify({
                panel: content.panel,
                visible: host.visible,
                content: content.objectName
            });
        }
    }
    function synchronizePanel() {
        if (showing)
            retainedPanel = ShellState.panel;
    }
    Connections {
        target: ShellState
        function onPanelChanged() {
            host.synchronizePanel();
        }
        function onScreenNameChanged() {
            host.synchronizePanel();
        }
    }
    onShowingChanged: {
        synchronizePanel();
    }
    visible: progress > 0 || showing
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shale-panel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: showing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    Behavior on progress {
        NumberAnimation {
            duration: host.showing ? Theme.enter : Theme.leave
            easing.type: Easing.OutCubic
        }
    }
    MouseArea {
        anchors.fill: parent
        onClicked: ShellState.close()
    }
    PanelContent {
        id: content
        panel: host.retainedPanel
        width: Math.min(parent.width - 24, preferredWidth)
        height: Math.min(parent.height - 90, preferredHeight)
        x: ["control", "notifications"].indexOf(panel) >= 0 ? parent.width - width - 12 : (parent.width - width) / 2
        y: (["control", "notifications", "calendar"].indexOf(panel) >= 0 ? 46 : Math.max(48, (parent.height - height) * 0.38))
        transform: Translate {
            y: Theme.reduced ? 0 : (1 - host.progress) * -8
        }
        Behavior on width {
            enabled: !Theme.reduced && host.showing && host.progress > 0.99
            NumberAnimation {
                duration: Theme.enter
                easing.type: Easing.OutCubic
            }
        }
        Behavior on height {
            enabled: !Theme.reduced && host.showing && host.progress > 0.99
            NumberAnimation {
                duration: Theme.enter
                easing.type: Easing.OutCubic
            }
        }
        Behavior on x {
            enabled: !Theme.reduced && host.showing && host.progress > 0.99
            NumberAnimation {
                duration: Theme.enter
                easing.type: Easing.OutCubic
            }
        }
        Behavior on y {
            enabled: !Theme.reduced && host.showing && host.progress > 0.99
            NumberAnimation {
                duration: Theme.enter
                easing.type: Easing.OutCubic
            }
        }
        opacity: host.progress
        enabled: host.showing
        scale: 1
        visible: host.visible
        active: host.visible
    }
}
