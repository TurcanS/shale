import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"

AbstractButton {
    id: root
    property string glyph: ""
    property string hint: ""
    // A Tooltip that shows `hint` while the pointer rests here; for icon-only controls outside panels.
    property var tooltip: null
    property bool selected: false
    property bool danger: false
    property bool flat: false
    property bool accent: false
    // Optional status tint for the label: "warning" or "danger".
    property string tone: ""
    property real cornerRadius: height > 42 ? Theme.controlRadius : 8
    implicitWidth: Math.max(28, contentItem.implicitWidth + leftPadding + rightPadding)
    implicitHeight: Theme.controlHeight
    Layout.minimumWidth: 0
    padding: 10
    topPadding: 4
    bottomPadding: 4
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    Accessible.name: text || hint
    Accessible.role: Accessible.Button
    onHoveredChanged: if (tooltip) hovered ? tooltip.show(root) : tooltip.hide(root, false)
    onPressedChanged: if (tooltip && pressed) tooltip.hide(root, true)
    scale: Theme.reduced ? 1 : down ? 0.98 : 1
    Behavior on scale {
        NumberAnimation {
            duration: Theme.fast
            easing.type: Easing.OutCubic
        }
    }
    background: Rectangle {
        radius: root.cornerRadius
        color: !root.enabled ? (root.flat ? "transparent" : Theme.surface) : root.accent ? (root.hovered || root.visualFocus ? Theme.accentHover : Theme.accent) : root.selected ? (root.hovered || root.down || root.visualFocus ? Theme.selectionHover : Theme.selection) : (root.hovered || root.down || root.visualFocus ? Theme.hover : (root.flat ? "transparent" : Theme.raised))
        border.width: 0
        Behavior on color {
            ColorAnimation {
                duration: Theme.fast
            }
        }
    }
    // Keyboard focus only (visualFocus is false for mouse clicks), so there are still no click outlines.
    Rectangle {
        anchors.fill: parent
        z: 10
        visible: root.visualFocus
        color: "transparent"
        radius: root.background && root.background.radius !== undefined ? root.background.radius : root.cornerRadius
        border.width: 1.5
        border.color: Theme.accent
    }
    contentItem: Item {
        implicitWidth: contents.implicitWidth
        implicitHeight: contents.implicitHeight
        RowLayout {
            id: contents
            anchors.centerIn: parent
            width: Math.min(parent.width, implicitWidth)
            spacing: 8
            Icon {
                visible: root.glyph !== ""
                name: root.glyph
                size: 16
                opacity: root.enabled ? 1 : 0.35
                invert: root.enabled && root.accent
                Layout.alignment: Qt.AlignVCenter
            }
            Label {
                visible: root.text !== ""
                text: root.text
                color: !root.enabled ? Theme.disabled : root.danger || root.tone === "danger" ? Theme.danger : root.tone === "warning" ? Theme.warning : root.accent ? Theme.background : root.selected ? Theme.accentText : Theme.text
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
    }
}
