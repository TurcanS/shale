import QtQuick
import QtQuick.Layouts
import "../core"

// The one heading style inside panels. Children (a "Clear" or "Refresh" button) line up on the right; only then does
// the row take a button's height, so a plain title sits as close to its group as the text allows.
RowLayout {
    id: root
    property alias text: label.text
    Layout.fillWidth: true
    Layout.minimumHeight: children.length > 1 ? Theme.controlSmall : 0
    spacing: Theme.gapS
    Label {
        id: label
        color: Theme.textMuted
        font.pixelSize: Theme.label
        font.weight: Font.DemiBold
        Layout.fillWidth: true
        Accessible.role: Accessible.Heading
    }
}
