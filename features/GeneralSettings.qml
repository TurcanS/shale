import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "../components" as C

// Settings → General: time and units, search and the terminal, updates.
ColumnLayout {
    spacing: 8
    C.SectionHeader { text: "Time and units" }
    C.Group {
        C.SettingToggle {
            text: "24-hour clock"
            description: "Everywhere Shale shows the time"
            key: "clock24h"
            fallback: true
        }
        C.ChoiceRow {
            settingKey: "weekStart"
            label: "Week starts on"
            description: "In the calendar and Activity"
            model: [{key: "locale", text: "Auto", hint: "As your language and region have it"}, {key: "monday", text: "Mon"}, {key: "sunday", text: "Sun"}, {key: "saturday", text: "Sat"}]
            current: ShellState.setting("weekStart", "locale")
            onActivated: key => ShellState.setSetting("weekStart", key)
        }
        C.ChoiceRow {
            settingKey: "weatherUnits"
            label: "Weather units"
            description: "Temperature and wind"
            model: [{key: "metric", text: "°C, km/h"}, {key: "imperial", text: "°F, mph"}]
            current: ShellState.setting("weatherUnits", "metric")
            onActivated: key => ShellState.setSetting("weatherUnits", key)
        }
    }
    C.SectionHeader { text: "Search and terminal" }
    C.Group {
        C.ChoiceRow {
            settingKey: "searchEngine"
            label: "Web search"
            description: "Type ? in Find"
            model: [{key: "duckduckgo", text: "DuckDuckGo"}, {key: "google", text: "Google"}, {key: "brave", text: "Brave"}]
            current: ShellState.setting("searchEngine", "duckduckgo")
            onActivated: key => ShellState.setSetting("searchEngine", key)
        }
        C.ChoiceRow {
            readonly property string chosen: ShellState.setting("terminal", "auto")
            readonly property var installed: Backend.capabilities.terminals || []
            settingKey: "terminal"
            label: "Terminal"
            description: "For commands run with > in Find"
            model: [{key: "auto", text: "Auto", hint: "$TERMINAL or the first one installed"}]
                .concat(installed.concat(chosen !== "auto" && installed.indexOf(chosen) < 0 ? [chosen] : []).map(name => ({key: name, text: name})))
            // Many terminals don't fit beside the name.
            stacked: model.length > 4
            current: chosen
            onActivated: key => ShellState.setSetting("terminal", key)
        }
    }
    C.SectionHeader { text: "Updates" }
    C.Group {
        C.SettingToggle {
            text: "Check for updates"
            description: "Asks GitHub every 12 hours. Control shows what a new version changes."
            key: "updateCheck"
            fallback: true
        }
    }
    C.SectionHeader { text: "History" }
    C.Group {
        C.OpenRow {
            id: findHistory
            // What Find remembers: how often apps and emoji were picked, and commands run with >.
            readonly property int count: Object.keys(ShellState.setting("appUsage", {})).length + Object.keys(ShellState.setting("emojiUsage", {})).length + ShellState.setting("runHistory", []).length
            label: "Find history"
            description: count ? "The apps, emoji and commands Find puts first. Pinned apps stay." : "Nothing remembered yet"
            action: "Clear"
            glyph: "trash"
            enabled: count > 0
            onOpened: ShellState.resetSettings(["appUsage", "emojiUsage", "runHistory"], () => ShellState.message("Find history cleared", "success", {label: "Undo", run: () => ShellState.restoreSettings()}))
        }
    }
}
