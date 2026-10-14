import QtQuick
import QtQuick.Layouts
import "../core"

// The one heading style inside panels. Children (a "Clear" or "Refresh" button) line up on the right.
RowLayout {
    id: root
    property alias text: label.text
    Layout.fillWidth: true
    Layout.minimumHeight: Theme.controlSmall
    spacing: Theme.gapS
    Label {
        id: label
        color: Theme.muted
        font.pixelSize: Theme.small
        font.weight: Font.Medium
        Layout.fillWidth: true
        Accessible.role: Accessible.Heading
    }
}
