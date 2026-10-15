import QtQuick
import QtQuick.Layouts
import "../core"
import "." as C

// Hold to put a page's settings back; it can be used again once the hold has finished.
C.HoldButton {
    id: root
    text: "Reset this page"
    glyph: "refresh"
    Layout.fillWidth: true
    implicitHeight: Math.max(62, Theme.body * 2 + 30)
    topPadding: Theme.gapS
    bottomPadding: 20
    onTriggeredChanged: if (triggered) rearm.restart()
    Timer {
        id: rearm
        interval: 900
        onTriggered: root.triggered = false
    }
}
