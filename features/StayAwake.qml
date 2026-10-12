import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"

// Compositors honour idle inhibitors only on mapped surfaces, so this lives on its own
// click-through pixel instead of the bar, which hides for fullscreen apps and lock. There is one
// per output, so turning an output off (a closed lid while docked) never takes the inhibitor along.
// The pixel is mapped only while it inhibits: every mapped window holds a GL context and its threads.
PanelWindow {
    id: root
    visible: inhibitor.enabled
    anchors { top: true; left: true }
    implicitWidth: 1
    implicitHeight: 1
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shale-stay-awake"
    WlrLayershell.layer: WlrLayer.Background
    mask: Region {}
    IdleInhibitor {
        id: inhibitor
        enabled: ShellState.lidAwake || (ShellState.presentation && !ShellState.locked)
        window: root
    }
}
