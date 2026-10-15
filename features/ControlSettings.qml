import QtQuick
import QtQuick.Layouts
import "../core"
import "../core/controlItems.js" as ControlItems
import "../components" as C

// Settings → Control center: the order of its tiles and buttons, and which parts it shows.
ColumnLayout {
    id: root
    spacing: Theme.gapM
    readonly property var setting: ShellState.setting("controlLayout", {})
    readonly property var arrangement: ControlItems.layout(setting)
    function save(value) {
        ShellState.setSetting("controlLayout", value);
    }
    // One reorderable entry: its switch, then earlier and later.
    component Entry: RowLayout {
        id: entry
        property var item: ({})
        property bool shown: true
        property bool first: false
        property bool last: false
        signal toggled()
        signal moved(int step)
        Layout.fillWidth: true
        spacing: Theme.gapXs
        C.Toggle {
            Layout.fillWidth: true
            flat: true
            text: entry.item.title || ""
            description: entry.item.required ? "Always shown" : entry.item.description || ""
            enabled: !entry.item.required
            selected: entry.shown
            onClicked: entry.toggled()
        }
        C.Button {
            glyph: "chevron"
            rotation: -90
            flat: true
            // Hidden entries sit after the shown ones; they keep no place of their own.
            enabled: !entry.first && entry.shown
            hint: "Move " + (entry.item.title || "") + " earlier"
            implicitWidth: 30
            implicitHeight: 30
            onClicked: entry.moved(-1)
        }
        C.Button {
            glyph: "chevron"
            rotation: 90
            flat: true
            enabled: !entry.last && entry.shown
            hint: "Move " + (entry.item.title || "") + " later"
            implicitWidth: 30
            implicitHeight: 30
            Layout.rightMargin: Theme.gapS
            onClicked: entry.moved(1)
        }
    }
    C.SectionHeader {
        text: "Tiles"
        Layout.topMargin: Theme.gapS
    }
    C.Caption {
        text: "Two to a row, in this order. Tiles for hardware this computer lacks stay out of sight."
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    C.Group {
        Repeater {
            model: root.arrangement.tiles
            Entry {
                required property var modelData
                required property int index
                item: ControlItems.find(ControlItems.tiles, modelData.id)
                shown: modelData.shown
                first: index === 0
                last: index === root.arrangement.tiles.filter(entry => entry.shown).length - 1
                onToggled: root.save(ControlItems.changed(root.setting, "tiles", modelData.id, 0, !modelData.shown))
                onMoved: step => root.save(ControlItems.changed(root.setting, "tiles", modelData.id, step))
            }
        }
    }
    C.SectionHeader {
        text: "Below the tiles"
        Layout.topMargin: Theme.gapS
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
        Layout.topMargin: Theme.gapS
    }
    C.Group {
        Repeater {
            model: root.arrangement.footer
            Entry {
                required property var modelData
                required property int index
                item: ControlItems.find(ControlItems.footer, modelData.id)
                shown: modelData.shown
                first: index === 0
                last: index === root.arrangement.footer.filter(entry => entry.shown).length - 1
                onToggled: root.save(ControlItems.changed(root.setting, "footer", modelData.id, 0, !modelData.shown))
                onMoved: step => root.save(ControlItems.changed(root.setting, "footer", modelData.id, step))
            }
        }
    }
    C.Button {
        text: "Open control center"
        glyph: "settings"
        Layout.fillWidth: true
        onClicked: ShellState.open("control")
    }
}
