pragma ComponentBehavior: Bound
import QtQuick
import "../core"
import "../services"

// The day's target as five segments along the top of the capsule (the Line holds the bottom); a segment lights as orders
// are cleared. Hidden when targets are off (daily target 0), on a day off, and while presenting.
Row {
    id: meter
    readonly property var m: Day.momentum
    readonly property int lit: m && m.target > 0 ? Math.floor(Math.min(m.cleared, m.target) * 5 / m.target) : 0
    visible: ShellState.setting("capsuleMeter", true) && Day.targets && !!m && !m.dayOff && !ShellState.presentation
    spacing: 2
    Accessible.role: Accessible.ProgressBar
    Accessible.name: m ? "Target " + m.cleared + " of " + m.target : ""
    Repeater {
        model: 5
        Rectangle {
            id: segment
            required property int index
            width: 8
            height: 2
            radius: 1
            color: segment.index < meter.lit ? Theme.accent : Theme.border
            Behavior on color {
                ColorAnimation {
                    duration: Theme.fast
                }
            }
        }
    }
}
