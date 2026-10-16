pragma Singleton
import QtQuick
import Quickshell
import "../core"

// Whether a newer Shale is on GitHub and what it changes. helpers/update.py asks GitHub at most every 12 hours;
// asking the helper is cheap, so this does it hourly. A dot on the bar's control center button and a row at the
// top of the control center show it; the control center's Update page lists the commits as they were written.
QtObject {
    id: root
    property var status: ({})
    readonly property var info: status || ({})
    readonly property bool enabled: ShellState.setting("updateCheck", true)
    readonly property bool available: !!info.available
    readonly property var commits: info.commits || []
    readonly property int count: info.ahead || commits.length
    // What the last update brought, until "Got it": {from, to, commits}.
    readonly property var recent: info.recent || null
    readonly property string installed: info.installed || ""
    readonly property string latest: info.latest || ""
    // Update now runs ./install.sh --update in the checkout the shell was installed from.
    readonly property string source: info.source || ""
    property bool checking: false

    function refresh(force) {
        if (!Backend.ready || checking)
            return;
        checking = !!force;
        askedWith = enabled;
        Backend.request("update.status", {refresh: !!force}, (result, error) => {
            root.checking = false;
            if (!error)
                root.status = result;
        });
    }
    function skip() {
        Backend.request("update.skip", {}, (result, error) => {
            if (error)
                ShellState.message(error.message, "error");
            else
                root.status = result;
        });
    }
    function seen() {
        Backend.request("update.seen", {}, (result, error) => {
            if (!error)
                root.status = result;
        });
    }
    // In a terminal: the update may ask for a password or about shortcut clashes, and shows what it does. The
    // terminal runs in its own scope, so it stays open when the update restarts the shell.
    function install() {
        const terminal = Backend.capabilities.terminal || [];
        if (!source) {
            ShellState.message("Run ./install.sh --update in your Shale folder.", "error");
            return;
        }
        if (!terminal.length) {
            ShellState.message("Install a terminal, such as foot or kitty, or set $TERMINAL.", "error");
            return;
        }
        ShellState.launch(terminal.concat(["sh", "-c", 'cd -- "$1" && ./install.sh --update\nexec "${SHELL:-sh}"', "sh", source]), "", "shale-update");
        ShellState.close();
    }
    function changes(n) {
        return n + (n === 1 ? " change" : " changes");
    }
    // "2 hours ago" for epoch seconds.
    function ago(seconds) {
        const minutes = Math.max(0, Math.round((Date.now() / 1000 - seconds) / 60));
        if (!seconds)
            return "";
        if (minutes < 1)
            return "just now";
        if (minutes < 60)
            return minutes + (minutes === 1 ? " minute ago" : " minutes ago");
        const hours = Math.round(minutes / 60);
        if (hours < 24)
            return hours + (hours === 1 ? " hour ago" : " hours ago");
        const days = Math.round(hours / 24);
        return days + (days === 1 ? " day ago" : " days ago");
    }

    // The first look waits for the desktop to settle after login; later ones are hourly.
    property Timer firstCheck: Timer {
        interval: 20000
        running: Backend.ready
        onTriggered: root.refresh(false)
    }
    property Timer hourly: Timer {
        interval: 3600000
        running: Backend.ready
        repeat: true
        onTriggered: root.refresh(false)
    }
    // Turning checking on or off in Settings shows (or hides) an update once the helper has the setting.
    property bool askedWith: true
    property Connections saved: Connections {
        target: ShellState
        function onSettingsSaved() {
            if (root.enabled !== root.askedWith)
                root.refresh(false);
        }
    }
}
