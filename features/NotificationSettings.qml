import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "../components" as C

// Settings → Notifications: history and focus sessions.
ColumnLayout {
    spacing: 8
    C.Group {
        C.SettingToggle {
            text: "Keep notification history across restarts"
            description: "Up to 200 notifications for seven days. Contents stay hidden on the lock screen."
            key: "persistNotifications"
        }
        C.ChoiceRow {
            readonly property var hours: ShellState.setting("quietHours", [])
            settingKey: "quietHours"
            label: "Quiet hours"
            description: hours.length === 2 ? "Popups wait, as with Do not disturb; urgent ones still show" : "Every night, without turning Do not disturb on"
            model: [{key: "off", text: "Off"}, {key: "22-7", text: "22–07"}, {key: "23-8", text: "23–08"}, {key: "0-9", text: "00–09"}]
            current: hours.length === 2 ? hours.join("-") : "off"
            onActivated: key => ShellState.setSetting("quietHours", key === "off" ? [] : key.split("-").map(Number))
        }
        C.ChoiceRow {
            settingKey: "focusMinutes"
            label: "Focus length"
            description: "Notifications wait until a focus session ends"
            model: [25, 50, 90].map(minutes => ({key: minutes, text: minutes + " min"}))
            current: ShellState.setting("focusMinutes", 25)
            onActivated: key => ShellState.setSetting("focusMinutes", key)
        }
    }
}
