import QtQuick
import QtQuick.Layouts
import "../core"

// One row of a list: glyph (or an app image), title, subtitle, a check when selected, and a trailing slot for
// buttons. Children go below the main line (a password field, a confirmation). Rows that only hold buttons set
// interactive: false so the row itself doesn't light up.
Button {
    id: root
    property string subtitle: ""
    property string image: ""
    property bool positive: false
    property bool interactive: true
    // Lists on a case (Find): no fill at rest, the subtitle on the title's line, the image inside the tile.
    property bool quiet: false
    property bool inline: false
    property bool tileImage: false
    // A trailing check marks the current choice in single-choice lists.
    property bool checkmark: selected
    property alias trailing: trailingRow.data
    default property alias details: detailColumn.data
    readonly property bool highlighted: interactive && (hovered || down || visualFocus)
    // While the row is hidden its children count as hidden too, so the slots below only judge themselves while
    // the row shows; otherwise a row that starts hidden would keep its slots hidden once it appears.
    function shows(slot) {
        return !root.visible || slot.visibleChildren.length > 0;
    }
    hoverEnabled: interactive
    focusPolicy: interactive ? Qt.StrongFocus : Qt.NoFocus
    implicitHeight: rowContent.implicitHeight + topPadding + bottomPadding
    padding: Theme.gapM - 2
    topPadding: 7
    bottomPadding: 7
    cornerRadius: Theme.radiusKey + 2
    // A whole row only gives a little under the pointer.
    scale: down && !Theme.reduced ? Theme.rowPressScale : 1
    pressDepth: 0
    // A module at rest; the chosen row is a raised neutral key.
    background: Rectangle {
        radius: root.cornerRadius
        color: root.quiet ? (root.highlighted && !root.selected ? root.wash : "transparent")
             : root.highlighted ? Theme.mix(Theme.module, Theme.text, 0.05) : Theme.module
        Behavior on color { ColorAnimation { duration: Theme.fast } }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Theme.raised
            opacity: root.selected && root.interactive ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
        }
        Raise {
            shown: root.selected && root.interactive
        }
    }
    contentItem: ColumnLayout {
        // Named: contentItem is created late, and a binding through it doesn't see later size changes.
        id: rowContent
        spacing: Theme.gapS
        opacity: root.enabled ? 1 : Theme.disabledOpacity
        RowLayout {
            Layout.fillWidth: true
            Layout.minimumHeight: 30
            spacing: Theme.gapM
            GlyphTile {
                size: 30
                color: selected ? Theme.accent : Theme.keyTile
                glyphColor: selected ? Theme.accentInk : Theme.textSecondary
                visible: root.image === "" || root.tileImage
                glyph: tileIcon.visible ? "" : root.glyph
                selected: root.selected && root.interactive
                positive: root.positive
                Image {
                    id: tileIcon
                    anchors.centerIn: parent
                    visible: root.tileImage && status === Image.Ready
                    source: root.tileImage ? root.image : ""
                    sourceSize.width: 20
                    sourceSize.height: 20
                    width: 20
                    height: 20
                    fillMode: Image.PreserveAspectFit
                }
            }
            Image {
                visible: root.image !== "" && !root.tileImage
                source: root.image
                sourceSize.width: 24
                sourceSize.height: 24
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                fillMode: Image.PreserveAspectFit
            }
            GridLayout {
                id: titles
                Layout.fillWidth: true
                columns: root.inline ? 2 : 1
                columnSpacing: Theme.gapS
                rowSpacing: 2
                Label {
                    text: root.text
                    color: Theme.text
                    font.weight: root.inline || root.selected && root.interactive ? Font.DemiBold : Font.Medium
                    Layout.fillWidth: !root.inline
                    // From the row's own width: bound to the grid's width, it laid the grid out again and again.
                    Layout.maximumWidth: root.inline ? root.availableWidth * 0.6 : Infinity
                }
                Label {
                    visible: root.subtitle !== ""
                    text: root.subtitle
                    color: Theme.textDim
                    font.pixelSize: root.inline ? Theme.label : Theme.small
                    Layout.fillWidth: true
                }
            }
            Icon {
                visible: root.checkmark
                name: "check"
                color: Theme.accentText
                Layout.rightMargin: trailingRow.visibleChildren.length ? 0 : 4
            }
            RowLayout {
                id: trailingRow
                visible: root.shows(trailingRow)
                spacing: Theme.gapXs
            }
        }
        ColumnLayout {
            id: detailColumn
            visible: root.shows(detailColumn)
            Layout.fillWidth: true
            spacing: Theme.gapS
        }
    }
}
