import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import "../core"
import "../core/keys.js" as KeyNames
import "../components" as C

// Settings → Shortcuts: each Shale shortcut, recorded by pressing the new keys.
ColumnLayout {
    id: root
    spacing: 8
    // shortcuts.list: {ready, shortcuts: [{action, title, default, keys, changed}]}
    property var listing: ({ready: false, shortcuts: []})
    property bool loaded: false
    // The action whose keys are being recorded, and the modifiers held so far.
    property string recording: ""
    property string held: ""
    // True while Hyprland's empty recording submap is active, so bound keys reach the recorder.
    property bool submap: false
    // Counts start() calls: only the latest one's answer may set `submap`, whatever order the answers come in.
    property int recordTicket: 0
    property bool busy: false
    property string error: ""
    property string errorAction: ""
    property string savedAction: ""
    readonly property bool anyChanged: listing.shortcuts.some(item => item.changed)
    function load() {
        Backend.request("shortcuts.list", {}, (r, e) => {
            if (!e)
                root.listing = r;
            root.loaded = true;
        }, {owner: root});
    }
    function start(action) {
        stop();
        error = "";
        savedAction = "";
        recording = action;
        held = "";
        recorder.forceActiveFocus();
        const ticket = ++recordTicket;
        Backend.request("shortcuts.record", {active: true}, (r, e) => {
            // Settings closed meanwhile: leave the submap, or Hyprland's shortcuts stay off until Escape.
            if (!root) {
                if (!e && r.active)
                    Backend.request("shortcuts.record", {active: false});
                return;
            }
            if (ticket === root.recordTicket && root.recording !== "")
                root.submap = !e && r.active;
            // Stopped meanwhile: leave the submap again, unless another shortcut is being recorded and needs it.
            else if (!e && r.active && root.recording === "")
                Backend.request("shortcuts.record", {active: false});
        });
    }
    function stop() {
        if (!recording)
            return;
        recording = "";
        held = "";
        if (submap)
            Backend.request("shortcuts.record", {active: false});
        submap = false;
    }
    // keys: "" removes the shortcut, null resets it (or every shortcut when action is "").
    function apply(action, keys) {
        stop();
        busy = true;
        error = "";
        const reset = keys === null;
        Backend.request(reset ? "shortcuts.reset" : "shortcuts.set", reset ? (action ? {action: action} : {}) : {action: action, keys: keys}, (r, e) => {
            busy = false;
            if (e) {
                root.error = e.message;
                root.errorAction = action;
                // It may have been saved even so (Hyprland couldn't take it right now).
                root.load();
                return;
            }
            root.listing = r;
            root.savedAction = action || "*";
            savedTimer.restart();
        }, {owner: root});
    }
    onVisibleChanged: visible ? load() : stop()
    Component.onCompleted: if (Backend.ready) load()
    Component.onDestruction: stop()
    Connections {
        target: Backend
        function onReadyChanged() {
            if (Backend.ready) {
                root.submap = false;
                root.stop();
                root.load();
            }
        }
    }
    // Escape or the helper's 15-second limit ends the submap; stop listening with it.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap" && root.submap && event.data !== "shale-record") {
                root.submap = false;
                root.stop();
            }
        }
    }
    Timer {
        id: savedTimer
        interval: 2500
        onTriggered: root.savedAction = ""
    }
    Item {
        id: recorder
        Layout.preferredHeight: 0
        Layout.preferredWidth: 0
        onActiveFocusChanged: if (!activeFocus) root.stop()
        Keys.onPressed: event => {
            if (!root.recording)
                return;
            event.accepted = true;
            const plain = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier | Qt.ShiftModifier));
            if (event.key === Qt.Key_Escape && plain) {
                root.stop();
            } else if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) && plain) {
                root.apply(root.recording, "");
            } else {
                const keys = KeyNames.fromEvent(event);
                if (keys)
                    root.apply(root.recording, keys);
                else
                    root.held = KeyNames.held(event, true);
            }
        }
        Keys.onReleased: event => {
            if (root.recording) {
                event.accepted = true;
                root.held = KeyNames.held(event, false);
            }
        }
    }
    C.Label {
        text: !root.loaded ? "" : root.listing.ready ? "Choose Change, then press the new keys. Keys Hyprland already uses are refused; the rest apply right away." : "Shortcuts come from the installed Hyprland fragment. Update Shale with ./install.sh --update to change them here; you can also copy a command to bind it yourself."
        visible: text !== ""
        color: Theme.textSecondary
        font.pixelSize: Theme.label
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    // Each shortcut: its name (and what's happening to it) beside its key caps, Change, then reset and copy.
    C.Group {
        Repeater {
            model: root.listing.shortcuts
            C.SettingRow {
                id: shortcut
                required property var modelData
                readonly property bool active: root.recording === modelData.action
                readonly property bool saved: root.savedAction === modelData.action || root.savedAction === "*"
                readonly property bool failed: root.error !== "" && root.errorAction === modelData.action
                readonly property var caps: KeyNames.caps(active ? (root.held ? root.held + " + …" : "") : modelData.keys)
                label: modelData.title
                description: failed ? root.error : active ? "Press the new keys · Esc to cancel · Backspace for none" : saved ? "Saved" : modelData.changed ? "Changed" : ""
                descriptionColor: failed ? Theme.dangerText : active ? Theme.accentText : saved ? Theme.success : Theme.textDim
                C.Label {
                    visible: !shortcut.active && !shortcut.modelData.keys
                    text: "Not set"
                    color: Theme.textFaint
                    font.pixelSize: Theme.small
                }
                Row {
                    spacing: 4
                    Layout.rightMargin: 4
                    Repeater {
                        model: shortcut.caps
                        C.KeyHint {
                            required property string modelData
                            text: modelData
                            textSize: 12
                            width: Math.max(24, implicitWidth)
                            height: 24
                            color: shortcut.active ? Theme.raisedOnKey : Theme.key
                            textColor: shortcut.active ? Theme.accentText : Theme.textSecondary

                        }
                    }
                }
                C.Button {
                    visible: root.listing.ready
                    text: shortcut.active ? "Press keys…" : "Change"
                    selected: shortcut.active
                    enabled: !root.busy
                    implicitWidth: 104
                    implicitHeight: 30
                    cornerRadius: 8
                    labelSize: 12
                    hint: (shortcut.active ? "Stop recording " : "Change the ") + shortcut.modelData.title + " shortcut"
                    onClicked: shortcut.active ? root.stop() : root.start(shortcut.modelData.action)
                }
                C.Button {
                    visible: root.listing.ready && shortcut.modelData.changed && !shortcut.active
                    glyph: "refresh"
                    hint: "Reset " + shortcut.modelData.title
                    flat: true
                    enabled: !root.busy
                    implicitWidth: 30
                    implicitHeight: 30
                    cornerRadius: 8
                    onClicked: root.apply(shortcut.modelData.action, null)
                }
                C.Button {
                    glyph: "copy"
                    hint: "Copy command shale " + shortcut.modelData.action
                    flat: true
                    implicitWidth: 30
                    implicitHeight: 30
                    cornerRadius: 8
                    onClicked: {
                        const command = "shale " + shortcut.modelData.action;
                        ShellState.run("clipboard.write", {text: command}, () => ShellState.message("Copied · " + command, "success"));
                    }
                }
            }
        }
    }
    C.Label {
        visible: root.error !== "" && root.errorAction === ""
        text: root.error
        color: Theme.dangerText
        font.pixelSize: Theme.small
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    C.Label {
        text: "Esc closes any open panel without a shortcut. Volume, brightness and media keys stay in your Hyprland config."
        color: Theme.textDim
        font.pixelSize: Theme.small
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    C.ResetButton {
        visible: root.listing.ready && root.anyChanged
        Layout.topMargin: Theme.gapS
        text: "Reset all shortcuts"
        description: "Hold to put every shortcut back to how Shale comes"
        armed: !root.busy
        onConfirmed: root.apply("", null)
    }
}
