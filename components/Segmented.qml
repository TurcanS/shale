import QtQuick
import QtQuick.Layouts
import "../core"

// A single choice among a few options: [{key, text, glyph?, hint?}]. Arrow keys move the choice.
Rectangle {
    id: root
    property var model: []
    property var current: null
    // Equal-width segments that fill the row, or segments sized to their labels.
    property bool fill: true
    property int segmentHeight: Theme.controlHeight
    property color trackColor: Theme.surface
    signal activated(var key)
    implicitWidth: row.implicitWidth + 6
    implicitHeight: segmentHeight
    Layout.fillWidth: fill
    radius: segmentHeight > 30 ? Theme.radiusSmall + 2 : Theme.radiusSmall
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
    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: 3
        spacing: 2
        Repeater {
            id: segments
            model: root.model
            Button {
                required property var modelData
                required property int index
                text: modelData.text || ""
                glyph: modelData.glyph || ""
                hint: modelData.hint || ""
                flat: true
                selected: root.current === modelData.key
                cornerRadius: root.radius - 2
                implicitHeight: root.segmentHeight - 6
                padding: root.segmentHeight > 30 ? 10 : 8
                labelSize: root.segmentHeight > 30 ? Theme.body : Theme.small
                Layout.fillWidth: root.fill
                Layout.preferredWidth: root.fill ? 1 : implicitWidth
                Layout.fillHeight: true
                Accessible.name: modelData.accessibleName || text || hint
                Accessible.role: Accessible.RadioButton
                Accessible.checkable: true
                Accessible.checked: selected
                Keys.onLeftPressed: root.step(index, -1)
                Keys.onRightPressed: root.step(index, 1)
                onClicked: root.activated(modelData.key)
            }
        }
    }
}
