import QtQuick
import "../core"

// A dot-matrix reading, such as the station clock or a countdown.
Text {
    font.family: Theme.readout
    font.pixelSize: Theme.barText
    color: Theme.text
    verticalAlignment: Text.AlignVCenter
}
