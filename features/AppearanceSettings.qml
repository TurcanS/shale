import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

// Settings → Appearance: colour, size, behaviour, wallpaper and lock screen.
ColumnLayout {
    spacing: 8
    ColorSettings {
        Layout.fillWidth: true
    }
    C.SectionHeader { text: "Size" }
    C.Group {
        C.ChoiceRow {
            settingKey: "fontSize"
            label: "Text size"
            description: "In panels; the bar keeps its own"
            model: [12, 14, 16, 18].map(size => ({key: size, text: String(size)}))
            current: Theme.body
            onActivated: key => ShellState.setSetting("fontSize", key)
        }
        C.ChoiceRow {
            settingKey: "panelSize"
            label: "Panel size"
            description: "How large panels are drawn"
            model: [80, 85, 90, 100].map(size => ({key: size, text: size + "%"}))
            current: ShellState.setting("panelSize", 85)
            onActivated: key => ShellState.setSetting("panelSize", key)
        }
    }
    C.SectionHeader { text: "Behaviour" }
    C.Group {
        C.ChoiceRow {
            settingKey: "motion"
            label: "Motion"
            // Reduce motion and trimmed effects win over the choice; say so rather than look ignored.
            description: Theme.reduced ? "Reduce motion is on" : Theme.lowPower ? "Calm while effects are reduced" : "How much panels and controls move"
            model: [{key: "calm", text: "Calm", hint: "Short rises and fades"}, {key: "lively", text: "Lively", hint: "Drawers, flips and scope lines"},
                    {key: "playful", text: "Playful", hint: "The same, turned up"}]
            current: ShellState.setting("motion", "lively")
            onActivated: key => ShellState.setSetting("motion", key)
        }
        C.SettingToggle {
            text: "Reduce motion"
            description: "Panels and controls change without animating"
            key: "reducedMotion"
        }
        C.SettingToggle {
            text: "Reduce effects in every mode"
            description: "No visualizers, blur, shadows or live window previews"
            key: "batterySaving"
        }
        C.SettingToggle {
            text: "Window preview snapshots"
            description: "Pictures of windows in Pages"
            key: "windowPreviews"
            fallback: true
        }
        C.SettingToggle {
            text: "Music visualizer"
            description: "In the bar and on the Player"
            key: "visualizer"
            fallback: true
        }
    }
    C.SectionHeader { text: "Wallpaper" }
    C.Group {
        C.FolderField {
            label: "Wallpaper folder"
            note: "Where Wallpapers looks for pictures"
            key: "wallpaperDirectory"
            fallback: "~/Pictures/Wallpapers"
        }
        C.ChoiceRow {
            settingKey: "wallpaperFit"
            // hyprpaper has all four; awww and swww only crop or fit.
            readonly property bool hyprpaper: !Backend.has("awww", false) && !Backend.has("swww", false)
            label: "Wallpaper fit"
            description: "When a picture's shape isn't the screen's"
            model: [{key: "cover", text: "Fill", hint: "Crops the edges"}, {key: "contain", text: "Fit", hint: "Shows all of it, with bars"}]
                .concat(hyprpaper ? [{key: "fill", text: "Stretch", hint: "Pulls it to the screen's shape"}, {key: "tile", text: "Tile", hint: "Repeats it"}] : [])
            current: ShellState.setting("wallpaperFit", "cover")
            onActivated: key => ShellState.setSetting("wallpaperFit", key)
        }
        C.OpenRow {
            label: "Wallpaper"
            description: "Pick from the folder or find new ones"
            action: "Choose wallpaper"
            glyph: "image"
            onOpened: ShellState.open("wallpaper")
        }
    }
    C.SectionHeader { text: "Lock screen" }
    C.Group {
        C.Toggle {
            readonly property bool hyprlock: Backend.has("hyprlock", true)
            readonly property bool builtin: ShellState.setting("lockScreen", "builtin") === "builtin" || !hyprlock
            Layout.fillWidth: true
            flat: true
            enabled: hyprlock
            text: "Use the built-in lock screen"
            description: !hyprlock ? "Install hyprlock to use it instead." : builtin ? "Blurred wallpaper, clock and media controls. hyprlock takes over if the shell stops." : "hyprlock locks the screen."
            selected: builtin
            onClicked: ShellState.setSetting("lockScreen", builtin ? "hyprlock" : "builtin")
        }
        C.ChoiceRow {
            settingKey: "lockStyle"
            visible: ShellState.setting("lockScreen", "builtin") === "builtin" || !Backend.has("hyprlock", true)
            label: "Style"
            description: ShellState.setting("lockStyle", "particles") === "classic" ? "A large clock over your wallpaper" : "The time drawn in points of light that gather, shift and burst"
            model: [{key: "particles", text: "Particles"}, {key: "classic", text: "Classic"}]
            current: ShellState.setting("lockStyle", "particles")
            onActivated: key => ShellState.setSetting("lockStyle", key)
        }
    }
}
