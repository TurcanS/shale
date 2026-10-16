import QtQuick
import "../core"
import "../components" as C

// The line under the password field: a failed check, PAM's own words while it works ("Place your finger on
// the reader", "Touch your security key"), or a Caps Lock warning.
C.Label {
    id: root
    required property var context
    readonly property string info: context.busy || context.prompt !== "" ? context.attemptMessage : ""
    readonly property string note: context.status !== "" ? context.status : info !== "" ? info : context.capsLock ? "Caps Lock is on" : ""
    text: note
    color: context.status !== "" ? Theme.danger : info !== "" ? Theme.text : Theme.warning
    font.pixelSize: Theme.small
    font.weight: Font.Medium
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    elide: Text.ElideNone
    opacity: note !== "" ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
}
