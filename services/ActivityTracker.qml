import QtQuick
import Quickshell.Wayland
import "../core"
import "." as S

QtObject {
    id: root
    readonly property int idleTimeout: 120
    // Opt-in: nothing is sampled until Activity is turned on.
    readonly property bool enabled: ShellState.setting("activityTracking", "ask") === "on"
    onEnabledChanged: snapshot()
    property var lastSnapshot: ({})
    // The shell's own inhibitor (lid awake, presentation) says nothing about whether you are watching.
    readonly property bool ownInhibitor: ShellState.lidAwake || (ShellState.presentation && !ShellState.locked)
    readonly property bool inhibited: idle.isIdle && !respecting.isIdle && !ownInhibitor
    readonly property bool fullscreenMedia: S.Services.fullscreen && S.Services.players.some(player => player.isPlaying)
    function snapshot() {
        if (!Backend.ready || !enabled) return;
        const windows = S.Services.windows.map(window => {
            const ipc = window.lastIpcObject || {};
            return {
                id: window.address || ipc.address || "",
                app: (window.wayland && window.wayland.appId) || ipc.class || ipc.initialClass || ""
            };
        }).filter(window => window.id && window.app);
        const active = S.Services.activeWindow;
        lastSnapshot = {
            unlocked: !ShellState.locked,
            idle: idle.isIdle,
            idleTimeout: idleTimeout,
            inhibited: inhibited,
            fullscreenMedia: fullscreenMedia,
            windows: windows,
            focused: active ? active.address : ""
        };
        Backend.request("activity.update", lastSnapshot, () => {});
    }
    // Raw input idleness: no input for two minutes, whatever is playing.
    property IdleMonitor idle: IdleMonitor {
        enabled: root.enabled
        timeout: root.idleTimeout
        respectInhibitors: false
        // Input is reported at once; going idle waits for the inhibitor-aware monitor to agree.
        onIsIdleChanged: isIdle ? root.idleSettle.restart() : root.snapshot()
    }
    // Stays not-idle while an app (a video player or browser) inhibits idle.
    property IdleMonitor respecting: IdleMonitor {
        enabled: root.enabled
        timeout: root.idleTimeout
        respectInhibitors: true
        onIsIdleChanged: root.idle.isIdle ? root.idleSettle.restart() : root.debounce.restart()
    }
    property Timer idleSettle: Timer {
        interval: 1000
        onTriggered: root.snapshot()
    }
    onFullscreenMediaChanged: debounce.restart()
    property Timer debounce: Timer {
        interval: 80
        onTriggered: root.snapshot()
    }
    property Timer heartbeat: Timer {
        interval: 30000
        repeat: true
        running: root.enabled
        onTriggered: root.snapshot()
    }
    property Connections windows: Connections {
        target: S.Services
        function onWindowsChanged() { root.debounce.restart(); }
        function onActiveWindowChanged() { root.debounce.restart(); }
    }
    property Connections session: Connections {
        target: ShellState
        function onLockedChanged() { root.snapshot(); }
        function onActivitySnapshotRequested() { root.snapshot(); }
        // Turning tracking on starts once the helper has saved the choice; until then it records nothing.
        function onSettingsSaved() { root.snapshot(); }
    }
    property Connections helper: Connections {
        target: Backend
        function onReadyChanged() { if (Backend.ready) root.snapshot(); }
    }
    Component.onCompleted: snapshot()
}
