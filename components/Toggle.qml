import QtQuick
import QtQuick.Layouts
import "../core"

Button {
    id: root
    // Optional second line explaining what the switch does or its current state.
    property string description: ""
    // With a glyph the row becomes a header-style toggle (Wi-Fi, Bluetooth); positive adds a status dot.
    property bool positive: false
    // Flat inside a Group: no card of its own, only a hover highlight.
    implicitHeight: Math.max(glyph !== "" ? 64 : Theme.controlLarge + 4, toggleContent.implicitHeight + topPadding + bottomPadding)
    padding: Theme.gapM
    topPadding: Theme.gapS + 2
    bottomPadding: Theme.gapS + 2
    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: selected
    Accessible.description: description
    background: Rectangle {
        radius: root.flat ? Theme.radiusSmall : Theme.controlRadius
        color: root.hovered || root.visualFocus || root.down ? Theme.hover : root.flat ? "transparent" : Theme.surface
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }
    contentItem: RowLayout {
        // Named: contentItem is created late, and a binding through it doesn't see later size changes.
        id: toggleContent
        spacing: Theme.gapM
        GlyphTile {
            visible: root.glyph !== ""
            size: 38
            glyph: root.glyph
            positive: root.positive
            color: root.selected ? Theme.selection : Theme.raised
            opacity: root.enabled ? 1 : Theme.disabledOpacity
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Label {
                text: root.text
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.weight: root.glyph !== "" ? Font.DemiBold : Font.Normal
                color: root.enabled ? Theme.text : Theme.disabled
            }
            Label {
                visible: root.description !== ""
                text: root.description
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                // Header rows (with a glyph) keep status to one line; setting explanations may wrap.
                maximumLineCount: root.glyph !== "" ? 1 : 3
                elide: Text.ElideRight
                color: Theme.muted
                font.pixelSize: Theme.small
            }
        }
        Rectangle {
            Layout.preferredWidth: 34
            Layout.preferredHeight: 20
            radius: 10
            // The off track must stay visible on the hovered row background.
            color: root.selected ? Theme.accent : root.hovered || root.visualFocus || root.down ? Theme.raised : Theme.hover
            opacity: root.enabled ? 1 : Theme.disabledOpacity
            Behavior on color { ColorAnimation { duration: Theme.fast } }
            Rectangle {
                x: root.selected ? 17 : 3
                y: 3
                width: 14
                height: 14
                radius: 7
                color: root.selected ? Theme.background : Theme.muted
                Behavior on x { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }
            }
        }
    }
}
