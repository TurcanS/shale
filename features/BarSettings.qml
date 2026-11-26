import QtQuick
import QtQuick.Layouts
import Quickshell
import "../core"
import "../core/barItems.js" as BarItems
import "../components" as C

// Settings → Bar: where each item sits, how the bar looks, and the screens it shows on.
ColumnLayout {
    id: root
    spacing: 8
    readonly property var layout: BarItems.layout(ShellState.setting("barLayout", {}))
    readonly property var zoneNames: ({left: "Left", center: "Center", right: "Right", hidden: "Hidden"})
    readonly property var order: ["left", "center", "right"]
    readonly property bool edge: ShellState.setting("barStyle", "floating") === "edge"
    // Items that only show while something happens; the preview leaves them out.
    readonly property var passing: ["recording", "privacy", "media", "focus", "timer", "stayAwake", "keyboard", "vpn"]
    function save(value) {
        ShellState.setSetting("barLayout", value);
    }
    // `id` taken out of where it is and put in `zone` at `index`, counted without it.
    function place(id, zone, index) {
        const current = BarItems.layout(ShellState.setting("barLayout", {}));
        for (const name of Object.keys(current)) {
            const at = current[name].indexOf(id);
            if (at >= 0)
                current[name].splice(at, 1);
        }
        current[zone].splice(Math.max(0, Math.min(index, current[zone].length)), 0, id);
        save(current);
    }
    // One place earlier or later on the bar; past either end of a zone it joins the next zone.
    function step(id, zone, index, by) {
        const ids = layout[zone];
        if (index + by >= 0 && index + by < ids.length) {
            place(id, zone, index + by);
            return;
        }
        const next = order[order.indexOf(zone) + by];
        if (next)
            place(id, next, by < 0 ? layout[next].length : 0);
    }
    // Shown again, an item goes back to the end of the zone it comes in.
    function setShown(id, shown) {
        const item = BarItems.find(id);
        save(BarItems.moved(ShellState.setting("barLayout", {}), id, shown ? item.zone : "hidden", 0));
    }
    // Where a dragged item may land: the left, center and right groups.
    function targets() {
        const result = [];
        for (let i = 0; i < zones.count; i++) {
            const zone = zones.itemAt(i);
            if (zone && !zone.hidden)
                result.push({key: zone.modelData, group: zone.group});
        }
        return result;
    }
    // One item on the small bar, drawn like the bar draws it at about two thirds of its size.
    component PreviewItem: Item {
        id: part
        property string itemId: ""
        readonly property var item: BarItems.find(itemId)
        implicitWidth: itemId === "workspaces" ? pages.width : itemId === "clock" ? clockRow.implicitWidth + 12 : itemId === "windowTitle" ? 70 : 18
        implicitHeight: 20
        // The pages: a module pill with the current page stretched and lit, as dots or numbers.
        Rectangle {
            id: pages
            readonly property bool dots: ShellState.setting("workspaceStyle", "dots") === "dots"
            visible: part.itemId === "workspaces"
            width: pageRow.implicitWidth + 12
            height: 20
            radius: 6
            color: Theme.module
            Row {
                id: pageRow
                anchors.centerIn: parent
                spacing: 3
                Repeater {
                    model: 3
                    Rectangle {
                        id: page
                        required property int index
                        anchors.verticalCenter: parent.verticalCenter
                        width: page.index === 0 ? 15 : pages.dots ? 5 : 11
                        height: pages.dots ? 5 : 11
                        radius: pages.dots ? 2.5 : 4
                        color: page.index === 0 ? Theme.accent : pages.dots ? (page.index === 1 ? Theme.textDim : Theme.mix(Theme.key, Theme.textFaint, 0.25)) : "transparent"
                        C.Label {
                            visible: !pages.dots
                            anchors.centerIn: parent
                            text: String(page.index + 1)
                            color: page.index === 0 ? Theme.accentInk : Theme.textDim
                            font.family: Theme.mono
                            font.pixelSize: 7
                            elide: Text.ElideNone
                        }
                    }
                }
            }
        }
        // The clock as set: the time, then the day or the date.
        Row {
            id: clockRow
            readonly property date sample: new Date(2026, 9, 25, 14, 30, 5)
            readonly property bool seconds: ShellState.setting("clockSeconds", false)
            readonly property string style: ShellState.setting("clockFormat", "date-time")
            visible: part.itemId === "clock"
            anchors.centerIn: parent
            spacing: 5
            C.Label {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(clockRow.sample, ShellState.setting("clock24h", true) ? (clockRow.seconds ? "HH:mm:ss" : "HH:mm") : (clockRow.seconds ? "h:mm:ss AP" : "h:mm AP"))
                font.pixelSize: 9
                font.weight: 650
                font.features: ({"tnum": 1})
                elide: Text.ElideNone
            }
            C.Label {
                visible: clockRow.style !== "time"
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(clockRow.sample, clockRow.style === "date-time" ? "ddd d MMM" : "ddd")
                color: Theme.textMuted
                font.pixelSize: 8
                elide: Text.ElideNone
            }
        }
        // The window title: an app tile, then a line standing in for its words.
        Row {
            visible: part.itemId === "windowTitle"
            anchors.verticalCenter: parent.verticalCenter
            x: 4
            spacing: 5
            Rectangle {
                width: 12
                height: 12
                radius: 3.5
                color: Theme.key
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 46
                height: 4
                radius: 2
                color: Theme.textFaint
                opacity: 0.6
            }
        }
        C.Icon {
            visible: part.itemId !== "workspaces" && part.itemId !== "clock" && part.itemId !== "windowTitle"
            anchors.centerIn: parent
            name: part.item ? part.item.icon : ""
            size: 11
            color: Theme.textSecondary
        }
    }
    // A small picture of the bar as arranged, floating over a strip of desktop (or edge to edge).
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 48
        radius: Theme.radiusCard + 2
        border.width: 1
        border.color: Theme.separator
        clip: true
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.mix(Theme.well, Theme.accent, 0.12) }
            GradientStop { position: 1; color: Theme.well }
        }
        Accessible.role: Accessible.Graphic
        Accessible.name: "Bar preview"
        Rectangle {
            id: miniBar
            x: root.edge ? 0 : 8
            y: root.edge ? 0 : 8
            width: parent.width - 2 * x
            height: 28
            radius: root.edge ? 0 : 8
            color: Theme.caseColor
            border.width: root.edge ? 0 : 1
            border.color: Theme.hairline
            Rectangle {
                visible: root.edge
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.hairline
            }
            Repeater {
                id: previewZones
                model: root.order
                Row {
                    id: zoneRow
                    required property string modelData
                    required property int index
                    anchors.verticalCenter: parent.verticalCenter
                    // The middle stays centred unless a side would run into it, as on the bar.
                    x: zoneRow.modelData === "left" ? 4 : zoneRow.modelData === "right" ? miniBar.width - zoneRow.width - 4
                       : Math.max(previewZones.itemAt(0) ? previewZones.itemAt(0).width + 8 : 4, (miniBar.width - zoneRow.width) / 2)
                    spacing: 3
                    Repeater {
                        // Status items next to each other share one key; items that come and go stay out.
                        model: BarItems.runs(root.layout[zoneRow.modelData])
                            .map(run => ({status: run.status, ids: run.ids.filter(id => root.passing.indexOf(id) < 0)}))
                            .filter(run => run.ids.length > 0)
                        Rectangle {
                            id: run
                            required property var modelData
                            implicitWidth: runRow.implicitWidth + (modelData.status ? 8 : 0)
                            implicitHeight: 20
                            radius: 6
                            color: modelData.status ? Theme.module : "transparent"
                            Row {
                                id: runRow
                                anchors.centerIn: parent
                                spacing: run.modelData.status ? 0 : 3
                                Repeater {
                                    model: run.modelData.ids
                                    PreviewItem {
                                        required property string modelData
                                        itemId: modelData
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    C.Caption {
        text: "Drag an item by its handle, or move it with the arrows; past the end of a side it moves to the next one. Items that only show while something happens (recording, focus, timers, VPN) take their place when they appear."
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    Repeater {
        id: zones
        model: ["left", "center", "right", "hidden"]
        ColumnLayout {
            id: zone
            required property string modelData
            readonly property var ids: root.layout[zone.modelData]
            readonly property bool hidden: zone.modelData === "hidden"
            readonly property Item group: zoneGroup
            // Raised while one of its rows is dragged, so the row passes over the other groups.
            property bool lifted: false
            visible: !hidden || ids.length > 0
            z: lifted ? 2 : 0
            Layout.fillWidth: true
            spacing: 8
            C.SectionHeader {
                text: root.zoneNames[zone.modelData]
                Layout.topMargin: 2
            }
            C.Group {
                id: zoneGroup
                C.Label {
                    visible: zone.ids.length === 0
                    text: "Nothing here. Drag an item in to put it on this side."
                    color: Theme.textDim
                    font.pixelSize: Theme.small
                    verticalAlignment: Text.AlignVCenter
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    Layout.leftMargin: Theme.gapL
                }
                // Handle, name, what it shows, earlier and later on the bar, then whether it shows.
                Repeater {
                    model: zone.ids
                    C.OrderRow {
                        id: row
                        required property string modelData
                        required property int index
                        readonly property var item: BarItems.find(modelData)
                        itemId: modelData
                        glyph: item.icon
                        label: item.title
                        description: item.required ? (item.description ? item.description + " · always shown" : "Always shown") : item.description || ""
                        labelWidth: Math.max(150, Theme.body * 11)
                        shown: !zone.hidden
                        locked: !!item.required
                        draggable: !zone.hidden
                        canEarlier: !zone.hidden && !(zone.modelData === "left" && index === 0)
                        canLater: !zone.hidden && !(zone.modelData === "right" && index === zone.ids.length - 1)
                        onMoved: by => root.step(modelData, zone.modelData, index, by)
                        onToggled: root.setShown(modelData, zone.hidden)
                        onDragStarted: {
                            zone.lifted = true;
                            dropLine.targets = root.targets();
                            dropLine.row = row;
                        }
                        // Placed once the drag has finished, since the move rebuilds these rows.
                        onDropped: {
                            const drop = dropLine.drop;
                            if (drop)
                                Qt.callLater(root.place, modelData, drop.key, drop.index);
                        }
                        onDraggingChanged: if (!dragging) {
                            zone.lifted = false;
                            dropLine.row = null;
                        }
                    }
                }
            }
        }
    }
    C.SectionHeader {
        text: "Look"
        Layout.topMargin: 2
    }
    C.Group {
        C.ChoiceRow {
            settingKey: "barStyle"
            label: "Style"
            description: "Floating keeps 8 px from the screen edges"
            model: [{key: "floating", text: "Floating"}, {key: "edge", text: "Edge to edge"}]
            current: ShellState.setting("barStyle", "floating")
            onActivated: key => ShellState.setSetting("barStyle", key)
        }
        C.ChoiceRow {
            settingKey: "clockFormat"
            label: "Clock"
            description: "What the clock shows beside the time"
            model: [{key: "time", text: "Time"}, {key: "day-time", text: "Day"}, {key: "date-time", text: "Date"}]
            current: ShellState.setting("clockFormat", "date-time")
            onActivated: key => ShellState.setSetting("clockFormat", key)
        }
        C.SettingToggle {
            text: "Show seconds"
            description: "On the bar's clock"
            key: "clockSeconds"
        }
        C.ChoiceRow {
            settingKey: "workspaceStyle"
            label: "Pages"
            description: "How the pages on a screen are drawn"
            model: [{key: "numbers", text: "Numbers"}, {key: "dots", text: "Dots"}]
            current: ShellState.setting("workspaceStyle", "dots")
            onActivated: key => ShellState.setSetting("workspaceStyle", key)
        }
        C.ChoiceRow {
            settingKey: "workspaceSlots"
            label: "Empty pages"
            description: "Keep the first ones on the bar even without windows"
            model: [{key: 0, text: "Hide"}, {key: 5, text: "1–5"}, {key: 10, text: "1–10"}]
            current: ShellState.setting("workspaceSlots", 0)
            onActivated: key => ShellState.setSetting("workspaceSlots", key)
        }
        C.ChoiceRow {
            settingKey: "trayIcons"
            label: "Tray icons"
            description: "The rest open from the tray button"
            model: [{key: -1, text: "Auto", hint: "More on wider screens"}, {key: 0, text: "0"}, {key: 1, text: "1"}, {key: 2, text: "2"}, {key: 3, text: "3"}, {key: 5, text: "5"}]
            current: ShellState.setting("trayIcons", -1)
            onActivated: key => ShellState.setSetting("trayIcons", key)
        }
        C.ChoiceRow {
            settingKey: "batteryPercent"
            label: "Battery percentage"
            description: "Low battery always shows it"
            model: [{key: "auto", text: "Auto", hint: "Hidden on narrow screens"}, {key: "always", text: "Always"}, {key: "never", text: "Never"}]
            current: ShellState.setting("batteryPercent", "auto")
            onActivated: key => ShellState.setSetting("batteryPercent", key)
        }
    }
    C.SectionHeader {
        text: "Behaviour"
        Layout.topMargin: 2
    }
    C.Group {
        C.SettingToggle {
            text: "Hide bar over fullscreen windows"
            description: "It comes back when the window leaves fullscreen"
            key: "hideFullscreen"
            fallback: true
        }
        C.SettingToggle {
            text: "Show what's playing in the bar"
            description: "Cover and title, on bars wider than 1100 px"
            key: "barMedia"
            fallback: true
        }
        C.SettingToggle {
            text: "Show a card when the track changes"
            description: "Title and artist for a moment"
            key: "trackChangeCard"
            fallback: true
        }
    }
    C.SectionHeader {
        text: "Show the bar on"
        Layout.topMargin: 2
    }
    C.Group {
        Repeater {
            model: Quickshell.screens
            C.Toggle {
                required property var modelData
                Layout.fillWidth: true
                flat: true
                text: modelData.name
                description: modelData.model || ""
                selected: ShellState.setting("hiddenOutputs", []).indexOf(modelData.name) < 0
                onClicked: {
                    const hidden = ShellState.setting("hiddenOutputs", []);
                    // The last bar stays: without one there is no way back here but a shortcut.
                    if (hidden.indexOf(modelData.name) < 0 && Quickshell.screens.every(screen => screen.name === modelData.name || hidden.indexOf(screen.name) >= 0)) {
                        ShellState.message("One screen keeps its bar", "info");
                        return;
                    }
                    ShellState.setSetting("hiddenOutputs", hidden.indexOf(modelData.name) < 0 ? hidden.concat([modelData.name]) : hidden.filter(n => n !== modelData.name));
                }
            }
        }
    }
    C.DropLine {
        id: dropLine
        Layout.topMargin: -root.spacing
    }
}
