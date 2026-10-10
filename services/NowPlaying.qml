pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"
import "../core/palette.js" as Palette
import "." as S
import "../core/paths.js" as Paths

// Shared state for everything that shows the current track: one cava process for every
// visualizer, the cover's colours, and a signal when the track changes.
Singleton {
    id: root
    readonly property var player: S.Services.player
    readonly property bool playing: !!player && player.isPlaying
    readonly property string artUrl: player ? player.trackArtUrl || "" : ""

    // Visualizers call acquire() while they draw and release() when they stop; cava runs only with demand.
    property int demand: 0
    property bool available: false
    readonly property int bars: 32
    property var levels: []
    function acquire() { demand++; }
    function release() { demand = Math.max(0, demand - 1); }
    Process {
        command: ["sh", "-c", "command -v cava"]
        running: true
        onExited: code => root.available = code === 0
    }
    Process {
        command: ["cava", "-p", Paths.localPath(Qt.resolvedUrl("../assets/cava-visualizer.conf"))]
        running: root.demand > 0 && root.available
        stdout: SplitParser {
            onRead: data => root.levels = data.split(";", root.bars).map(Number)
        }
        onRunningChanged: if (!running)
            root.levels = []
    }

    // Two tones from the cover: its most vivid colour and a contrasting one.
    // Greyscale covers get soft white; no cover falls back to the accent.
    ColorQuantizer {
        id: quantizer
        source: root.artUrl
        depth: 3
        rescaleSize: 64
    }
    readonly property var artColors: {
        const pair = root.artUrl !== "" ? Palette.vividPair(quantizer.colors) : null;
        if (!pair)
            return [Theme.accent, Theme.accentHover];
        if (pair.grey)
            return [Qt.hsla(0, 0, 0.9, 1), Qt.hsla(0, 0, 0.6, 1)];
        // Lift lightness and saturation so bars read over the artwork itself.
        return [Palette.tone(pair.first, 0.66), Palette.tone(pair.second, 0.5)];
    }

    // Players fill metadata in several steps, so a change is announced once it has settled.
    // The first track seen after start-up (or after the player appears) is never announced.
    signal trackChanged()
    readonly property string trackKey: player && player.trackTitle ? player.dbusName + "\n" + player.trackTitle + "\n" + (player.trackArtist || "") : ""
    property string announcedKey: ""
    property string playerName: ""
    onTrackKeyChanged: settle.restart()
    Timer {
        id: settle
        interval: 600
        onTriggered: {
            const key = root.trackKey;
            const name = root.player ? root.player.dbusName : "";
            const known = root.announcedKey !== "" && name === root.playerName;
            if (key !== "" && key !== root.announcedKey && known && root.playing)
                root.trackChanged();
            if (key !== "") {
                root.announcedKey = key;
                root.playerName = name;
            }
        }
    }
}
