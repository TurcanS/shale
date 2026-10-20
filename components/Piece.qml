import QtQuick
import QtQuick.Layouts
import "../core"

// One part of a panel that rises into place in order while it opens.
Item {
    id: piece
    // Whether the panel is opening; the part follows it.
    property bool opening: false
    property int order: 0
    // Each piece rises 6 px in order while opening, about 30 ms apart, and all fade together when closing. An
    // animation of its own (not a formula of progress) lets a reversal carry on from where each piece is.
    property real shown: piece.opening ? 1 : 0
    Behavior on shown {
        id: rise
        SequentialAnimation {
            PauseAnimation {
                duration: rise.targetValue < 1 || Theme.reduced ? 0 : (Theme.lowPower ? 80 + 15 * piece.order : 160 + 30 * piece.order)
            }
            NumberAnimation {
                duration: rise.targetValue < 1 ? Theme.fast : Theme.enter
                easing.type: Easing.OutCubic
            }
        }
    }
    Layout.fillWidth: true
    opacity: shown
    transform: Translate { y: Theme.reduced ? 0 : (1 - piece.shown) * 6 }
}
