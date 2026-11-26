import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

// Settings → Activity: recording on or off, and the panel.
ColumnLayout {
    spacing: 8
    C.Group {
        C.Toggle {
            Layout.fillWidth: true
            flat: true
            text: "Record activity"
            description: "How long you use each app and when you're active. It stays on this computer."
            selected: ShellState.setting("activityTracking", "ask") === "on"
            onClicked: ShellState.setSetting("activityTracking", selected ? "off" : "on")
        }
        C.ChoiceRow {
            settingKey: "activityKeep"
            label: "Keep for"
            description: ShellState.setting("activityKeep", 0) ? "Older days are forgotten once a day" : "Until you clear it"
            model: [{key: 30, text: "1 month"}, {key: 90, text: "3 months"}, {key: 365, text: "1 year"}, {key: 0, text: "Always"}]
            current: ShellState.setting("activityKeep", 0)
            onActivated: key => ShellState.setSetting("activityKeep", key)
        }
        C.OpenRow {
            label: "Activity"
            description: "Your day, the year and the apps you use most"
            action: "Open activity"
            glyph: "activity"
            onOpened: ShellState.open("activity")
        }
    }
    C.Label {
        text: "Active time ends at your last input; time with a video playing or an app keeping the screen awake counts as watching. Only app IDs and time ranges are kept, never window titles, for as long as Keep for says. Pause recording or hold Clear history in the Activity panel."
        color: Theme.textDim
        font.pixelSize: Theme.small
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
}
