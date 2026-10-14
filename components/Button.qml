import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
// Qualified: QtQuick.Controls has its own Label, which would ignore the shell font and text size.
import "." as C

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
    property int labelSize: Theme.body
    property real cornerRadius: height > 42 ? Theme.controlRadius : Theme.radiusSmall
    // Label and glyph share one colour so state reads the same on both.
    readonly property color foreground: !enabled ? Theme.disabled : danger || tone === "danger" ? Theme.danger : tone === "warning" ? Theme.warning : accent ? Theme.background : selected ? Theme.accentText : Theme.text
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
            spacing: Theme.gapS
            C.Icon {
                visible: root.glyph !== ""
                name: root.glyph
                color: root.foreground
                Layout.alignment: Qt.AlignVCenter
            }
            C.Label {
                visible: root.text !== ""
                text: root.text
                font.pixelSize: root.labelSize
                color: root.foreground
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
    }
}
