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
    // Lively and Playful: the menu folds out like a paper one. Each row unfolds on its hinge under the one above,
    // and the case grows behind them; closing folds them back up quickly. Calm keeps the short drop and fade.
    readonly property bool folding: !Motion.calm
    readonly property int foldGap: Motion.ms(40 + Motion.stagger * 0.8)
    readonly property int foldSpan: Motion.ms(260)
    readonly property int foldTotal: foldGap * Math.max(0, list.rows.length - 1) + foldSpan
    property real foldAt: 100000
    NumberAnimation {
        id: unfold
        target: root
        property: "foldAt"
        duration: root.foldTotal
        // Fully out: a submenu with more rows than this one shows whole.
        onFinished: if (root.shown) root.foldAt = 100000
    }
    function foldTo(open) {
        unfold.stop();
        unfold.from = open ? 0 : Math.min(foldAt, foldTotal);
        unfold.to = open ? foldTotal : 0;
        unfold.duration = open ? foldTotal : Motion.ms(160);
        unfold.start();
    }
    function open(trayItem, window, anchorItem) {
        item = trayItem;
        stack = [];
        anchor.window = window;
        anchor.item = anchorItem;
        anchor.rect.width = anchorItem.width;
        anchor.rect.height = anchorItem.height + 6;
        shown = true;
        if (folding)
            foldTo(true);
        list.forceActiveFocus();
        focusTimer.restart();
    }
    function close() {
        if (shown && folding)
            foldTo(false);
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
    // No taller than the screen below the bar allows; the list scrolls past that.
    implicitHeight: Math.min(list.implicitHeight + 12, Math.max(200, (anchor.window && anchor.window.screen ? anchor.window.screen.height : 1080) - ShellState.barBottom - 24))
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
    // A small case: the panel colour with its hairline edge.
    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Theme.caseColor
        border.width: 1
        border.color: Theme.hairline
        // Folding, the case grows down behind the rows as they unfold.
        anchors.bottomMargin: root.folding ? (1 - Motion.out(Motion.clamp(root.foldAt / Math.max(1, root.foldTotal - root.foldSpan * 0.5), 0, 1))) * Math.max(0, root.height - 44) : 0
        opacity: root.folding ? Math.min(1, root.reveal * 3) : root.reveal
        transform: Translate { y: Theme.reduced || root.folding ? 0 : (1 - root.reveal) * -6 }
        TrayMenuList {
            id: list
            anchors.fill: parent
            anchors.margins: 6
            focus: true
            foldActive: root.folding
            foldAt: root.foldAt
            foldGap: root.foldGap
            foldSpan: root.foldSpan
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
