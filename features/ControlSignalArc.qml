import QtQuick
import QtQuick.Shapes
import "../core"

// One arc of the Wi-Fi strength glyph, in the icon set's 24-unit box.
ShapePath {
    id: arc
    property string d: ""
    property bool lit: true
    property color color: Theme.text
    scale: Qt.size(18 / 24, 18 / 24)
    strokeWidth: 1.5
    strokeColor: lit ? color : Theme.mix(Theme.module, Theme.text, 0.18)
    fillColor: "transparent"
    capStyle: ShapePath.RoundCap
    PathSvg { path: arc.d }
}
