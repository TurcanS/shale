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
    // A trailing check marks the current choice in single-choice lists.
    property bool checkmark: selected
    property alias trailing: trailingRow.data
    default property alias details: detailColumn.data
    readonly property bool highlighted: interactive && (hovered || down || visualFocus)
    hoverEnabled: interactive
    focusPolicy: interactive ? Qt.StrongFocus : Qt.NoFocus
    implicitHeight: rowContent.implicitHeight + topPadding + bottomPadding
    padding: Theme.gapM - 2
    topPadding: Theme.gapS
    bottomPadding: Theme.gapS
    background: Rectangle {
        radius: Theme.controlRadius
        color: root.selected && root.interactive ? (root.highlighted ? Theme.selectionHover : Theme.selection) : root.highlighted ? Theme.hover : Theme.surface
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }
    contentItem: ColumnLayout {
        // Named: contentItem is created late, and a binding through it doesn't see later size changes.
        id: rowContent
        spacing: Theme.gapS
        opacity: root.enabled ? 1 : Theme.disabledOpacity
        RowLayout {
            Layout.fillWidth: true
            Layout.minimumHeight: 36
            spacing: Theme.gapM
            GlyphTile {
                visible: root.image === ""
                glyph: root.glyph
                selected: root.selected && root.interactive
                positive: root.positive
            }
            Image {
                visible: root.image !== ""
                source: root.image
                sourceSize.width: 24
                sourceSize.height: 24
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                fillMode: Image.PreserveAspectFit
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label {
                    text: root.text
                    color: root.selected && root.interactive ? Theme.accentText : Theme.text
                    font.weight: Font.Medium
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
            Icon {
                visible: root.checkmark
                name: "check"
                color: Theme.accentText
                Layout.rightMargin: trailingRow.visibleChildren.length ? 0 : 4
            }
            RowLayout {
                id: trailingRow
                visible: visibleChildren.length > 0
                spacing: Theme.gapXs
            }
        }
        ColumnLayout {
            id: detailColumn
            visible: visibleChildren.length > 0
            Layout.fillWidth: true
            spacing: Theme.gapS
        }
    }
}
