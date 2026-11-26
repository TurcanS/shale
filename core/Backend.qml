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
    function refreshCapabilities() {
        request("capabilities", {}, (result, error) => {
            if (!error)
                capabilities = result;
        });
    }
    // Whether a helper command is installed; `assumed` answers until the helper has reported.
    function has(command, assumed) {
        const commands = capabilities.commands;
        return commands ? commands[command] === true : assumed === true;
    }
    property string lastError: ""
    signal eventReceived(string name, var data)
    // `options.owner`: the page asking. Once it is gone (its panel closed) the answer is dropped instead of reaching
    // a callback that would touch a destroyed page. `options.silent`: a failure is the caller's to show.
    function request(method, params, callback, options) {
        if (!ready) {
            if (callback)
                callback(null, {
                    code: "unavailable",
                    message: "Desktop helper is not running"
                });
            return;
        }
        const id = ++sequence;
        const item = {
            callback: callback,
            method: method,
            silent: !!(options && options.silent),
            time: Date.now()
        };
        if (options && options.owner) {
            try {
                options.owner.Component.destruction.connect(() => item.callback = null);
            } catch (e) {
                console.warn("Backend.request: owner of", method, "can't be followed:", e);
            }
        }
        pending[id] = item;

        process.write(JSON.stringify({
            id: id,
            method: method,
            params: params || {}
        }) + "\n");
    }
    // These fail in the ordinary course of typing or polling; their views show it themselves.
    readonly property var quietMethods: ["calculator", "units.convert", "files.search", "weather.get", "weather.search", "wallhaven.search", "wallpaperscom.search", "media.art", "system.sample"]
    function receive(line) {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            lastError = "Invalid response from desktop helper";
            return;
        }
        if (msg.event) {
            eventReceived(msg.event, msg.data);
            return;
        }
        const item = pending[msg.id];
        delete pending[msg.id];
        // An answer to a request that already timed out is late news, not a new error.
        if (item && !msg.ok && msg.error && msg.error.code !== "cancelled" && !item.silent && quietMethods.indexOf(item.method) < 0)
            lastError = msg.error.message || "Operation failed";
        if (!item || !item.callback)
            return;
        // A mistake in a caller's callback is that caller's, with its own trace, not a bad answer from the helper.
        try {
            item.callback(msg.result, msg.ok ? null : msg.error);
        } catch (e) {
            console.warn("Backend: the callback of", item.method, "failed:", e, e.stack || "");
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
            root.refreshCapabilities();
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
                            code: "timeout",
                            message: "Operation timed out"
                        });
                }
            }
        }
    }
}
