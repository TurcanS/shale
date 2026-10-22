pragma Singleton
import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Bluetooth
import "../core"

QtObject {
    id: root
    readonly property var workspaces: Hyprland.workspaces.values
    readonly property var windows: Hyprland.toplevels.values
    readonly property var focusedWorkspace: Hyprland.focusedWorkspace
    readonly property var activeWindow: Hyprland.activeToplevel
    readonly property bool fullscreen: !!focusedWorkspace && focusedWorkspace.hasFullscreen
    readonly property var trayItems: SystemTray.items.values
    readonly property var players: Mpris.players.values
    property string selectedPlayer: ""
    readonly property var player: players.find(p => p.dbusName === selectedPlayer) || players.find(p => p.isPlaying) || players[0] || null
    readonly property bool audioAvailable: Pipewire.ready && !!Pipewire.defaultAudioSink
    readonly property var output: Pipewire.defaultAudioSink
    readonly property var input: Pipewire.defaultAudioSource
    // The media equalizer's filter nodes are routed automatically and are not devices or apps.
    readonly property var audioOutputs: Pipewire.nodes.values.filter(n => (n.type & PwNodeType.Audio) && n.isSink && !n.isStream && !n.name.startsWith("shale_eq"))
    readonly property var audioInputs: Pipewire.nodes.values.filter(n => (n.type & PwNodeType.Audio) && !n.isSink && !n.isStream)
    readonly property var audioStreams: Pipewire.nodes.values.filter(n => (n.type & PwNodeType.Audio) && n.isStream && !n.isSink && !n.name.startsWith("shale_eq"))
    // Apps recording a microphone or receiving a shared screen: PipeWire links from a device or
    // portal source into an app's stream. Sink monitors (the visualizer) start at a sink and don't count.
    readonly property var captureLinks: Pipewire.linkGroups.values.filter(g => !!g.source && !!g.target && g.target.isStream && !g.source.isStream && !g.source.isSink)
    // Only these few nodes are bound, for their application names and device API.
    property PwObjectTracker captureTracker: PwObjectTracker {
        objects: root.captureLinks.reduce((nodes, g) => nodes.concat([g.source, g.target]), [])
    }
    function captureApps(links) {
        const names = links.map(g => g.target.properties["application.name"] || g.target.description || g.target.name);
        return names.filter((name, i) => !!name && names.indexOf(name) === i);
    }
    readonly property var micUsers: captureApps(captureLinks.filter(g => g.source.type & PwNodeType.Audio))
    // A portal's screen-cast source is a video source without a device behind it (cameras have v4l2 or libcamera).
    readonly property var screenSharers: captureApps(captureLinks.filter(g => (g.source.type & PwNodeType.Video) && g.source.ready && !g.source.properties["device.api"]))
    readonly property real volume: output && output.audio ? output.audio.volume : 0
    readonly property bool muted: output && output.audio ? output.audio.muted : true
    readonly property real micVolume: input && input.audio ? input.audio.volume : 0
    readonly property bool micMuted: input && input.audio ? input.audio.muted : true
    property bool amplification: false
    property bool trackStreams: false
    property PwObjectTracker audioTracker: PwObjectTracker {
        objects: [root.output, root.input].filter(n => !!n).concat(root.trackStreams ? root.audioStreams : [])
    }
    readonly property var bluetoothAdapter: Bluetooth.defaultAdapter
    readonly property var bluetoothDevices: Bluetooth.devices.values
    readonly property bool bluetoothAvailable: !!bluetoothAdapter
    readonly property bool bluetoothEnabled: !!bluetoothAdapter && bluetoothAdapter.enabled
    readonly property bool bluetoothScanning: !!bluetoothAdapter && bluetoothAdapter.discovering
    readonly property bool batteryAvailable: UPower.displayDevice.ready && UPower.displayDevice.isPresent
    readonly property real batteryPercent: batteryAvailable ? UPower.displayDevice.percentage * 100 : 0
    readonly property bool batteryCharging: UPower.displayDevice.state === UPowerDeviceState.Charging
    readonly property bool onBattery: UPower.onBattery
    readonly property real batterySeconds: batteryCharging ? UPower.displayDevice.timeToFull : UPower.displayDevice.timeToEmpty
    property string lastError: ""
    signal osdRequested(string kind, real value, bool muted)
    signal batteryWarning(int percent)
    property var batteryWarnings: []
    onBatteryPercentChanged: checkBattery()
    onBatteryChargingChanged: checkBattery()
    function checkBattery() {
        if (batteryCharging || batteryPercent > 22) {
            batteryWarnings = [];
            return;
        }
        if (!batteryAvailable || !onBattery)
            return;
        for (const level of [5, 10, 20]) {
            if (batteryPercent <= level && batteryWarnings.indexOf(level) === -1) {
                batteryWarnings = batteryWarnings.concat([level]);
                batteryWarning(level);
                // A low initial reading should emit only its most relevant warning.
                batteryWarnings = batteryWarnings.concat([5, 10, 20].filter(v => v > level));
                break;
            }
        }
    }
    property bool initializedAudio: false
    property Timer audioWarmup: Timer {
        interval: 1500
        running: true
        onTriggered: root.initializedAudio = true
    }
    onVolumeChanged: {
        if (initializedAudio)
            osdRequested("volume", volume, muted);
    }
    onMutedChanged: {
        if (initializedAudio)
            osdRequested("volume", volume, muted);
    }
    function setVolume(value) {
        if (output && output.audio)
            output.audio.volume = Math.max(0, Math.min(amplification ? 1.5 : 1, value));
    }
    // Turning amplification off brings a boosted volume back to 100%.
    onAmplificationChanged: if (!amplification && volume > 1)
        setVolume(1)
    function toggleMute() {
        if (output && output.audio)
            output.audio.muted = !output.audio.muted;
    }
    function setMicVolume(value) {
        if (input && input.audio)
            input.audio.volume = Math.max(0, Math.min(1, value));
    }
    function toggleMicMute() {
        if (input && input.audio)
            input.audio.muted = !input.audio.muted;
    }
    function setOutput(node) {
        if (node)
            Pipewire.preferredDefaultAudioSink = node;
    }
    function setInput(node) {
        if (node)
            Pipewire.preferredDefaultAudioSource = node;
    }
    function setStreamVolume(node, value) {
        if (node && node.audio)
            node.audio.volume = Math.max(0, Math.min(1, value));
    }
    function bluetoothPower(enabled) {
        if (bluetoothAdapter)
            bluetoothAdapter.enabled = enabled;
    }
    function bluetoothScan(enabled) {
        if (bluetoothAdapter)
            bluetoothAdapter.discovering = enabled;
    }
    function workspace(id) {
        const existing = workspaces.find(w => String(w.id) === String(id) || w.name === String(id));
        if (existing) {
            existing.activate();
            return;
        }
        if (!/^\d+$/.test(String(id)))
            return;
        Hyprland.dispatch("hl.dsp.focus({ workspace = " + Number(id) + " })");
    }
    function focusWindow(window) {
        if (window && window.wayland)
            window.wayland.activate();
    }
    function closeWindow(window) {
        if (window && window.wayland)
            window.wayland.close();
    }
    property string pendingMoveAddress: ""
    property int pendingMoveWorkspace: 0
    function moveWindow(window, id) {
        if (!window || !/^\d+$/.test(String(id)))
            return;
        pendingMoveAddress = window.address;
        pendingMoveWorkspace = Number(id);
        moveTimeout.restart();
        if (activeWindow && activeWindow.address === pendingMoveAddress)
            finishMove();
        else
            focusWindow(window);
    }
    function finishMove() {
        if (!pendingMoveAddress || !activeWindow || activeWindow.address !== pendingMoveAddress)
            return;
        Hyprland.dispatch("hl.dsp.window.move({ workspace = " + pendingMoveWorkspace + " })");
        pendingMoveAddress = "";
        moveTimeout.stop();
    }
    onActiveWindowChanged: finishMove()
    property Timer moveTimeout: Timer {
        interval: 1500
        onTriggered: {
            root.pendingMoveAddress = "";
            root.lastError = "Could not focus the window to move it.";
        }
    }

    property bool dnd: false
    property bool locked: false
    property var notifications: []
    // Keep snapshot arrays for persistence/count consumers; views use keyed models.
    readonly property ListModel notificationModel: ListModel { dynamicRoles: true }
    readonly property ListModel popupModel: ListModel { dynamicRoles: true }
    function reconcileNotifications(model, records) {
        const ids = records.map(record => record.id);
        for (let i = model.count - 1; i >= 0; i--)
            if (ids.indexOf(model.get(i).notificationId) === -1)
                model.remove(i);
        for (let i = 0; i < records.length; i++) {
            const record = records[i];
            let existing = i;
            while (existing < model.count && model.get(existing).notificationId !== record.id)
                existing++;
            if (existing === model.count)
                model.insert(i, {notificationId: record.id, appName: record.appName, notificationData: record});
            else {
                if (existing !== i)
                    model.move(existing, i, 1);
                model.setProperty(i, "appName", record.appName);
                model.setProperty(i, "notificationData", record);
            }
        }
    }
    // Groups are ordered by their newest notification so recent activity stays on top.
    function historyOrder(records) {
        const newest = {};
        for (const record of records)
            newest[record.appName] = Math.max(newest[record.appName] || 0, record.timestamp || 0);
        return records.slice().sort((a, b) => newest[b.appName] - newest[a.appName] || a.appName.localeCompare(b.appName) || b.timestamp - a.timestamp);
    }
    // Transient notifications only pop up; they never enter history.
    onNotificationsChanged: {
        reconcileNotifications(notificationModel, historyOrder(notifications.filter(n => !n.transient)));
        reconcileNotifications(popupModel, popupIds.map(id => notifications.find(n => n.id === id)).filter(n => !!n));
    }
    onPopupIdsChanged: reconcileNotifications(popupModel, popupIds.map(id => notifications.find(n => n.id === id)).filter(n => !!n))
    property var popupIds: []
    property var pausedPopupIds: []
    property var popupDeadlines: ({})
    property NotificationServer notificationServer: NotificationServer {
        id: server
        keepOnReload: false
        bodySupported: true
        bodyMarkupSupported: false
        actionsSupported: true
        imageSupported: true
        persistenceSupported: false
        onNotification: notification => {
            notification.tracked = true;
            root.receiveNotification(notification);
            root.signalArrived(Date.now());
            root.logSignal(notification.appName, notification.urgency);
        }
    }
    property Instantiator notificationObservers: Instantiator {
        model: server.trackedNotifications
        delegate: QtObject {
            required property var modelData
            property Connections changes: Connections {
                target: modelData
                function onSummaryChanged() {
                    root.updateNotification(modelData);
                }
                function onBodyChanged() {
                    root.updateNotification(modelData);
                }
                function onAppNameChanged() {
                    root.updateNotification(modelData);
                }
                function onActionsChanged() {
                    root.updateNotification(modelData);
                }
                function onImageChanged() {
                    root.updateNotification(modelData);
                }
                function onAppIconChanged() {
                    root.updateNotification(modelData);
                }
                function onUrgencyChanged() {
                    root.updateNotification(modelData);
                }
                function onClosed(reason) {
                    root.notificationClosed(modelData.id);
                }
            }
        }
    }
    function notificationRecord(n) {
        return {
            id: n.id,
            summary: n.summary,
            body: n.body,
            appName: n.appName || "Application",
            appIcon: n.appIcon,
            image: n.image,
            urgency: n.urgency,
            actions: n.actions,
            original: n,
            transient: n.transient,
            timestamp: Date.now()
        };
    }
    function updateNotification(n) {
        notifications = notifications.map(item => item.id === n.id ? Object.assign(notificationRecord(n), {timestamp: item.timestamp}) : item);
    }
    function receiveNotification(n) {
        notifications = [notificationRecord(n)].concat(notifications.filter(item => item.id !== n.id));
        while (notifications.length > 200)
            dismissNotification(notifications[notifications.length - 1].id);
        if (!showPopup(n))
            dropTransient(n.id);
    }
    // The shell's own signals (reminders) need no D-Bus round trip to itself. Their actions are {identifier, text};
    // choosing one, or dismissing the signal, is handed back through localInvoked and localDismissed. One marked
    // `breaksQuiet` pops up through Quiet and Do not disturb, but not over the lock or a fullscreen window.
    // Something arrived: the Line shakes a small tremor at its time.
    signal signalArrived(real at)
    // The Dig keeps when a signal arrived and from which app, never what it said, and only while recording is on.
    function logSignal(app, urgency) {
        if (ShellState.setting("activityTracking", "ask") === "on" && Backend.ready)
            Backend.request("dig.signal", {at: Date.now(), app: app || "", urgency: urgency}, () => {});
    }
    signal localInvoked(int id, string identifier)
    signal localDismissed(int id)
    function post(fields) {
        const id = Math.min(0, ...notifications.map(n => n.id)) - 1;
        const record = Object.assign({summary: "", body: "", appName: "Application", appIcon: "", image: "", urgency: NotificationUrgency.Normal,
                                      actions: [], transient: false}, fields, {id: id, original: null, local: true, timestamp: Date.now()});
        notifications = [record].concat(notifications);
        while (notifications.length > 200)
            dismissNotification(notifications[notifications.length - 1].id);
        // A reminder waits for you: its popup stays until it is handled or makes room for a newer one.
        showPopup({id: id, urgency: record.urgency, expireTimeout: 0, breaksQuiet: !!record.breaksQuiet});
        signalArrived(record.timestamp);
        logSignal(record.appName, record.urgency);
        return id;
    }
    function showPopup(n) {
        if (locked || (((dnd && !n.breaksQuiet) || fullscreen) && n.urgency !== NotificationUrgency.Critical))
            return false;
        if (popupIds.indexOf(n.id) === -1 && popupIds.length >= 3) {
            // Make room by retiring the oldest popup that nobody is reading and that is not critical.
            const evictable = popupIds.find(id => {
                const record = notifications.find(item => item.id === id);
                return pausedPopupIds.indexOf(id) === -1 && !(record && record.urgency === NotificationUrgency.Critical);
            });
            if (evictable === undefined)
                return false;
            hidePopup(evictable);
        }
        popupIds = popupIds.filter(id => id !== n.id).concat([n.id]);
        // expireTimeout is in milliseconds. Critical notifications stay until dismissed, whatever the sender asks.
        const duration = n.urgency === NotificationUrgency.Critical || n.expireTimeout === 0 ? 0 : n.expireTimeout < 0 ? 6000 : n.expireTimeout;
        popupDeadlines[n.id] = duration === 0 ? 0 : Date.now() + duration;
        return true;
    }
    function notificationClosed(id) {
        notifications = notifications.map(item => item.id === id ? Object.assign({}, item, {
                original: null,
                actions: []
            }) : item);
        hidePopup(id);
    }
    // A popup that goes away leaves its notification in history, except a transient one, which closes.
    function hidePopup(id) {
        popupIds = popupIds.filter(value => value !== id);
        pausedPopupIds = pausedPopupIds.filter(value => value !== id);
        delete popupDeadlines[id];
        dropTransient(id);
    }
    function dropTransient(id) {
        const record = notifications.find(item => item.id === id);
        if (!record || !record.transient)
            return;
        notifications = notifications.filter(item => item.id !== id);
        if (record.original)
            record.original.expire();
    }
    function pausePopup(id, paused) {
        pausedPopupIds = pausedPopupIds.filter(value => value !== id);
        if (paused)
            pausedPopupIds = pausedPopupIds.concat([id]);
    }
    function dismissNotification(id) {
        const record = notifications.find(item => item.id === id);
        notifications = notifications.filter(item => item.id !== id);
        hidePopup(id);
        if (record && record.original)
            record.original.dismiss();
        if (record && record.local)
            localDismissed(id);
    }
    function dismissAllNotifications() {
        for (const item of notifications.slice())
            dismissNotification(item.id);
    }
    function dismissApplication(appName) {
        for (const item of notifications.slice())
            if (item.appName === appName)
                dismissNotification(item.id);
    }
    function defaultActionIndex(record) {
        return record && record.original ? (record.actions || []).findIndex(action => action && action.identifier === "default") : -1;
    }
    function invokeDefault(id) {
        const record = notifications.find(item => item.id === id);
        const index = defaultActionIndex(record);
        if (index >= 0)
            invokeNotification(id, index);
        return index >= 0;
    }
    function invokeNotification(id, index) {
        const record = notifications.find(item => item.id === id);
        if (record && record.local && record.actions[index]) {
            localInvoked(id, record.actions[index].identifier);
            dismissNotification(id);
            return;
        }
        if (!record || !record.original || !record.actions[index])
            return;
        record.actions[index].invoke();
        if (record.original && !record.original.resident)
            dismissNotification(id);
    }
    onLockedChanged: {
        if (!locked)
            return;
        popupIds = [];
        pausedPopupIds = [];
        popupDeadlines = ({});
        for (const item of notifications.slice())
            if (item.transient)
                dismissNotification(item.id);
        bluetoothScan(false);
    }
    property Timer popupClock: Timer {
        interval: 250
        repeat: true
        running: root.popupIds.length > 0
        onTriggered: {
            const now = Date.now();
            for (const id of root.popupIds.slice()) {
                if (!root.popupDeadlines[id])
                    continue;
                if (root.pausedPopupIds.indexOf(id) !== -1) {
                    root.popupDeadlines[id] += interval;
                    continue;
                }
                if (now >= root.popupDeadlines[id])
                    root.hidePopup(id);
            }
        }
    }
    // The helper reports an equalizer filter it gave up restarting (at login or after a crash). The setting
    // stays on: PipeWire may only have been slow, and the equalizer starts again when Media is opened.
    property Connections backendEvents: Connections {
        target: Backend
        function onEventReceived(name, data) {
            if (name !== "eq" || !data || data.enabled || !ShellState.setting("eqEnabled", false))
                return;
            ShellState.message("The equalizer could not start. Open Media in the control center to try again.", "error");
        }
    }
}
