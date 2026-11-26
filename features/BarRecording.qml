import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

BarLiveChip {
    id: recordingChip
    // The bar this item is on: its screen, layout, weather and helpers.
    required property var bar
    readonly property string elapsed: Math.floor(ShellState.recordingSeconds / 60) + ":" + String(ShellState.recordingSeconds % 60).padStart(2, "0")
    shown: ShellState.recording.active
    text: "Recording " + elapsed
    hint: "Stop recording"
    tooltip: bar.tooltip
    onClicked: ShellState.action("stop-recording")
    contentItem: RowLayout {
        spacing: 6
        C.Icon {
            id: dot
            name: "record"
            size: 12
            color: Theme.accentText
            // A recording LED: a short blink, a long glow.
            SequentialAnimation on opacity {
                running: recordingChip.shown && !Motion.calm && recordingChip.bar.onScreen
                loops: Animation.Infinite
                NumberAnimation { to: 0.3; duration: 140; easing.type: Easing.OutQuad }
                PauseAnimation { duration: 260 }
                NumberAnimation { to: 1; duration: 140; easing.type: Easing.OutQuad }
                PauseAnimation { duration: 900 }
                onStopped: dot.opacity = 1
            }
        }
        // Tabular digits keep the chip from jittering every second.
        C.Label {
            text: recordingChip.elapsed
            color: Theme.accentText
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.features: ({"tnum": 1})
            elide: Text.ElideNone
        }
    }
}
