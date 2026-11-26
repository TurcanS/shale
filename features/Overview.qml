import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import "../core"
import "../services"
import "../components" as C

// Pages: a 4-wide grid of small desktops (more rows when pages past 8 or a scratch page have windows), each with
// its windows where they sit on the screen. Click a window to pick it, then Move here on another page; matching
// windows stay bright while searching.
FocusScope {
    id: root
    readonly property string title: "Pages"
    readonly property bool showHeader: false
    readonly property int panelWidth: 1240
    readonly property int panelHeight: 580 + Math.max(0, Math.ceil(pages.length / 4) - 2) * 230
    // The picked window: Move here and the number keys send it to a page, Enter focuses it.
    property var moving: null
    property alias query: search.text
    readonly property string folded: query.trim().toLowerCase()
    readonly property var occupied: new Set(Services.windows.filter(w => w.workspace).map(w => w.workspace.id))
    readonly property int currentId: Services.focusedWorkspace ? Services.focusedWorkspace.id : 0
    // Pages 1–8 always; pages past 8 and scratch pages while they have windows (or are the current one).
    readonly property var pages: {
        const result = [];
        for (let i = 1; i <= 8; i++)
            result.push({id: i, name: "Page " + i, label: String(i)});
        const extra = Services.workspaces.filter(w => (w.id > 8 || w.id < 0) && (occupied.has(w.id) || w.id === currentId))
            .sort((a, b) => (a.id < 0 ? 1000 - a.id : a.id) - (b.id < 0 ? 1000 - b.id : b.id));
        for (const w of extra)
            result.push({id: w.id, name: w.id > 0 ? "Page " + w.id : "Scratch", label: w.id > 0 ? String(w.id) : "S"});
        return result;
    }
    // Every window in page order, then left to right: the order the arrow keys pick in.
    readonly property var ordered: Services.windows.filter(w => w.workspace && pages.some(page => page.id === w.workspace.id))
        .sort((a, b) => pageIndex(a.workspace.id) - pageIndex(b.workspace.id) || frame(a, 0, 1).x - frame(b, 0, 1).x)
    readonly property var hits: ordered.filter(w => matches(w))
    function same(a, b) {
        return a === b || (!!a && !!b && !!a.address && a.address === b.address);
    }
    function pageIndex(id) {
        return pages.findIndex(page => page.id === id);
    }
    function appId(window) {
        return window ? (window.wayland ? window.wayland.appId || "" : (window.lastIpcObject || {}).class || "") : "";
    }
    function appName(window) {
        const id = appId(window);
        const entry = id && DesktopEntries.heuristicLookup ? DesktopEntries.heuristicLookup(id) : null;
        return entry && entry.name ? entry.name : id.split(".").pop() || "Window";
    }
    function appIcon(window) {
        const id = appId(window);
        if (!id)
            return "";
        const entry = DesktopEntries.heuristicLookup ? DesktopEntries.heuristicLookup(id) : null;
        const icon = entry && entry.icon ? entry.icon : id;
        if (icon.startsWith("/"))
            return "file://" + icon;
        return Quickshell.hasThemeIcon(icon) ? Quickshell.iconPath(icon) : "";
    }
    function matches(window) {
        return folded === "" || (appName(window) + " " + appId(window) + " " + (window.title || "")).toLowerCase().indexOf(folded) >= 0;
    }
    // Where a window sits on its screen, as fractions of the screen; side by side when Hyprland hasn't said.
    function frame(window, index, count) {
        const ipc = window.lastIpcObject || {};
        const monitor = window.workspace ? window.workspace.monitor : null;
        if (ipc.at && ipc.size && monitor && monitor.width > 0 && monitor.height > 0) {
            const rotated = ((monitor.lastIpcObject || {}).transform || 0) % 2 === 1;
            const scale = monitor.scale || 1;
            const width = (rotated ? monitor.height : monitor.width) / scale;
            const height = (rotated ? monitor.width : monitor.height) / scale;
            const x = Math.max(0, Math.min(0.92, (ipc.at[0] - monitor.x) / width));
            const y = Math.max(0, Math.min(0.92, (ipc.at[1] - monitor.y) / height));
            return {x: x, y: y, w: Math.max(0.08, Math.min(1 - x, ipc.size[0] / width)), h: Math.max(0.08, Math.min(1 - y, ipc.size[1] / height))};
        }
        return {x: index / count, y: 0, w: 1 / count, h: 1};
    }
    function wallpaper(id) {
        const space = Services.workspaces.find(w => w.id === id);
        const output = space && space.monitor ? space.monitor.name : ShellState.screenName;
        const active = ShellState.activeWallpapers;
        const path = active[output] || active[Object.keys(active)[0]] || "";
        return path ? "file://" + path.split("/").map(encodeURIComponent).join("/") : "";
    }
    function go(page) {
        moving = null;
        Services.workspace(page.id);
        ShellState.close();
    }
    function moveHere(page) {
        if (!moving || page.id <= 0)
            return;
        Services.moveWindow(moving, page.id);
        moving = null;
    }
    function focusWindow(window) {
        if (!window)
            return;
        Services.focusWindow(window);
        ShellState.close();
    }
    function step(delta) {
        const list = hits;
        if (!list.length)
            return;
        const index = list.findIndex(w => same(w, moving));
        moving = list[index < 0 ? (delta > 0 ? 0 : list.length - 1) : (index + delta + list.length) % list.length];
    }
    // The number keys go to (or, with a window picked, move it to) that page; 0 is page 10.
    function numberKey(key) {
        const id = key === Qt.Key_0 ? 10 : key - Qt.Key_0;
        const page = pages.find(p => p.id === id) || {id: id, name: "Page " + id};
        if (moving)
            moveHere(page);
        else
            go(page);
    }
    Component.onCompleted: {
        // Window positions come from Hyprland's last report; ask again so they match the screen now.
        if (Hyprland.refreshToplevels)
            Hyprland.refreshToplevels();
        if (Hyprland.refreshMonitors)
            Hyprland.refreshMonitors();
    }
    // A picked window that closes, or a search that hides it, lets go of it.
    onHitsChanged: if (moving && !hits.some(w => same(w, moving))) moving = null
    Keys.onEscapePressed: event => {
        if (root.moving) {
            root.moving = null;
        } else if (search.text !== "") {
            search.clear();
        } else {
            event.accepted = false;
        }
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 12
        // Title, what is going on, Find a window and close.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            spacing: 12
            C.Label {
                text: root.title
                font.pixelSize: 17
                font.weight: 650
                elide: Text.ElideNone
                Layout.leftMargin: 2
            }
            C.Label {
                // A search that finds nothing says so here, where the window count usually is.
                text: root.moving ? root.appName(root.moving) + " picked · choose a page"
                    : root.folded !== "" ? (root.hits.length ? root.hits.length + (root.hits.length === 1 ? " window matches" : " windows match") : "No window matches “" + root.query.trim() + "”")
                    : (root.currentId > 0 ? "Page " + root.currentId : "Scratch") + " · " + Services.windows.length + (Services.windows.length === 1 ? " window open" : " windows open")
                color: root.moving ? Theme.accentText : root.folded !== "" && !root.hits.length ? Theme.dangerText : Theme.textDim
                font.pixelSize: 13
                Layout.fillWidth: true
                Layout.minimumWidth: 0
            }
            C.Field {
                id: search
                focus: true
                Layout.preferredWidth: 260
                implicitHeight: 34
                leftPadding: 32
                font.pixelSize: 13
                placeholderText: "Find a window"
                C.Icon {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    name: "search"
                    size: 14
                    color: Theme.textDim
                }
                Keys.onUpPressed: root.step(-1)
                Keys.onDownPressed: root.step(1)
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                        root.step(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1);
                        event.accepted = true;
                    } else if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9 && search.text === "" && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
                        // Digits type into the search once it has text, so "2" still finds a "2" in a title.
                        root.numberKey(event.key);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ShiftModifier) && root.moving) {
                        Services.closeWindow(root.moving);
                        root.moving = null;
                        event.accepted = true;
                    }
                }
                onAccepted: root.focusWindow(root.moving || root.hits[0] || null)
            }
            C.Button {
                glyph: "close"
                implicitWidth: 32
                implicitHeight: 32
                flat: true
                hint: "Close · Escape"
                onClicked: ShellState.close()
            }
        }
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 4
            rowSpacing: 12
            columnSpacing: 12
            Repeater {
                model: root.pages
                ColumnLayout {
                    id: cell
                    required property var modelData
                    readonly property var windows: Services.windows.filter(w => w.workspace && w.workspace.id === modelData.id)
                    readonly property bool current: root.currentId === modelData.id
                    readonly property bool canMove: !!root.moving && modelData.id > 0 && !!root.moving.workspace && root.moving.workspace.id !== modelData.id
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 1
                    spacing: 6
                    // The page number (accent on the current page), its window count, and Move here.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 22
                        spacing: 8
                        AbstractButton {
                            id: pageKey
                            implicitWidth: pageLabel.implicitWidth
                            implicitHeight: 22
                            hoverEnabled: true
                            focusPolicy: Qt.NoFocus
                            Accessible.name: (cell.current ? "Current page, " : "Go to ") + cell.modelData.name
                            onClicked: root.go(cell.modelData)
                            contentItem: Item {}
                            RowLayout {
                                id: pageLabel
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8
                                Rectangle {
                                    implicitWidth: Math.max(20, number.implicitWidth + 10)
                                    implicitHeight: 20
                                    radius: 6
                                    color: cell.current ? Theme.accent : pageKey.hovered ? Theme.keyHover : Theme.keyTile
                                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                                    C.Label {
                                        id: number
                                        anchors.centerIn: parent
                                        text: cell.modelData.label
                                        color: cell.current ? Theme.accentInk : cell.windows.length ? Theme.text : Theme.textFaint
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        font.features: ({"tnum": 1})
                                    }
                                }
                                C.Label {
                                    visible: text !== ""
                                    text: cell.modelData.id < 0 ? cell.modelData.name + (cell.windows.length ? " · " + cell.windows.length : "")
                                        : cell.windows.length ? cell.windows.length + (cell.windows.length === 1 ? " window" : " windows") : ""
                                    color: pageKey.hovered ? Theme.textSecondary : Theme.textDim
                                    font.pixelSize: 12
                                }
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        C.Button {
                            visible: cell.canMove
                            text: "Move here"
                            accent: true
                            labelSize: 11
                            implicitHeight: 22
                            cornerRadius: 6
                            leftPadding: 9
                            rightPadding: 9
                            focusPolicy: Qt.NoFocus
                            hint: "Move " + root.appName(root.moving) + " to " + cell.modelData.name
                            onClicked: root.moveHere(cell.modelData)
                        }
                    }
                    // The small desktop: the wallpaper, a bar line, and the windows as cards where they sit.
                    MouseArea {
                        id: desk
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        Accessible.role: Accessible.Button
                        Accessible.name: "Go to " + cell.modelData.name
                        onClicked: root.go(cell.modelData)
                        ClippingRectangle {
                            anchors.fill: parent
                            radius: Theme.radiusCard
                            color: Theme.well
                            Rectangle {
                                anchors.fill: parent
                                gradient: Gradient {
                                    GradientStop { position: 0; color: Theme.module }
                                    GradientStop { position: 1; color: Theme.well }
                                }
                            }
                            Image {
                                id: wall
                                anchors.fill: parent
                                source: root.wallpaper(cell.modelData.id)
                                sourceSize.width: 400
                                sourceSize.height: 240
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                            }
                            // Darkened so the cards and the words on it read on any wallpaper.
                            Rectangle {
                                anchors.fill: parent
                                visible: wall.status === Image.Ready
                                gradient: Gradient {
                                    // Empty pages sit further back, so the pages with windows lead.
                                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, (desk.containsMouse ? 0.22 : 0.32) + (cell.windows.length === 0 ? 0.3 : 0)) }
                                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, (desk.containsMouse ? 0.4 : 0.5) + (cell.windows.length === 0 ? 0.25 : 0)) }
                                }
                            }
                            Rectangle {
                                x: 5
                                y: 4
                                width: parent.width - 10
                                height: 5
                                radius: 3
                                color: Theme.tint(Theme.caseColor, 0.8)
                            }
                            Rectangle {
                                visible: cell.windows.length === 0
                                anchors.centerIn: parent
                                implicitWidth: emptyLabel.implicitWidth + 20
                                implicitHeight: 26
                                radius: 13
                                color: cell.canMove ? Theme.accentSoft : Theme.tint(Theme.caseColor, 0.75)
                                border.width: 1
                                border.color: cell.canMove ? Theme.accentLine : Theme.edge
                                C.Label {
                                    id: emptyLabel
                                    anchors.centerIn: parent
                                    text: cell.canMove ? "Move here" : "Empty"
                                    color: cell.canMove ? Theme.accentText : Theme.textSecondary
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }
                            }
                            Repeater {
                                model: cell.windows
                                AbstractButton {
                                    id: card
                                    required property var modelData
                                    required property int index
                                    readonly property var spot: root.frame(modelData, index, cell.windows.length)
                                    readonly property bool picked: root.same(root.moving, modelData)
                                    readonly property bool hit: root.matches(modelData)
                                    readonly property real innerHeight: desk.height - 18
                                    x: spot.x * desk.width + 5
                                    y: 14 + spot.y * innerHeight
                                    width: Math.max(24, spot.w * desk.width - 10)
                                    height: Math.max(24, spot.h * innerHeight - 4)
                                    hoverEnabled: true
                                    focusPolicy: Qt.NoFocus
                                    opacity: hit ? 1 : 0.3
                                    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                                    Accessible.name: root.appName(modelData) + ": " + (modelData.title || "")
                                    Accessible.role: Accessible.CheckBox
                                    Accessible.checked: picked
                                    onClicked: root.moving = picked ? null : modelData
                                    onDoubleClicked: root.focusWindow(modelData)
                                    contentItem: Item {}
                                    background: Rectangle {
                                        radius: 8
                                        color: Theme.tint(Theme.module, 0.94)
                                        border.width: card.picked ? 2 : root.folded !== "" && card.hit ? 1 : 0
                                        border.color: card.picked ? Theme.accent : Theme.accentLine
                                        // The window itself under its name, when previews are on and there is room.
                                        ClippingRectangle {
                                            id: previewFrame
                                            visible: preview.hasContent && height >= 24
                                            x: 6
                                            y: 30
                                            width: parent.width - 12
                                            height: parent.height - 36
                                            radius: 5
                                            color: "transparent"
                                            ScreencopyView {
                                                id: preview
                                                anchors.fill: parent
                                                captureSource: !ShellState.locked && !Theme.lowPower && ShellState.setting("windowPreviews", true) && card.height > 60 ? card.modelData.wayland : null
                                                live: false
                                                paintCursor: false
                                                constraintSize: Qt.size(400, 240)
                                            }
                                        }
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: parent.radius
                                            color: Theme.text
                                            opacity: card.hovered ? 0.05 : 0
                                            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                                        }
                                    }
                                    ColumnLayout {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 8
                                        anchors.rightMargin: closeKey.visible ? 28 : 8
                                        spacing: 6
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6
                                            Rectangle {
                                                implicitWidth: 18
                                                implicitHeight: 18
                                                radius: 5
                                                color: icon.visible ? "transparent" : card.picked ? Theme.accent : Theme.textSecondary
                                                Image {
                                                    id: icon
                                                    anchors.fill: parent
                                                    source: root.appIcon(card.modelData)
                                                    visible: status === Image.Ready
                                                    sourceSize.width: 18
                                                    sourceSize.height: 18
                                                }
                                                C.Label {
                                                    visible: !icon.visible
                                                    anchors.centerIn: parent
                                                    text: root.appName(card.modelData).charAt(0).toUpperCase()
                                                    color: Theme.accentInk
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                }
                                            }
                                            C.Label {
                                                text: root.appName(card.modelData)
                                                font.pixelSize: 12
                                                font.weight: Font.DemiBold
                                                Layout.fillWidth: true
                                            }
                                        }
                                        C.Label {
                                            visible: !previewFrame.visible && card.height > 52
                                            text: card.modelData.title || ""
                                            color: Theme.textMuted
                                            font.pixelSize: 11
                                            Layout.fillWidth: true
                                        }
                                    }
                                    C.Button {
                                        id: closeKey
                                        visible: card.hovered || card.picked
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.margins: 5
                                        glyph: "close"
                                        danger: true
                                        flat: true
                                        implicitWidth: 22
                                        implicitHeight: 22
                                        cornerRadius: 6
                                        padding: 3
                                        focusPolicy: Qt.NoFocus
                                        hint: "Close " + root.appName(card.modelData)
                                        onClicked: {
                                            if (card.picked)
                                                root.moving = null;
                                            Services.closeWindow(card.modelData);
                                        }
                                    }
                                }
                            }
                            // The current page carries the accent ring; the rest a hairline.
                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.radiusCard
                                color: "transparent"
                                border.width: cell.current ? 2 : 1
                                border.color: cell.current ? Theme.accent : Theme.separator
                            }
                        }
                    }
                }
            }
        }
        // Key hints, and the scratch page.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 22
            spacing: 16
            Repeater {
                model: root.moving ? [{key: "1–8", text: "Move here"}, {key: "↑↓", text: "Pick another"}, {key: "↵", text: "Focus"},
                                      {key: "Shift Del", text: "Close window"}, {key: "Esc", text: "Cancel"}]
                    : [{key: "1–8", text: "Go to page"}, {key: "", text: "Click a window, then Move here"}, {key: "↑↓", text: "Pick a window"},
                       {key: "↵", text: "Focus"}, {key: "Esc", text: "Close"}]
                RowLayout {
                    required property var modelData
                    spacing: 6
                    C.KeyHint {
                        visible: parent.modelData.key !== ""
                        text: parent.modelData.key
                    }
                    C.Label {
                        text: parent.modelData.text
                        color: Theme.textDim
                        font.pixelSize: 12
                        elide: Text.ElideNone
                    }
                }
            }
            Item {
                Layout.fillWidth: true
            }
            C.Button {
                text: "Scratch page"
                glyph: "window"
                flat: true
                labelSize: 12
                implicitHeight: 26
                cornerRadius: 7
                leftPadding: 8
                rightPadding: 10
                focusPolicy: Qt.NoFocus
                foreground: hovered ? Theme.text : Theme.textDim
                hint: "Show or hide the scratch page"
                onClicked: {
                    Hyprland.dispatch('hl.dsp.workspace.toggle_special("magic")');
                    ShellState.close();
                }
            }
        }
    }
}
