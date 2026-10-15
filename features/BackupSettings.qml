import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

// Settings → Backup: copy your settings to a file, and bring them back here or on another computer.
ColumnLayout {
    id: root
    spacing: Theme.gapM
    property bool busy: false
    property string result: ""
    property bool failed: false
    function transfer(method) {
        busy = true;
        result = "";
        Backend.request(method, {path: pathField.text.trim()}, (r, e) => {
            busy = false;
            failed = !!e;
            if (e) {
                result = e.message;
                return;
            }
            if (method === "settings.export") {
                result = r.count ? "Saved " + r.count + " setting" + (r.count === 1 ? "" : "s") + " to " + r.path : "Saved to " + r.path + ". Everything is at its default, so there was nothing to save.";
                return;
            }
            ShellState.settings = r.settings;
            ShellState.settingsSaved();
            result = (r.applied.length ? "Applied " + r.applied.length + " setting" + (r.applied.length === 1 ? "" : "s") + "." : "Nothing to apply.")
                + (r.skipped.length ? " Skipped " + r.skipped.join(", ") + (r.skipped.indexOf("shortcuts") >= 0 ? " (their keys are taken here)" : "") + "." : "")
                + (r.problem ? " " + r.problem : "");
            failed = !!r.problem;
        });
    }
    C.Label {
        text: "Save your settings to a file to keep a copy or move them to another computer. Usage history, pinned apps, your weather location and folders stay out of it."
        color: Theme.muted
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    C.Label {
        text: "File"
        Layout.fillWidth: true
        Layout.topMargin: Theme.gapS
    }
    C.Field {
        id: pathField
        Layout.fillWidth: true
        Accessible.name: "Backup file"
        text: "~/shale-settings.json"
        onTextEdited: root.result = ""
        onAccepted: root.transfer("settings.export")
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.gapS
        C.Button {
            text: "Export"
            glyph: "copy"
            accent: true
            enabled: !root.busy && Backend.ready
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            onClicked: root.transfer("settings.export")
        }
        C.Button {
            text: "Import"
            glyph: "folder"
            enabled: !root.busy && Backend.ready
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            onClicked: root.transfer("settings.import")
        }
    }
    C.Label {
        visible: root.result !== ""
        text: root.result
        color: root.failed ? Theme.danger : Theme.success
        font.pixelSize: Theme.small
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    C.Caption {
        text: "Importing replaces the settings the file has and keeps the rest. Shortcuts come along when their keys are free on this computer. The settings from before each change are kept in ~/.config/shale/config.previous.json."
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        Layout.topMargin: Theme.gapS
    }
}
