import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C
import "../core/parts.js" as Parts

// Settings → Desktop: the widget cards under your windows, which of them show (up to six), their order and the corner
// they sit in. Off until turned on here.
ColumnLayout {
    id: root
    spacing: 8
    readonly property var cards: Parts.parts
    readonly property int maxCards: Parts.maximum
    readonly property var shownCards: Parts.clean(ShellState.setting("widgetCards", Parts.defaults))
    // The set saved as Mine, and the layout the shown cards make ("" when they match none).
    readonly property var savedCards: Parts.clean(ShellState.setting("widgetSaved", []))
    readonly property string layout: Parts.layoutOf(shownCards, savedCards)
    // The shown cards in their order, then the hidden ones in their usual order.
    readonly property var entries: shownCards.map(id => ({id: id, shown: true}))
        .concat(cards.filter(card => shownCards.indexOf(card.id) < 0).map(card => ({id: card.id, shown: false})))
    readonly property bool enabledWidgets: ShellState.setting("widgets", false)
    function save(list) {
        ShellState.setSetting("widgetCards", list.slice(0, maxCards));
    }
    function move(id, step) {
        const list = shownCards.slice();
        const from = list.indexOf(id);
        const to = Math.max(0, Math.min(list.length - 1, from + step));
        if (from < 0 || to === from)
            return;
        list.splice(from, 1);
        list.splice(to, 0, id);
        save(list);
    }
    // Shown again, a card goes to the end of the row; a full row takes no more.
    function toggle(id) {
        if (shownCards.indexOf(id) >= 0)
            save(shownCards.filter(other => other !== id));
        else if (shownCards.length < maxCards)
            save(shownCards.concat([id]));
        else
            ShellState.message("The desktop holds " + maxCards + " cards. Hide one to show another.", "info");
    }
    function useLayout(key) {
        const layout = Parts.layouts.find(item => item.id === key);
        save(key === "mine" ? savedCards : layout ? layout.cards : shownCards);
    }
    C.Group {
        C.Toggle {
            Layout.fillWidth: true
            flat: true
            text: "Widgets"
            description: "Cards on the desktop, under your windows. They hide while a window is fullscreen."
            selected: root.enabledWidgets
            onClicked: ShellState.setSetting("widgets", !root.enabledWidgets)
        }
        C.ChoiceRow {
            settingKey: "widgetCorner"
            label: "Corner"
            description: "Where the cards sit; at the top they stay under the bar"
            stacked: true
            model: [{key: "top-left", text: "Top left"}, {key: "top-right", text: "Top right"},
                    {key: "bottom-left", text: "Bottom left"}, {key: "bottom-right", text: "Bottom right"}]
            current: ShellState.setting("widgetCorner", "bottom-left")
            onActivated: key => ShellState.setSetting("widgetCorner", key)
        }
    }
    C.SectionHeader {
        text: "Layouts"
        Layout.topMargin: 2
    }
    // Ready-made sets of cards, and your own. Find switches them too: layout evening.
    C.Group {
        C.ChoiceRow {
            label: "Layout"
            description: root.layout === "" ? "Your cards match no layout; save them as Mine to keep them"
                : root.layout === "mine" ? "Your saved set" : Parts.layouts.find(item => item.id === root.layout).description
            stacked: true
            model: Parts.layouts.map(item => ({key: item.id, text: item.title}))
                .concat(root.savedCards.length ? [{key: "mine", text: "Mine"}] : [])
            current: root.layout
            onActivated: key => root.useLayout(key)
        }
        C.SettingRow {
            label: "Mine"
            description: root.savedCards.length ? root.savedCards.map(id => Parts.find(id).title).join(", ") : "Nothing saved yet"
            C.Button {
                text: root.layout === "mine" ? "Saved" : "Save these cards"
                enabled: root.shownCards.length > 0 && root.layout !== "mine"
                implicitHeight: 32
                onClicked: ShellState.setSetting("widgetSaved", root.shownCards)
            }
        }
    }
    C.SectionHeader {
        text: "Cards"
        Layout.topMargin: 2
    }
    C.Caption {
        text: "Side by side in this order, up to " + root.maxCards + "; drag a card by its handle or move it with the arrows."
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    C.Group {
        id: cardsGroup
        Repeater {
            model: root.entries
            C.OrderRow {
                id: entry
                required property var modelData
                required property int index
                readonly property var card: root.cards.find(card => card.id === entry.modelData.id) || ({})
                itemId: entry.modelData.id
                glyph: entry.card.icon || "widgets"
                label: entry.card.title || ""
                description: entry.card.description || ""
                labelWidth: Math.max(110, Theme.body * 8)
                shown: entry.modelData.shown
                // Hidden cards sit after the shown ones; they keep no place of their own.
                draggable: entry.shown
                canEarlier: entry.shown && entry.index > 0
                canLater: entry.shown && entry.index < root.shownCards.length - 1
                onMoved: step => root.move(entry.modelData.id, step)
                onToggled: root.toggle(entry.modelData.id)
                onDragStarted: {
                    dropLine.targets = [{key: "cards", group: cardsGroup}];
                    dropLine.row = entry;
                }
                // Saved once the drag has finished, since the change rebuilds these rows.
                onDropped: {
                    const drop = dropLine.drop;
                    if (drop && drop.index !== entry.index)
                        Qt.callLater(root.move, entry.modelData.id, drop.index - entry.index);
                }
                onDraggingChanged: if (!entry.dragging) dropLine.row = null
            }
        }
    }
    C.DropLine {
        id: dropLine
        Layout.topMargin: -root.spacing
    }
}
