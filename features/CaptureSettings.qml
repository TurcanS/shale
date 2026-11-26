import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

// Settings → Capture: recording sound, delay and folders.
ColumnLayout {
    spacing: 8
    C.Group {
        C.ChoiceRow {
            settingKey: "recordAudio"
            label: "Recording sound"
            description: "What a screen recording hears"
            model: [{key: "none", text: "None"}, {key: "system", text: "System"}, {key: "microphone", text: "Microphone"}]
            current: ShellState.setting("recordAudio", "none")
            onActivated: key => ShellState.setSetting("recordAudio", key)
        }
        C.ChoiceRow {
            settingKey: "captureDelay"
            label: "Screenshot delay"
            description: "Time to set the screen up first"
            model: [0, 3, 5, 10].map(seconds => ({key: seconds, text: seconds ? seconds + " s" : "None"}))
            current: ShellState.setting("captureDelay", 0)
            onActivated: key => ShellState.setSetting("captureDelay", key)
        }
    }
    C.SectionHeader { text: "Folders" }
    C.Group {
        C.FolderField {
            label: "Screenshot folder"
            note: "Saved screenshots go here"
            key: "screenshotDirectory"
            fallback: "~/Pictures/Screenshots"
        }
        C.FolderField {
            label: "Recording folder"
            note: "Screen recordings go here"
            key: "recordingDirectory"
            fallback: "~/Videos/Recordings"
        }
    }
}
