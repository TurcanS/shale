import QtQuick
import QtQuick.Layouts
import "../core"

Button {
    id: root
    // Optional second line explaining what the switch does or its current state.
    property string description: ""
    // With a glyph the row becomes a header-style toggle (Wi-Fi, Bluetooth).
    property bool positive: false
    implicitHeight: Math.max(glyph !== "" ? 64 : 48, contentItem.implicitHeight + topPadding + bottomPadding)
    padding: 12
    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: selected
    Accessible.description: description
    background: Rectangle {
        radius: Theme.controlRadius
        color: root.hovered || root.visualFocus || root.down ? Theme.hover : Theme.surface
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }
    contentItem: RowLayout {
        spacing: 12
        Rectangle {
            visible: root.glyph !== ""
            Layout.preferredWidth: 38
            Layout.preferredHeight: 38
            radius: 11
            color: root.selected ? Theme.selection : Theme.raised
            opacity: root.enabled ? 1 : 0.45
            Behavior on color { ColorAnimation { duration: Theme.fast } }
            Icon {
                anchors.centerIn: parent
                name: root.glyph
                size: 18
            }
            Rectangle {
                visible: root.positive
                width: 7
                height: 7
                radius: 3.5
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                color: Theme.success
            }
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
            opacity: root.enabled ? 1 : 0.4
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
