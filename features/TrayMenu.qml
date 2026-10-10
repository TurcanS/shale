import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../core"

// A tray app's menu in Shale's style, opened under the icon or row that asked for it. It lists the
// app's own entries (submenus open in place), plus Open and, unless the app has its own, Quit.
PopupWindow {
    id: root
    property var item: null
    // Submenus opened so far, innermost last.
    property var stack: []
    property bool shown: false
    property real reveal: shown ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.shown ? Theme.enter : Theme.leave
            easing.type: Easing.OutCubic
        }
    }
    function open(trayItem, window, anchorItem) {
        item = trayItem;
        stack = [];
        anchor.window = window;
        anchor.item = anchorItem;
        anchor.rect.width = anchorItem.width;
        anchor.rect.height = anchorItem.height + 6;
        shown = true;
        list.forceActiveFocus();
        focusTimer.restart();
    }
    function close() {
        shown = false;
    }
    function toggle(trayItem, window, anchorItem) {
        if (shown && item === trayItem)
            close();
        else
            open(trayItem, window, anchorItem);
    }
    readonly property string appName: item ? item.tooltipTitle || item.title || item.id : ""
    // The app quit or its icon went away.
    onItemChanged: if (!item) close()
    anchor.rect.x: 0
    anchor.rect.y: 0
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    implicitWidth: list.implicitWidth + 12
    implicitHeight: list.implicitHeight + 12
    visible: reveal > 0
    color: "transparent"
    QsMenuOpener {
        id: opener
        menu: root.stack.length ? root.stack[root.stack.length - 1] : root.item && root.item.hasMenu ? root.item.menu : null
    }
    // Clicking anywhere else closes the menu; the grab also gives it the keyboard.
    HyprlandFocusGrab {
        active: root.shown
        windows: [root]
        onCleared: root.close()
    }
    Connections {
        target: ShellState
        function onLockedChanged() {
            root.close();
        }
        function onPanelChanged() {
            root.close();
        }
    }
    // Rows exist only once the menu's entries have loaded.
    Timer {
        id: focusTimer
        interval: 60
        onTriggered: list.focusFirst()
    }
    Rectangle {
        anchors.fill: parent
        radius: Theme.controlRadius
        color: Theme.panel
        border.width: 1
        border.color: Theme.border
        opacity: root.reveal
        transform: Translate { y: Theme.reduced ? 0 : (1 - root.reveal) * -6 }
        TrayMenuList {
            id: list
            anchors.fill: parent
            anchors.margins: 6
            focus: true
            entries: opener.children ? opener.children.values : []
            appName: root.appName
            canOpen: !!root.item && !root.item.onlyMenu
            submenu: root.stack.length ? list.label(root.stack[root.stack.length - 1].text) : ""
            onOpenRequested: {
                root.item.activate();
                root.close();
            }
            onQuitRequested: {
                ShellState.run("tray.quit", {id: root.item.id, title: root.item.title || ""});
                root.close();
            }
            onEntryChosen: entry => {
                if (entry.hasChildren) {
                    root.stack = root.stack.concat([entry]);
                    focusTimer.restart();
                } else {
                    entry.triggered();
                    root.close();
                }
            }
            onBackRequested: {
                root.stack = root.stack.slice(0, -1);
                focusTimer.restart();
            }
            onCloseRequested: root.close()
        }
    }
}
