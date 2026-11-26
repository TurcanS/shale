pragma Singleton
import QtQuick
import "../core"

// The desktop Note card's one running note: [{text, done}], oldest first, kept by the helper next to the other state
// files. Find adds a line with "note …"; the card ticks lines off and removes them.
QtObject {
    id: root
    property var lines: []
    property bool loaded: false
    readonly property int remaining: lines.filter(line => !line.done).length
    function load() {
        if (!Backend.ready)
            return;
        Backend.request("note.get", {}, (r, e) => {
            if (e)
                return;
            root.lines = r.lines;
            root.loaded = true;
        });
    }
    // Added by the helper, so a line typed before the note has loaded never replaces it.
    function add(text, finished) {
        const line = String(text || "").trim();
        if (!line)
            return;
        Backend.request("note.add", {text: line}, (r, e) => {
            if (e) {
                ShellState.message(e.message, "error");
                return;
            }
            root.lines = r.lines;
            root.loaded = true;
            if (finished)
                finished();
        });
    }
    function toggle(index) {
        save(lines.map((line, i) => i === index ? {text: line.text, done: !line.done} : line));
    }
    function remove(index) {
        save(lines.filter((line, i) => i !== index));
    }
    function save(next) {
        if (!loaded)
            return;
        const before = lines;
        lines = next;
        Backend.request("note.set", {lines: next}, (r, e) => {
            if (e) {
                root.lines = before;
                ShellState.message(e.message, "error");
            }
        });
    }
    Component.onCompleted: load()
    property Connections helper: Connections {
        target: Backend
        function onReadyChanged() {
            root.load();
        }
    }
}
