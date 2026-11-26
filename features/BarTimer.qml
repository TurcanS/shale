import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "../components" as C

BarKey {
    id: timerButton
    // The bar this item is on: its screen, layout, weather and helpers.
    required property var bar
    readonly property var timer: Focus.nextTimer
    readonly property int remaining: timer ? Math.max(0, Math.ceil((timer.endsAt - Focus.now) / 1000)) : 0
    shown: !!timer
    leftPadding: 10
    rightPadding: 10
    hint: Focus.timers.map(t => (t.label || Focus.minutesText(t.seconds) + " timer") + " · " + Focus.clockText(Math.max(0, Math.ceil((t.endsAt - Focus.now) / 1000)))).join("\n") + "\nClick to cancel the first"
    tooltip: bar.tooltip
    Accessible.name: "Timer, " + Focus.clockText(remaining) + " left"
    onClicked: {
        const timer = timerButton.timer, left = timerButton.remaining;
        Focus.cancelTimer(timer.id);
        ShellState.message("Timer cancelled", "info", {label: "Undo", run: () => Focus.addTimer(left, timer.label)});
    }
    contentItem: RowLayout {
        spacing: 6
        C.Icon {
            name: "timer"
            size: 14
            color: timerButton.foreground
        }
        C.Label {
            text: Focus.clockText(timerButton.remaining)
            color: timerButton.foreground
            font.pixelSize: 12
            font.features: ({"tnum": 1})
            elide: Text.ElideNone
        }
    }
}
