import QtQuick
import QtQuick.Controls
import "../core"
import "../components" as C

// The password field with its unlock button. Typing on one screen shows on all of them; each style adds
// its own motion for a wrong password.
Item {
    id: root
    required property var context
    readonly property alias masked: field.masked
    readonly property alias fieldFocus: field.activeFocus
    // Room on the left for something drawn over the field, such as your picture.
    property int leftInset: 22
    // Any key reaching the field, for styles that wake on activity.
    signal keyPressed()
    function focusField() {
        field.forceActiveFocus();
    }
    implicitWidth: 330
    implicitHeight: 52
    Connections {
        target: root.context
        function onFailed() {
            field.forceActiveFocus();
        }
        function onPasswordChanged() {
            if (field.text !== root.context.password)
                field.text = root.context.password;
        }
    }
    TextField {
        id: field
        // PAM's follow-up questions, such as a one-time code, may show what is typed.
        readonly property bool masked: root.context.prompt === "" || !root.context.promptVisible
        anchors.fill: parent
        focus: true
        echoMode: masked ? TextInput.Password : TextInput.Normal
        passwordCharacter: "●"
        enabled: !root.context.busy && !root.context.unlocking
        placeholderText: root.context.prompt || (root.context.busy ? "Checking…" : "Enter password")
        placeholderTextColor: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.5)
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: text === "" || !masked ? Theme.body + 1 : 12
        font.letterSpacing: text === "" || !masked ? 0 : 4
        selectionColor: Theme.selectionHover
        leftPadding: root.leftInset
        rightPadding: 56
        verticalAlignment: TextInput.AlignVCenter
        Accessible.name: root.context.prompt || "Password"
        Component.onCompleted: {
            // A screen added while locked picks up what was already typed.
            text = root.context.password;
            forceActiveFocus();
        }
        // Back after a check, possibly with PAM's next question.
        onEnabledChanged: if (enabled)
            forceActiveFocus()
        onActiveFocusChanged: if (activeFocus)
            capsWatch.restart()
        onTextChanged: if (root.context.password !== text)
            root.context.password = text
        onAccepted: root.context.submit()
        Keys.onEscapePressed: root.context.cancel()
        Keys.onPressed: event => {
            capsWatch.restart();
            root.keyPressed();
            event.accepted = false;
        }
        background: Rectangle {
            radius: height / 2
            color: field.activeFocus ? Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.78) : Qt.rgba(Theme.panel.r, Theme.panel.g, Theme.panel.b, 0.62)
            border.width: 1
            border.color: root.context.status !== "" ? Theme.danger : field.activeFocus ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6) : Qt.rgba(1, 1, 1, 0.08)
            Behavior on color { ColorAnimation { duration: Theme.fast } }
            Behavior on border.color { ColorAnimation { duration: Theme.fast } }
        }
    }
    // Caps Lock is checked each second only while this field has the keyboard and someone
    // pressed a key in the last half minute, so an idle lock screen does no polling.
    Timer {
        id: capsWatch
        interval: 30000
    }
    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: field.activeFocus && capsWatch.running
        onTriggered: root.context.checkCapsLock()
    }
    C.Button {
        anchors.right: parent.right
        anchors.rightMargin: 7
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: 38
        implicitHeight: 38
        cornerRadius: 19
        accent: root.context.password !== ""
        flat: root.context.password === ""
        glyph: "chevron"
        hint: "Unlock"
        enabled: root.context.password !== "" && !root.context.busy
        focusPolicy: Qt.NoFocus
        onClicked: root.context.submit()
    }
}
