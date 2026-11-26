import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../services"
import "../core/parts.js" as Parts

// Desktop widgets on one output: cards on the bottom layer, under every window, in the corner Settings → Desktop
// picks and in its order. The surface never takes the keyboard, and only the cards take the pointer. It is unmapped
// while a window on this output is fullscreen and while the session is locked, and so are the cards' clocks and
// samplers.
PanelWindow {
    id: root
    required property string outputName
    // The shown parts, in order (core/parts.js lists them, with their card files and widths).
    readonly property var cards: Parts.clean(ShellState.setting("widgetCards", Parts.defaults))
    readonly property string corner: ShellState.setting("widgetCorner", "bottom-left")
    readonly property bool atTop: corner.startsWith("top")
    readonly property bool atLeft: corner.endsWith("left")
    readonly property var monitor: Services.workspaces.find(w => w.monitor && w.monitor.name === root.outputName && w.active)
    readonly property bool fullscreen: !!monitor && monitor.hasFullscreen
    readonly property bool showing: cards.length > 0 && !fullscreen && !ShellState.locked
    // 24 px from the screen's edges (from the bar's, at the top), 12 px apart, with room on the open sides for the
    // cards' shadows.
    readonly property int edge: 24
    readonly property int gap: 12
    readonly property int room: 64
    readonly property int rowWidth: cards.reduce((sum, card) => sum + Parts.find(card).width, 0) + Math.max(0, cards.length - 1) * gap
    function offset(index) {
        let x = 0;
        for (let i = 0; i < index; i++)
            x += Parts.find(cards[i]).width + gap;
        return x;
    }
    visible: showing
    anchors {
        top: root.atTop
        bottom: !root.atTop
        left: root.atLeft
        right: !root.atLeft
    }
    implicitWidth: rowWidth + edge + room
    implicitHeight: 214 + edge + room
    color: "transparent"
    // Kept clear of the bar like a window, without asking windows to keep clear of the cards.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    WlrLayershell.namespace: "shale-widgets"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Clicks between and around the cards reach the desktop: one region per card, up to the six a desktop holds.
    mask: Region {
        Region { item: cardRow.count > 0 ? cardRow.itemAt(0) : null }
        Region { item: cardRow.count > 1 ? cardRow.itemAt(1) : null }
        Region { item: cardRow.count > 2 ? cardRow.itemAt(2) : null }
        Region { item: cardRow.count > 3 ? cardRow.itemAt(3) : null }
        Region { item: cardRow.count > 4 ? cardRow.itemAt(4) : null }
        Region { item: cardRow.count > 5 ? cardRow.itemAt(5) : null }
    }
    // Minutes are enough for every card; the clock stops with the surface.
    SystemClock {
        id: clock
        enabled: root.showing
        precision: SystemClock.Minutes
    }
    // The cards sit straight in the window, not in a row item, so the mask follows each card's own position when the
    // corner changes.
    readonly property int rowX: atLeft ? edge : room
    readonly property int rowY: atTop ? edge : room
    // Each part's card, loaded from its file. Cards take what they use of outputName, now (the minute clock) and
    // live (on screen, so samplers and tickers run).
    Repeater {
        id: cardRow
        model: root.cards
        Loader {
            id: part
            required property string modelData
            required property int index
            readonly property var spec: Parts.find(modelData)
            x: root.rowX + root.offset(index)
            y: root.rowY
            width: spec.width
            height: 214
            source: spec.source
            onLoaded: {
                const card = item as WidgetsCard;
                card.width = Qt.binding(() => part.width);
                card.outputName = Qt.binding(() => root.outputName);
                if ("now" in item)
                    item.now = Qt.binding(() => clock.date);
                if ("live" in item)
                    item.live = Qt.binding(() => root.showing);
            }
        }
    }
}
