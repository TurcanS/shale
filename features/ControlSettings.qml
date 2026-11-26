import QtQuick
import QtQuick.Layouts
import "../core"
import "../core/controlItems.js" as ControlItems
import "../components" as C

// Settings → Control: the order of its tiles and buttons, and which parts it shows.
ColumnLayout {
    id: root
    spacing: 8
    readonly property var setting: ShellState.setting("controlLayout", {})
    readonly property var arrangement: ControlItems.layout(setting)
    function save(value) {
        ShellState.setSetting("controlLayout", value);
    }
    // One reorderable entry of a part ("tiles" or "footer"): handle, glyph, name and line, earlier and later, switch.
    component Entry: C.OrderRow {
        id: entry
        required property var modelData
        required property int index
        property string part: ""
        property Item group: null
        property var entries: []
        readonly property var item: ControlItems.find(entry.part === "tiles" ? ControlItems.tiles : ControlItems.footer, entry.modelData.id) || ({})
        readonly property int shownCount: entry.entries.filter(other => other.shown).length
        itemId: entry.modelData.id
        glyph: entry.item.icon || "grid"
        label: entry.item.title || ""
        description: entry.item.required ? "Always shown" : entry.item.description || ""
        labelWidth: Math.max(150, Theme.body * 11)
        shown: entry.modelData.shown
        locked: !!entry.item.required
        // Hidden entries sit after the shown ones; they keep no place of their own.
        draggable: entry.shown
        canEarlier: entry.shown && entry.index > 0
        canLater: entry.shown && entry.index < entry.shownCount - 1
        onMoved: step => root.save(ControlItems.changed(root.setting, entry.part, entry.modelData.id, step))
        onToggled: root.save(ControlItems.changed(root.setting, entry.part, entry.modelData.id, 0, !entry.modelData.shown))
        onDragStarted: {
            dropLine.targets = [{key: entry.part, group: entry.group}];
            dropLine.row = entry;
        }
        // Saved once the drag has finished, since the change rebuilds these rows.
        onDropped: {
            const drop = dropLine.drop;
            if (drop && drop.index !== entry.index)
                Qt.callLater(root.save, ControlItems.changed(root.setting, entry.part, entry.modelData.id, drop.index - entry.index));
        }
        onDraggingChanged: if (!entry.dragging) dropLine.row = null
    }
    C.SectionHeader { text: "Tiles" }
    C.Caption {
        text: "Two to a row, in this order; drag a tile by its handle or move it with the arrows. Tiles for hardware this computer lacks stay out of sight."
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    C.Group {
        id: tilesGroup
        Repeater {
            model: root.arrangement.tiles
            Entry {
                part: "tiles"
                group: tilesGroup
                entries: root.arrangement.tiles
            }
        }
    }
    C.SectionHeader {
        text: "Below the tiles"
        Layout.topMargin: 2
    }
    C.Group {
        Repeater {
            model: ControlItems.sections
            C.Toggle {
                required property var modelData
                Layout.fillWidth: true
                flat: true
                text: modelData.title
                description: modelData.description || ""
                selected: root.arrangement.sections[modelData.id]
                onClicked: root.save(ControlItems.section(root.setting, modelData.id, !selected))
            }
        }
    }
    C.SectionHeader {
        text: "Buttons"
        Layout.topMargin: 2
    }
    C.Group {
        id: footerGroup
        Repeater {
            model: root.arrangement.footer
            Entry {
                part: "footer"
                group: footerGroup
                entries: root.arrangement.footer
            }
        }
    }
    C.Group {
        Layout.topMargin: 4
        C.SettingRow {
            label: "Control"
            description: "See the arrangement in place"
            C.Button {
                text: "Open Control"
                glyph: "sliders"
                implicitHeight: 32
                onClicked: ShellState.open("control")
            }
        }
    }
    C.DropLine {
        id: dropLine
        Layout.topMargin: -root.spacing
    }
}
