import QtQuick
import "../core"

// Three small bars beside the chosen output; they move while something plays, and rest under reduced motion
// or power saving.
Row {
    id: levelBars
    property bool live: false
    spacing: 2
    height: 14
    Repeater {
        model: [0.55, 0.9, 0.7]
        Rectangle {
            id: levelBar
            required property real modelData
            required property int index
            property real level: modelData
            anchors.bottom: parent.bottom
            width: 3
            height: Math.max(3, 14 * level)
            radius: 1
            color: Theme.accent
            SequentialAnimation on level {
                running: levelBars.live && levelBars.visible && !Theme.reduced && !Theme.lowPower
                loops: Animation.Infinite
                onRunningChanged: if (!running) levelBar.level = levelBar.modelData
                NumberAnimation { to: 0.25; duration: 240 + levelBar.index * 60; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.9; duration: 300 + levelBar.index * 40; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.45; duration: 220 + levelBar.index * 50; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 280; easing.type: Easing.InOutSine }
            }
        }
    }
}
