import QtQuick
import QtQuick.Layouts
import "../core"

// A 60 px quick tile: a module at rest; "on" is a raised neutral key and fills the glyph tile with the accent.
Button {
    id: root
    property string subtitle: ""
    // Split tiles: the body toggles, a trailing chevron segment opens details.
    property string detailHint: ""
    readonly property bool split: detailHint !== ""
    readonly property int detailWidth: 40
    signal detailRequested()
    // Turning on, the glyph tile warms up like an indicator lamp.
    onSelectedChanged: if (selected) lamp.flash()
    // Hovering the chevron segment must not also light up the body it doesn't act on.
    readonly property bool bodyActive: root.down || root.visualFocus || (root.hovered && !(split && detailButton.hovered))
    implicitHeight: Math.max(60, tileContent.implicitHeight + topPadding + bottomPadding)
    cornerRadius: Theme.radiusCard + 2
    padding: Theme.gapM
    topPadding: Theme.gapS
    bottomPadding: Theme.gapS
    rightPadding: split ? detailWidth + Theme.gapS : Theme.gapM
    background: Rectangle {
        radius: root.cornerRadius
        color: root.selected ? Theme.raised : root.bodyActive ? Theme.mix(Theme.module, Theme.text, 0.05) : Theme.module
        Behavior on color { ColorAnimation { duration: Theme.fast } }
        Raise {
            shown: root.selected
        }
        // Hover on an "on" tile: a light wash over the raised key.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: root.selected
            color: Theme.keyWash(root.down)
            opacity: root.bodyActive ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
        }
    }
    contentItem: RowLayout {
        // Named: contentItem is created late, and a binding through it doesn't see later size changes.
        id: tileContent
        opacity: root.enabled ? 1 : Theme.disabledOpacity
        spacing: Theme.gapM
        GlyphTile {
            size: 36
            glyph: root.glyph
            selected: root.selected
            WarmUp {
                id: lamp
                anchors.fill: parent
                radius: parent.radius
                peak: 0.4
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Label {
                text: root.text
                font.pixelSize: Theme.body
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }
            Label {
                visible: root.subtitle !== ""
                text: root.subtitle
                color: root.selected ? Theme.mix(Theme.textSecondary, Theme.text, 0.4) : Theme.textDim
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
        scale: 1
        pressDepth: 0
        onClicked: root.detailRequested()
        // A translucent tint reads correctly on both the neutral and the selected tile colors.
        background: Rectangle {
            radius: root.cornerRadius
            topLeftRadius: 0
            bottomLeftRadius: 0
            color: Theme.text
            opacity: detailButton.down ? 0.12 : detailButton.hovered || detailButton.visualFocus ? 0.06 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
        }
        contentItem: Item {
            Icon {
                anchors.centerIn: parent
                name: "chevron"
                size: 16
                color: root.selected ? Theme.accentText : Theme.text
                opacity: detailButton.hovered || detailButton.visualFocus ? 1 : 0.7
                Behavior on opacity { NumberAnimation { duration: Theme.fast } }
            }
        }
    }
}
