import QtQuick
import QtQuick.Layouts
import "." as C

// Hold to put a page's settings back; it can be used again once the hold has finished.
C.HoldButton {
    id: root
    text: "Reset this page"
    glyph: "refresh"
    Layout.fillWidth: true
    onTriggeredChanged: if (triggered) rearm.restart()
    Timer {
        id: rearm
        interval: 900
        onTriggered: root.triggered = false
    }
}
