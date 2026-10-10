import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../core"
import "../core/palette.js" as Palette

// Keeps the accent colour in step with the focused monitor's wallpaper while "Match wallpaper" is on.
Scope {
    id: root
    readonly property bool enabled: ShellState.setting("accentFromWallpaper", false)
    readonly property string monitor: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    readonly property string path: {
        const active = ShellState.activeWallpapers;
        return active[monitor] || active[Object.keys(active)[0]] || "";
    }
    readonly property string accent: Palette.accentFrom(quantizer.colors)
    function apply() {
        if (enabled && accent !== "" && ShellState.setting("accentColor", "") !== accent)
            ShellState.setSetting("accentColor", accent);
    }
    ColorQuantizer {
        id: quantizer
        source: root.enabled && root.path !== "" ? "file://" + root.path.split("/").map(encodeURIComponent).join("/") : ""
        depth: 3
        rescaleSize: 64
    }
    // Moving focus across monitors with different wallpapers settles before the settings file is written.
    Timer {
        id: settle
        interval: 400
        onTriggered: root.apply()
    }
    onAccentChanged: settle.restart()
    onEnabledChanged: settle.restart()
}
