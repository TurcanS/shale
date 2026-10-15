import QtQuick
import Quickshell
import "core"
import "services"
import "features"

ShellRoot {
    id: root
    ActivityTracker {}
    WallpaperAccent {}
    LockScreen {}
    property bool historyLoaded: false
    // Until saved history is back, a save would overwrite it with only the new notifications.
    property bool historyRestored: false
    property bool lastPersist: false
    // Runs once per enable: needs the helper and the loaded settings, whichever arrives last.
    function restoreHistory() {
        if (!Backend.ready || historyLoaded || !ShellState.setting("persistNotifications", false))
            return;
        historyLoaded = true;
        Backend.request("notifications.get", {}, (r, e) => {
            if (e) {
                root.historyLoaded = false; // tried again when the helper is back
                return;
            }
            if (!ShellState.setting("persistNotifications", false))
                return;
            root.historyRestored = true;
            // Turning history off and on again quickly can bring back entries that are still listed. They are
            // matched by content: ids start over with each session. Restored ids stay below every id in use.
            const key = n => n.timestamp + "\n" + n.appName + "\n" + n.summary;
            const listed = new Set(Services.notifications.map(key));
            const lowest = Math.min(0, ...Services.notifications.map(n => n.id));
            const restored = r.entries.filter(n => !listed.has(key(n))).map((n, i) => Object.assign({}, n, {
                    id: lowest - 1 - i,
                    original: null,
                    actions: [],
                    image: "",
                    transient: false
                }));
            Services.notifications = Services.notifications.concat(restored).slice(0, 200);
        });
    }
    Component.onCompleted: {
        // A focus session holds popups too, without changing the user's own Do not disturb.
        Services.dnd = Qt.binding(() => ShellState.setting("dnd", false) || Focus.active);
        Services.locked = Qt.binding(() => ShellState.locked);
        Services.amplification = Qt.binding(() => ShellState.setting("amplification", false));
        Services.trackStreams = Qt.binding(() => ShellState.panel === "control" && ShellState.detail === "audio");
    }
    Connections {
        target: Services
        function onOsdRequested(kind, value, muted) {
            ShellState.osd(muted ? "Muted" : "Volume", value, muted ? "mute" : "volume", muted);
        }
        function onBatteryWarning(percent) {
            ShellState.message("Battery at " + percent + "% · Connect your charger", "error");
        }
        function onLastErrorChanged() {
            if (Services.lastError)
                ShellState.message(Services.lastError, "error");
        }
        function onNotificationsChanged() {
            historySave.restart();
        }
    }
    Connections {
        target: Backend
        function onReadyChanged() {
            root.restoreHistory();
        }
    }
    Connections {
        target: ShellState
        function onSettingsChanged() {
            const enabled = ShellState.setting("persistNotifications", false);
            if (enabled !== root.lastPersist) {
                root.lastPersist = enabled;
                if (enabled) {
                    root.restoreHistory();
                } else {
                    root.historyLoaded = false;
                    root.historyRestored = false;
                    historySave.restart();
                }
            }
        }
    }
    Timer {
        id: historySave
        interval: 1000
        onTriggered: {
            // Before settings load, persistence may be on without the shell knowing it yet.
            if (!Object.keys(ShellState.settings).length || (ShellState.setting("persistNotifications", false) && !root.historyRestored))
                return;
            Backend.request("notifications.set", {
                entries: Services.notifications.filter(n => !n.transient).map(n => ({
                            id: n.id,
                            summary: n.summary,
                            body: n.body,
                            appName: n.appName,
                            appIcon: n.appIcon,
                            urgency: n.urgency,
                            timestamp: n.timestamp
                        }))
            });
        }
    }
    Variants {
        model: Quickshell.screens
        delegate: Scope {
            id: output
            required property var modelData
            Bar {
                screen: output.modelData
                outputName: output.modelData.name
            }
            WallpaperTransition {
                screen: output.modelData
                outputName: output.modelData.name
            }
            PanelHost {
                screen: output.modelData
                outputName: output.modelData.name
            }
            Toasts {
                screen: output.modelData
            }
            StayAwake {
                screen: output.modelData
            }
        }
    }
}
