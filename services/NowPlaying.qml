pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"
import "." as S
import "../core/paths.js" as Paths

// Shared state for everything that shows the current track: one cava process for every
// visualizer, the cover as a local file, and a signal when the track changes.
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

    // The cover as a local file: the helper saves https:// and data: covers first. Every cover shown uses this file,
    // never the player's address: the helper fetches only from public addresses, and the display must not bypass
    // that.
    property string artFile: ""
    property int artRequest: 0
    onArtUrlChanged: resolveArt()
    // A player may already be playing when this is first created.
    Component.onCompleted: resolveArt()
    function resolveArt() {
        const url = root.artUrl;
        const request = ++artRequest;
        if (/^file:\/\//i.test(url)) {
            artFile = url;
        } else if (/^(https?:|data:image\/)/i.test(url) && Backend.ready) {
            // No cover until the new one arrives, never the previous track's.
            artFile = "";
            Backend.request("media.art", {url: url}, (result, error) => {
                if (request === root.artRequest)
                    root.artFile = error ? "" : "file://" + result.path.split("/").map(encodeURIComponent).join("/");
            });
        } else {
            artFile = "";
        }
    }
    property Connections helper: Connections {
        target: Backend
        function onReadyChanged() {
            if (Backend.ready)
                root.resolveArt();
        }
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
