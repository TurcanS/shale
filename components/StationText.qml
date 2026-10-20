import QtQuick
import "../core"

// The small stamped capitals that name every instrument and reading.
Text {
    font.family: Theme.instrument
    font.pixelSize: Theme.caption
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 1.6
    color: Theme.muted
}
