import QtQuick
import QtQuick.Layouts
import "../core"

// A single choice among a few options: [{key, text, glyph?, hint?}]. Arrow keys move the choice. A module-coloured
// track (set trackColor to Theme.well inside a module); the chosen option is a raised key that slides between options.
Rectangle {
    id: root
    property var model: []
    property var current: null
    // Equal-width segments that fill the row, or segments sized to their labels.
    property bool fill: true
    // With fill, size the segments to their labels instead of equally, so long labels keep their room.
    property bool proportional: false
    property int segmentHeight: Theme.controlHeight
    property color trackColor: Theme.module
    signal activated(var key)
    readonly property int currentIndex: {
        const list = root.model || [];
        for (let i = 0; i < list.length; i++) {
            if (list[i].key === root.current)
                return i;
        }
        return -1;
    }
    readonly property Item currentItem: currentIndex >= 0 && segments.count === (root.model || []).length ? segments.itemAt(currentIndex) : null
    // Equal segments share the widest label's width (with a little room), so none of them elides.
    readonly property real widest: {
        let widest = 0;
        for (let i = 0; i < segments.count; i++) {
            const item = segments.itemAt(i) as Button;
            if (item)
                widest = Math.max(widest, item.implicitContentWidth + 12);
        }
        return widest;
    }
    implicitWidth: row.implicitWidth + 6
    implicitHeight: segmentHeight
    Layout.fillWidth: fill
    radius: segmentHeight > 30 ? Theme.radiusKey : Theme.radiusSegment + 1
    color: trackColor
    Accessible.role: Accessible.Grouping
    function step(index, delta) {
        const next = Math.max(0, Math.min(segments.count - 1, index + delta));
        const item = segments.itemAt(next);
        if (next === index || !item || !item.enabled)
            return;
        item.forceActiveFocus(Qt.TabFocusReason);
        root.activated(root.model[next].key);
    }
    // The chosen option, drawn once under the labels so it can slide; a 1 px darker edge below stands in for its
    // small drop shadow.
    Item {
        id: indicator
        readonly property bool placed: !!root.currentItem && root.currentItem.width > 0
        // Slides only between options, so it doesn't fly in from the corner when the control first lays out.
        property bool settled: false
        // Where the selector is headed; it stops against the track's ends rather than run past them.
        property real slide: placed ? row.x + root.currentItem.x : 0
        x: Math.max(row.x, Math.min(slide, row.x + row.width - width))
        y: placed ? row.y + root.currentItem.y : 0
        width: placed ? root.currentItem.width : 0
        height: placed ? root.currentItem.height : 0
        visible: placed
        onPlacedChanged: if (placed) Qt.callLater(() => indicator.settled = true)
        // A selector clicking over: it holds, snaps past the middle and settles (plain slide under Calm).
        Detent on slide {
            enabled: indicator.settled
            overshoot: 0.5
        }
        Detent on width {
            enabled: indicator.settled
            overshoot: 0
        }
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 1
            anchors.bottomMargin: -1
            radius: root.radius - 3
            color: Qt.rgba(0, 0, 0, 0.4)
        }
        Rectangle {
            anchors.fill: parent
            radius: root.radius - 3
            color: Theme.keySelected
        }
    }
    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: 3
        spacing: 2
        Repeater {
            id: segments
            model: root.model
            Button {
                id: segment
                required property var modelData
                required property int index
                text: modelData.text || ""
                glyph: modelData.glyph || ""
                hint: modelData.hint || ""
                flat: true
                pressDepth: 0
                selected: root.current === modelData.key
                cornerRadius: root.radius - 3
                implicitHeight: root.segmentHeight - 6
                padding: root.segmentHeight > 30 ? 12 : 10
                labelSize: root.segmentHeight > 36 ? Theme.label : Theme.small
                // White on the chosen option, quiet on the others until hovered.
                foreground: !enabled ? Theme.textFaint : selected ? "#ffffff" : hovered || visualFocus ? Theme.text : Theme.textMuted
                glyphColor: foreground
                Layout.fillWidth: root.fill
                Layout.preferredWidth: root.fill && !root.proportional ? root.widest : implicitWidth
                // Never narrower than the label, so a large text size widens the control instead of eliding it.
                Layout.minimumWidth: root.fill && !root.proportional ? root.widest : implicitContentWidth + 12
                Layout.fillHeight: true
                Accessible.name: modelData.accessibleName || text || hint
                Accessible.role: Accessible.RadioButton
                Accessible.checkable: true
                Accessible.checked: selected
                // One Tab stop for the whole control, on the chosen option (the first when none is); the arrows
                // move between options.
                focusPolicy: activeFocus || index === Math.max(0, root.currentIndex) ? Qt.StrongFocus : Qt.ClickFocus
                Keys.onLeftPressed: root.step(index, -1)
                Keys.onRightPressed: root.step(index, 1)
                onClicked: root.activated(modelData.key)
                background: Rectangle {
                    radius: segment.cornerRadius
                    color: Theme.rowWash(segment.down)
                    opacity: !segment.selected && (segment.hovered || segment.down) ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                }
            }
        }
    }
}
