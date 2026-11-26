import QtQuick
import QtQuick.Layouts
import "../core"

// A plain on/off preference on a group.
Toggle {
    property string key: ""
    property bool fallback: false
    settingKey: key
    flat: true
    Layout.fillWidth: true
    selected: ShellState.setting(key, fallback)
    onClicked: ShellState.setSetting(key, !ShellState.setting(key, fallback))
}
