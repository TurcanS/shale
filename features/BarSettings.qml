import QtQuick
import QtQuick.Layouts
import Quickshell
import "../core"
import "../core/barItems.js" as BarItems
import "../components" as C

// Settings → Bar: where each item sits, how the bar looks, and the screens it shows on.
ColumnLayout {
    id: root
    spacing: Theme.gapM
    readonly property var layout: BarItems.layout(ShellState.setting("barLayout", {}))
    readonly property var zoneNames: ({left: "Left", center: "Center", right: "Right", hidden: "Hidden"})
    function move(id, zone, step) {
        ShellState.setSetting("barLayout", BarItems.moved(ShellState.setting("barLayout", {}), id, zone, step));
    }
    C.SectionHeader {
        text: "Layout"
        Layout.topMargin: Theme.gapS
    }
    // A small picture of the bar as arranged.
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 34
        radius: ShellState.setting("barStyle", "floating") === "edge" ? 0 : Theme.radiusSmall + 2
        color: Theme.panel
        border.width: 1
        border.color: Theme.border
        Accessible.role: Accessible.Graphic
        Accessible.name: "Bar preview"
        Repeater {
            model: ["left", "center", "right"]
            Row {
                required property string modelData
                anchors.verticalCenter: parent.verticalCenter
                x: modelData === "left" ? 10 : modelData === "center" ? (parent.width - width) / 2 : parent.width - width - 10
                spacing: 2
                Repeater {
                    model: root.layout[parent.modelData]
                    Rectangle {
                        required property string modelData
                        readonly property var item: BarItems.find(modelData)
                        width: 18
                        height: 20
                        radius: 5
                        color: modelData === "control" ? Theme.raised : "transparent"
                        C.Icon {
                            anchors.centerIn: parent
                            name: parent.item ? parent.item.icon : ""
                            size: 12
                            color: Theme.muted
                        }
                    }
                }
            }
        }
    }
    C.Caption {
        text: "Items that only show while something happens (recording, focus, timers, VPN) take their place when they appear."
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    Repeater {
        model: ["left", "center", "right", "hidden"]
        ColumnLayout {
            id: zone
            required property string modelData
            readonly property var ids: root.layout[modelData]
            Layout.fillWidth: true
            spacing: Theme.gapXs + 2
            C.Label {
                text: root.zoneNames[zone.modelData]
                color: Theme.muted
                font.pixelSize: Theme.small
                font.weight: Font.DemiBold
                Layout.topMargin: Theme.gapXs
            }
            C.Group {
                C.Caption {
                    visible: zone.ids.length === 0
                    text: zone.modelData === "hidden" ? "Every item is on the bar." : "Nothing here."
                    Layout.fillWidth: true
                    Layout.margins: Theme.gapM
                }
                Repeater {
                    model: zone.ids
                    RowLayout {
                        id: row
                        required property string modelData
                        required property int index
                        readonly property var item: BarItems.find(modelData)
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(48, Theme.body + 34)
                        Layout.leftMargin: Theme.gapM
                        Layout.rightMargin: Theme.gapS
                        spacing: Theme.gapS
                        C.Icon {
                            name: row.item.icon
                            color: zone.modelData === "hidden" ? Theme.disabled : Theme.muted
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            C.Label {
                                text: row.item.title
                                color: zone.modelData === "hidden" ? Theme.muted : Theme.text
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            C.Caption {
                                visible: text !== ""
                                text: row.item.required ? (row.item.description ? row.item.description + " · always shown" : "Always shown") : row.item.description || ""
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                        C.Button {
                            visible: zone.modelData !== "hidden"
                            glyph: "chevron"
                            rotation: 180
                            flat: true
                            enabled: row.index > 0
                            hint: "Move " + row.item.title + " left"
                            implicitWidth: 30
                            implicitHeight: 30
                            onClicked: root.move(row.modelData, "", -1)
                        }
                        C.Button {
                            visible: zone.modelData !== "hidden"
                            glyph: "chevron"
                            flat: true
                            enabled: row.index < zone.ids.length - 1
                            hint: "Move " + row.item.title + " right"
                            implicitWidth: 30
                            implicitHeight: 30
                            onClicked: root.move(row.modelData, "", 1)
                        }
                        C.Segmented {
                            // One width for every row, with or without Hide, so the columns line up.
                            Layout.fillWidth: false
                            Layout.preferredWidth: Math.max(236, Theme.body * 17)
                            segmentHeight: 30
                            model: [{key: "left", text: "Left"}, {key: "center", text: "Center"}, {key: "right", text: "Right"}]
                                .concat(row.item.required ? [] : [{key: "hidden", text: "Hide", hint: "Hide " + row.item.title}])
                            current: zone.modelData
                            onActivated: key => root.move(row.modelData, key, 0)
                        }
                    }
                }
            }
        }
    }
    C.SectionHeader {
        text: "Look"
        Layout.topMargin: Theme.gapM
    }
    C.ChoiceRow {
        label: "Style"
        model: [{key: "floating", text: "Floating"}, {key: "edge", text: "Edge to edge"}]
        current: ShellState.setting("barStyle", "floating")
        onActivated: key => ShellState.setSetting("barStyle", key)
    }
    C.ChoiceRow {
        label: "Clock"
        model: [{key: "time", text: "Time"}, {key: "day-time", text: "Day"}, {key: "date-time", text: "Date"}]
        current: ShellState.setting("clockFormat", "day-time")
        onActivated: key => ShellState.setSetting("clockFormat", key)
    }
    C.Group {
        C.Toggle {
            Layout.fillWidth: true
            flat: true
            text: "Show seconds"
            selected: ShellState.setting("clockSeconds", false)
            onClicked: ShellState.setSetting("clockSeconds", !selected)
        }
    }
    C.ChoiceRow {
        label: "Workspaces"
        model: [{key: "numbers", text: "Numbers"}, {key: "dots", text: "Dots"}]
        current: ShellState.setting("workspaceStyle", "numbers")
        onActivated: key => ShellState.setSetting("workspaceStyle", key)
    }
    C.ChoiceRow {
        label: "Empty workspaces"
        description: "Keep the first ones on the bar even without windows"
        model: [{key: 0, text: "Hide"}, {key: 5, text: "1–5"}, {key: 10, text: "1–10"}]
        current: ShellState.setting("workspaceSlots", 0)
        onActivated: key => ShellState.setSetting("workspaceSlots", key)
    }
    C.ChoiceRow {
        label: "Tray icons"
        description: "The rest open from the tray button"
        model: [{key: -1, text: "Auto", hint: "More on wider screens"}, {key: 0, text: "0"}, {key: 1, text: "1"}, {key: 2, text: "2"}, {key: 3, text: "3"}, {key: 5, text: "5"}]
        current: ShellState.setting("trayIcons", -1)
        onActivated: key => ShellState.setSetting("trayIcons", key)
    }
    C.ChoiceRow {
        label: "Battery percentage"
        description: "Low battery always shows it"
        model: [{key: "auto", text: "Auto", hint: "Hidden on narrow screens"}, {key: "always", text: "Always"}, {key: "never", text: "Never"}]
        current: ShellState.setting("batteryPercent", "auto")
        onActivated: key => ShellState.setSetting("batteryPercent", key)
    }
    C.SectionHeader {
        text: "Show the bar on"
        Layout.topMargin: Theme.gapM
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
                    ShellState.setSetting("hiddenOutputs", hidden.indexOf(modelData.name) < 0 ? hidden.concat([modelData.name]) : hidden.filter(n => n !== modelData.name));
                }
            }
        }
    }
}
