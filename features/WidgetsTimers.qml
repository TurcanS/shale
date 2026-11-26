import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "../components" as C

// The Timers card: the focus session, then each running timer with the time left, soonest first. With none it says
// how to start one. The times come from Focus, which ticks while anything runs. Opens Control.
WidgetsCard {
    id: root
    readonly property var rows: (Focus.active ? [{key: "focus", label: Focus.paused ? "Focus · paused" : "Focus",
                                                   seconds: Focus.remainingSeconds, focus: true}] : [])
        .concat(Focus.timers.map(timer => ({key: "timer-" + timer.id, label: timer.label || "Timer",
                                            seconds: Math.max(0, Math.ceil((timer.endsAt - Focus.now) / 1000)), focus: false})))
    panel: "control"
    padding: 16
    Accessible.role: Accessible.List
    Accessible.name: rows.length ? rows.length + " running" : "No timers"
    ColumnLayout {
        anchors.fill: parent
        spacing: 8
        RowLayout {
            spacing: 8
            Layout.fillWidth: true
            C.Icon {
                name: "timer"
                size: 16
                color: Theme.textMuted
            }
            C.Label {
                text: "Timers"
                color: Theme.textMuted
                font.pixelSize: 14
                Layout.fillWidth: true
            }
        }
        Repeater {
            model: root.rows.slice(0, 3)
            RowLayout {
                id: timerRow
                required property var modelData
                spacing: 8
                Layout.fillWidth: true
                C.Label {
                    text: timerRow.modelData.label
                    color: timerRow.modelData.focus ? Theme.accentText : Theme.textSecondary
                    font.pixelSize: 13
                    Layout.fillWidth: true
                }
                C.Label {
                    text: Focus.clockText(timerRow.modelData.seconds)
                    font.pixelSize: timerRow.modelData === root.rows[0] ? 28 : 17
                    font.weight: Font.DemiBold
                    font.features: ({"tnum": 1})
                    elide: Text.ElideNone
                }
            }
        }
        C.Label {
            visible: root.rows.length > 3
            text: "and " + (root.rows.length - 3) + " more"
            color: Theme.textDim
            font.pixelSize: 12
        }
        Item {
            Layout.fillHeight: true
        }
        C.Label {
            visible: root.rows.length === 0
            text: "Nothing running. Type timer 10m tea in Find to start one."
            color: Theme.textDim
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }
}
