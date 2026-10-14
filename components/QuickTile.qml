import QtQuick
import QtQuick.Layouts
import "../core"

Button {
    id: root
    property string subtitle: ""
    // Split tiles: the body toggles, a trailing chevron segment opens details.
    property string detailHint: ""
    readonly property bool split: detailHint !== ""
    readonly property int detailWidth: 40
    signal detailRequested()
    // Hovering the chevron segment must not also light up the body it doesn't act on.
    readonly property bool bodyActive: root.down || root.visualFocus || (root.hovered && !(split && detailButton.hovered))
    implicitHeight: Math.max(78, tileContent.implicitHeight + topPadding + bottomPadding)
    padding: Theme.gapM
    rightPadding: split ? detailWidth + Theme.gapS : Theme.gapM
    background: Rectangle {
        radius: Theme.controlRadius
        color: root.selected ? (root.bodyActive ? Theme.selectionHover : Theme.selection) : root.bodyActive ? Theme.hover : Theme.surface
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }
    contentItem: RowLayout {
        // Named: contentItem is created late, and a binding through it doesn't see later size changes.
        id: tileContent
        opacity: root.enabled ? 1 : Theme.disabledOpacity
        spacing: Theme.gapS + 2
        GlyphTile {
            glyph: root.glyph
            selected: root.selected
            glyphColor: root.selected ? Theme.accentText : Theme.text
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Label {
                text: root.text
                color: root.selected ? Theme.accentText : Theme.text
                font.pixelSize: Theme.label
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }
            Label {
                visible: root.subtitle !== ""
                text: root.subtitle
                color: Theme.muted
                font.pixelSize: Theme.small
                Layout.fillWidth: true
            }
        }
    }
    // Hairline between the two targets; hidden while either side is highlighted.
    Rectangle {
        visible: root.split
        x: root.width - root.detailWidth
        anchors.verticalCenter: parent.verticalCenter
        width: 1
        height: parent.height * 0.46
        color: Theme.text
        opacity: detailButton.hovered || detailButton.down || root.bodyActive ? 0 : 0.10
        Behavior on opacity { NumberAnimation { duration: Theme.fast } }
    }
    Button {
        id: detailButton
        visible: root.split
        enabled: root.split
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.detailWidth
        glyph: "chevron"
        hint: root.detailHint
        padding: 0
        onClicked: root.detailRequested()
        // A translucent tint reads correctly on both the neutral and the selected tile colors.
        background: Rectangle {
            radius: Theme.controlRadius
            topLeftRadius: 0
            bottomLeftRadius: 0
            color: Theme.text
            opacity: detailButton.down ? 0.14 : detailButton.hovered || detailButton.visualFocus ? 0.08 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
        }
        contentItem: Item {
            Icon {
                anchors.centerIn: parent
                name: "chevron"
                size: 16
                opacity: detailButton.hovered || detailButton.visualFocus ? 1 : 0.7
                Behavior on opacity { NumberAnimation { duration: Theme.fast } }
            }
        }
    }
}
