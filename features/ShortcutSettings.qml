import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import "../core"
import "../core/keys.js" as KeyNames
import "../components" as C

// Settings → Shortcuts: each Shale shortcut, recorded by pressing the new keys.
ColumnLayout {
    id: root
    spacing: Theme.gapM
    // shortcuts.list: {ready, shortcuts: [{action, title, default, keys, changed}]}
    property var listing: ({ready: false, shortcuts: []})
    property bool loaded: false
    // The action whose keys are being recorded, and the modifiers held so far.
    property string recording: ""
    property string held: ""
    // True while Hyprland's empty recording submap is active, so bound keys reach the recorder.
    property bool submap: false
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
        });
    }
    function start(action) {
        stop();
        error = "";
        savedAction = "";
        recording = action;
        held = "";
        recorder.forceActiveFocus();
        Backend.request("shortcuts.record", {active: true}, (r, e) => {
            // Stopped meanwhile: leave the submap again.
            if (!e && r.active && root.recording !== action)
                Backend.request("shortcuts.record", {active: false});
            root.submap = !e && r.active && root.recording === action;
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
                return;
            }
            root.listing = r;
            root.savedAction = action || "*";
            savedTimer.restart();
        });
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
        text: !root.loaded ? "" : root.listing.ready ? "Choose Change, then press the new keys. Changes apply right away." : "Shortcuts come from the installed Hyprland fragment. Update Shale with ./install.sh --update to change them here; you can also copy a command to bind it yourself."
        visible: text !== ""
        color: Theme.muted
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    C.Group {
        Repeater {
            model: root.listing.shortcuts
            ColumnLayout {
                id: shortcut
                required property var modelData
                readonly property bool active: root.recording === modelData.action
                readonly property var caps: KeyNames.caps(active ? (root.held ? root.held + " + …" : "") : modelData.keys)
                Layout.fillWidth: true
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(40, Theme.body + 26)
                    Layout.leftMargin: Theme.gapM - 2
                    spacing: Theme.gapXs + 2
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        C.Label {
                            text: shortcut.modelData.title
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        C.Caption {
                            visible: text !== ""
                            text: shortcut.active ? "Press the new keys · Esc to cancel · Backspace for none"
                                : root.savedAction === shortcut.modelData.action || root.savedAction === "*" ? "Saved"
                                : shortcut.modelData.changed ? "Changed" : ""
                            color: shortcut.active ? Theme.accentText : root.savedAction === shortcut.modelData.action || root.savedAction === "*" ? Theme.success : Theme.muted
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                    C.Caption {
                        visible: !shortcut.active && !shortcut.modelData.keys
                        text: "Not set"
                        color: Theme.disabled
                    }
                    Repeater {
                        model: shortcut.caps
                        Rectangle {
                            required property string modelData
                            implicitWidth: Math.max(26, keyLabel.implicitWidth + 14)
                            implicitHeight: Math.max(24, Theme.caption + 12)
                            radius: Theme.radiusSmall - 2
                            color: shortcut.active ? Theme.selection : Theme.raised
                            C.Label {
                                id: keyLabel
                                anchors.centerIn: parent
                                text: parent.modelData
                                font.family: Theme.mono
                                font.pixelSize: Theme.caption
                                color: shortcut.active ? Theme.accentText : Theme.text
                            }
                        }
                    }
                    C.Button {
                        visible: root.listing.ready
                        text: shortcut.active ? "Cancel" : "Change"
                        flat: true
                        selected: shortcut.active
                        enabled: !root.busy
                        implicitHeight: 32
                        hint: (shortcut.active ? "Stop recording " : "Change the ") + shortcut.modelData.title + " shortcut"
                        onClicked: shortcut.active ? root.stop() : root.start(shortcut.modelData.action)
                    }
                    C.Button {
                        visible: root.listing.ready && shortcut.modelData.changed && !shortcut.active
                        glyph: "refresh"
                        hint: "Reset " + shortcut.modelData.title
                        flat: true
                        enabled: !root.busy
                        implicitWidth: 32
                        implicitHeight: 32
                        onClicked: root.apply(shortcut.modelData.action, null)
                    }
                    C.Button {
                        glyph: "copy"
                        hint: "Copy command shale " + shortcut.modelData.action
                        flat: true
                        implicitWidth: 32
                        implicitHeight: 32
                        onClicked: {
                            const command = "shale " + shortcut.modelData.action;
                            ShellState.run("clipboard.write", {text: command}, () => ShellState.message("Copied · " + command, "success"));
                        }
                    }
                }
                C.Label {
                    visible: root.error !== "" && root.errorAction === shortcut.modelData.action
                    text: root.error
                    color: Theme.danger
                    font.pixelSize: Theme.small
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.gapM - 2
                    Layout.bottomMargin: Theme.gapS
                }
            }
        }
    }
    C.Label {
        visible: root.error !== "" && root.errorAction === ""
        text: root.error
        color: Theme.danger
        font.pixelSize: Theme.small
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    C.Label {
        text: "Esc closes any open panel without a shortcut. Volume, brightness and media keys stay in your Hyprland config."
        color: Theme.muted
        font.pixelSize: Theme.small
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    C.ResetButton {
        visible: root.listing.ready && root.anyChanged
        text: "Reset all shortcuts"
        armed: !root.busy
        onConfirmed: root.apply("", null)
    }
}
