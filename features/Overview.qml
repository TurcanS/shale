import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../core"
import "../services"
import "../components" as C

FocusScope {
    id: root
    property var moving: null
    readonly property var occupied: new Set(Services.windows.filter(w => w.workspace).map(w => w.workspace.id))
    readonly property int currentId: Services.focusedWorkspace ? Services.focusedWorkspace.id : 0
    readonly property var spaces: {
        let result = [];
        for (let i = 1; i <= 10; i++)
            result.push({
                id: i,
                name: "Workspace " + i
            });
        for (const w of Services.workspaces)
            if (w.id < 0 || w.id > 10)
                result.push({
                    id: w.id,
                    name: w.id > 0 ? "Workspace " + w.id : w.name
                });
        const priority = space => space.id === currentId ? 0 : occupied.has(space.id) ? 1 : 2;
        result.sort((a, b) => priority(a) - priority(b) ||
            (a.id < 0 ? 1000 + Math.abs(a.id) : a.id) - (b.id < 0 ? 1000 + Math.abs(b.id) : b.id));
        return result;
    }
    // Only workspaces with something in them earn a full card; the rest become compact chips.
    readonly property var busySpaces: spaces.filter(space => space.id === currentId || occupied.has(space.id))
    readonly property var emptySpaces: spaces.filter(space => space.id !== currentId && !occupied.has(space.id)).sort((a, b) => (a.id < 0 ? 1000 - a.id : a.id) - (b.id < 0 ? 1000 - b.id : b.id))
    function activate(space) {
        if (moving) {
            if (space.id <= 0)
                return;
            Services.moveWindow(moving, space.id);
            moving = null;
        } else {
            Services.workspace(space.id);
            ShellState.close();
        }
    }
    function appIcon(window) {
        const appId = window && window.wayland ? window.wayland.appId || "" : "";
        if (!appId)
            return "";
        const entry = DesktopEntries.heuristicLookup ? DesktopEntries.heuristicLookup(appId) : null;
        const icon = entry && entry.icon ? entry.icon : appId;
        if (icon.startsWith("/"))
            return "file://" + icon;
        return Quickshell.hasThemeIcon(icon) ? Quickshell.iconPath(icon) : "";
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.sectionSpacing
        Rectangle {
            visible: !!root.moving
            Layout.fillWidth: true
            implicitHeight: 64
            radius: Theme.controlRadius
            color: Theme.surface
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12
                C.Icon { name: "chevron"; size: 20 }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    C.Label {
                        text: "Choose a workspace for this window"
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                    }
                    C.Label {
                        text: root.moving ? (root.moving.title || "Window") : ""
                        font.pixelSize: Theme.caption
                        color: Theme.muted
                        Layout.fillWidth: true
                    }
                }
                C.Button {
                    text: "Cancel move"
                    glyph: "close"
                    onClicked: root.moving = null
                }
            }
        }
        ScrollView {
            id: workspaceScroll
            ScrollBar.vertical: C.ScrollBar {
                parent: workspaceScroll
                x: workspaceScroll.width - width
                y: workspaceScroll.topPadding
                height: workspaceScroll.availableHeight
            }
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true
            ColumnLayout {
                width: workspaceScroll.availableWidth
                spacing: Theme.sectionSpacing
                GridLayout {
                    Layout.fillWidth: true
                    columns: width > 750 ? 3 : width > 430 ? 2 : 1
                    rowSpacing: Theme.sectionSpacing
                    columnSpacing: Theme.sectionSpacing
                    Repeater {
                        model: root.busySpaces
                        Rectangle {
                            id: card
                            required property var modelData
                            required property int index
                            readonly property var windows: Services.windows.filter(w => w.workspace && w.workspace.id === modelData.id)
                            readonly property bool current: root.currentId === modelData.id
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredHeight: root.moving || !windows.length ? 72 : stack.implicitHeight + 24
                            color: current ? Theme.selection : Theme.surface
                            radius: Theme.controlRadius + 2
                            Behavior on color { ColorAnimation { duration: Theme.fast } }
                            ColumnLayout {
                                id: stack
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                    margins: 12
                                }
                                spacing: 8
                                C.Button {
                                    Layout.fillWidth: true
                                    implicitHeight: 44
                                    flat: true
                                    hint: root.moving ? "Move window to " + card.modelData.name : "Switch to " + card.modelData.name
                                    enabled: !root.moving || card.modelData.id > 0
                                    contentItem: RowLayout {
                                        spacing: 10
                                        C.Label {
                                            text: card.modelData.id > 0 ? String(card.modelData.id).padStart(2, "0") : "S"
                                            font.family: Theme.mono
                                            font.pixelSize: 22
                                            color: card.current ? Theme.accentText : Theme.text
                                        }
                                        C.Label {
                                            text: root.moving ? (card.modelData.id > 0 ? "Move here" : "Unavailable") : (card.modelData.id > 0 ? "" : card.modelData.name + " · ") + card.windows.length + (card.windows.length === 1 ? " window" : " windows")
                                            Layout.fillWidth: true
                                            font.pixelSize: Theme.small
                                            color: Theme.muted
                                        }
                                        Rectangle {
                                            visible: card.current
                                            Layout.preferredWidth: 5
                                            Layout.preferredHeight: 20
                                            radius: 3
                                            color: Theme.accent
                                        }
                                    }
                                    onClicked: root.activate(card.modelData)
                                }
                                Repeater {
                                    model: root.moving ? [] : card.windows
                                    ColumnLayout {
                                        id: windowRow
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 6
                                        C.Button {
                                            id: previewButton
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 100
                                            hint: "Focus " + (windowRow.modelData.title || "window")
                                            padding: 0
                                            onClicked: {
                                                Services.focusWindow(windowRow.modelData);
                                                ShellState.close();
                                            }
                                            background: Rectangle {
                                                radius: 10
                                                color: Theme.panel
                                                clip: true
                                                ScreencopyView {
                                                    id: preview
                                                    anchors.fill: parent
                                                    captureSource: !ShellState.locked && !Theme.lowPower && ShellState.setting("windowPreviews", true) ? windowRow.modelData.wayland : null
                                                    live: false
                                                    paintCursor: false
                                                    constraintSize: Qt.size(400, 200)
                                                }
                                                C.Icon {
                                                    visible: !preview.hasContent
                                                    anchors.centerIn: parent
                                                    name: "window"
                                                    size: 28
                                                    opacity: 0.35
                                                }
                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: parent.radius
                                                    color: Theme.text
                                                    opacity: previewButton.hovered ? 0.06 : 0
                                                    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                                                }
                                            }
                                            contentItem: Item {}
                                        }
                                        RowLayout {
                                            spacing: 4
                                            Image {
                                                source: root.appIcon(windowRow.modelData)
                                                visible: status === Image.Ready
                                                sourceSize.width: 18
                                                sourceSize.height: 18
                                                Layout.preferredWidth: 18
                                                Layout.preferredHeight: 18
                                                Layout.leftMargin: 4
                                            }
                                            C.Button {
                                                Layout.fillWidth: true
                                                flat: true
                                                hint: windowRow.modelData.title || "Window"
                                                contentItem: C.Label {
                                                    text: windowRow.modelData.title || "Window"
                                                    horizontalAlignment: Text.AlignLeft
                                                    font.pixelSize: Theme.small
                                                    elide: Text.ElideRight
                                                }
                                                onClicked: {
                                                    Services.focusWindow(windowRow.modelData);
                                                    ShellState.close();
                                                }
                                            }
                                            C.Button {
                                                glyph: "chevron"
                                                hint: "Move to another workspace"
                                                flat: true
                                                onClicked: root.moving = windowRow.modelData
                                            }
                                            C.Button {
                                                glyph: "close"
                                                hint: "Close window"
                                                danger: true
                                                flat: true
                                                onClicked: Services.closeWindow(windowRow.modelData)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                RowLayout {
                    visible: root.emptySpaces.length > 0
                    Layout.fillWidth: true
                    spacing: 12
                    C.Label {
                        text: root.moving ? "Move to empty" : "Empty"
                        color: Theme.muted
                        font.pixelSize: Theme.small
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: root.emptySpaces
                            C.Button {
                                required property var modelData
                                text: modelData.id > 0 ? String(modelData.id) : "S"
                                implicitWidth: Math.max(40, implicitHeight)
                                enabled: !root.moving || modelData.id > 0
                                hint: root.moving ? "Move window to " + modelData.name : "Open " + modelData.name
                                onClicked: root.activate(modelData)
                            }
                        }
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            visible: !root.moving
            C.Button {
                text: "Scratch workspace"
                glyph: "window"
                flat: true
                onClicked: {
                    Hyprland.dispatch('hl.dsp.workspace.toggle_special("magic")');
                    ShellState.close();
                }
            }
            Item {
                Layout.fillWidth: true
            }
            C.Label {
                text: Services.windows.length + (Services.windows.length === 1 ? " window open" : " windows open")
                color: Theme.muted
                font.pixelSize: Theme.small
            }
        }
    }
    Keys.onEscapePressed: event => {
        if (root.moving) {
            root.moving = null;
            event.accepted = true;
        } else {
            event.accepted = false;
        }
    }
}
