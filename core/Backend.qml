pragma Singleton
import QtQuick
import Quickshell.Io
import "paths.js" as Paths

QtObject {
    id: root
    property bool ready: false
    property int sequence: 0
    property var pending: ({})
    property var capabilities: ({})
    // Whether a helper command is installed; `assumed` answers until the helper has reported.
    function has(command, assumed) {
        const commands = capabilities.commands;
        return commands ? commands[command] === true : assumed === true;
    }
    property string lastError: ""
    signal eventReceived(string name, var data)
    function request(method, params, callback) {
        if (!ready) {
            if (callback)
                callback(null, {
                    code: "unavailable",
                    message: "Desktop helper is not running"
                });
            return;
        }
        const id = ++sequence;
        pending[id] = {
            callback: callback,
            method: method,
            time: Date.now()
        };

        process.write(JSON.stringify({
            id: id,
            method: method,
            params: params || {}
        }) + "\n");
    }
    function receive(line) {
        try {
            const msg = JSON.parse(line);
            if (msg.event) {
                eventReceived(msg.event, msg.data);
                return;
            }
            const item = pending[msg.id];
            delete pending[msg.id];
            if (!msg.ok && msg.error && msg.error.code !== "cancelled" && (!item || ["calculator", "units.convert", "files.search", "weather.get", "weather.search", "wallhaven.search", "wallpaperscom.search", "media.art", "system.sample"].indexOf(item.method) < 0)) {
                lastError = msg.error.message || "Operation failed";
            }
            if (item && item.callback)
                item.callback(msg.result, msg.ok ? null : msg.error);
        } catch (e) {
            lastError = "Invalid response from desktop helper";
        }
    }
    property Process process: Process {
        command: ["python3", Paths.localPath(Qt.resolvedUrl("../helpers/backend.py"))]
        stdinEnabled: true
        running: true
        stdout: SplitParser {
            onRead: data => root.receive(data)
        }
        // The helper reports sanitized errors over its structured protocol.
        stderr: SplitParser {
            onRead: data => {
                if (data)
                    console.warn("Desktop helper:", data);
            }
        }
        onStarted: {
            root.ready = true;
            // A notice about the previous helper stopping no longer applies.
            root.lastError = "";
            root.request("capabilities", {}, (result, error) => {
                if (!error)
                    root.capabilities = result;
            });
        }
        onExited: {
            root.ready = false;
            const old = root.pending;
            root.pending = {};

            // ShellState shows one notice for the restart; callers see "stopped" and stay quiet.
            root.lastError = "Desktop helper stopped; restarting";
            for (const key in old)
                if (old[key].callback)
                    old[key].callback(null, {
                        code: "stopped",
                        message: "Desktop helper stopped"
                    });
            root.restart.restart();
        }
    }
    property Timer restart: Timer {
        interval: 5000
        onTriggered: root.process.running = true
    }
    property Timer deadlines: Timer {
        interval: 10000
        running: root.ready
        repeat: true
        onTriggered: {
            const now = Date.now();
            for (const key in root.pending) {
                if (now - root.pending[key].time > 180000) {
                    const cb = root.pending[key].callback;
                    delete root.pending[key];
                    if (cb)
                        cb(null, {
                            message: "Operation timed out"
                        });
                }
            }
        }
    }
}
