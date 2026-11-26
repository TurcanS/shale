import QtQuick
import QtQuick.Layouts
import "../core"
import "." as C

// A folder setting with its own error and a short confirmation once saved.
SettingRow {
    id: folder
    property string key: ""
    property string fallback: ""
    property string note: ""
    property string error: ""
    property bool saved: false
    function save(value) {
        const path = value.trim();
        if (!(path.startsWith("~/") || path.startsWith("/")) || /[\r\n]/.test(path)) {
            error = "Enter an absolute folder path or a path beginning with ~/";
            return;
        }
        error = "";
        if (path === ShellState.setting(key, fallback))
            return;
        ShellState.setSetting(key, path);
        saved = true;
        savedTimer.restart();
    }
    settingKey: key
    description: error || (saved ? "Saved" : note)
    descriptionColor: error ? Theme.dangerText : saved ? Theme.success : Theme.textDim
    C.Field {
        Layout.preferredWidth: 280
        implicitHeight: 36
        font.pixelSize: Theme.label
        Accessible.name: folder.label
        text: ShellState.setting(folder.key, folder.fallback)
        onTextEdited: folder.saved = false
        onEditingFinished: folder.save(text)
    }
    Timer {
        id: savedTimer
        interval: 2500
        onTriggered: folder.saved = false
    }
}
