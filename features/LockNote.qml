import QtQuick
import "../core"
import "../components" as C

// The line under the password field: a failed check, PAM's own words while it works ("Place your finger on
// the reader", "Touch your security key"), or the Caps Lock state, quiet while it is off.
C.Label {
    id: root
    required property var context
    readonly property string info: context.busy || context.prompt !== "" ? context.attemptMessage : ""
    readonly property string note: context.status !== "" ? context.status : info !== "" ? info : context.capsLock ? "Caps Lock is on" : ""
    text: note !== "" ? note : "Caps Lock is off"
    color: context.status !== "" ? Theme.dangerText : info !== "" ? Theme.text : context.capsLock ? Theme.warning : Theme.tint(Theme.text, 0.55)
    font.pixelSize: 13
    font.weight: note !== "" ? Font.Medium : Font.Normal
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    elide: Text.ElideNone
    Behavior on color { ColorAnimation { duration: Theme.fast } }
}
