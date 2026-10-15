import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import "../core"
import "../services"
import "../components" as C

// What one output shows while locked. `context` is the shared LockScreen (or a preview stand-in).
// Only counts are shown for notifications; their contents stay private.
Item {
    id: root
    required property var context
    property string screenName: ""
    readonly property string wallpaper: ShellState.activeWallpapers[screenName] || ShellState.activeWallpapers[Object.keys(ShellState.activeWallpapers)[0]] || ""
    readonly property var player: Services.player
    readonly property string user: Quickshell.env("USER") || ""
    // Glass panels: the surface tone at partial opacity over the blurred wallpaper.
    readonly property color glass: Qt.rgba(Theme.panel.r, Theme.panel.g, Theme.panel.b, 0.62)
    readonly property color glassEdge: Qt.rgba(1, 1, 1, 0.08)
    readonly property string face: Quickshell.env("HOME") + "/.face"
    property bool hasFace: false
    Process {
        command: ["test", "-r", root.face]
        running: true
        onExited: code => root.hasFace = code === 0
    }
    property real reveal: 0
    Component.onCompleted: reveal = 1
    opacity: context.unlocking ? 0 : reveal
    Behavior on opacity {
        NumberAnimation {
            duration: Theme.reduced ? 0 : 220
            easing.type: Easing.OutCubic
        }
    }
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // Blurred, dimmed wallpaper keeps the desktop's mood without showing its contents.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.mix(Theme.background, Theme.selection, 0.55) }
            GradientStop { position: 1; color: Theme.background }
        }
    }
    Image {
        id: backdrop
        anchors.fill: parent
        source: root.wallpaper ? "file://" + root.wallpaper.split("/").map(encodeURIComponent).join("/") : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        // Blur hides detail anyway; a small decode keeps memory and the blur pass cheap.
        sourceSize.width: 640
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: backdrop
        visible: backdrop.status === Image.Ready
        blurEnabled: true
        blurMax: 64
        blur: 1
        saturation: -0.1
        brightness: -0.06
    }
    // Darker at the edges so the clock and the bottom controls stay readable on any wallpaper.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.32) }
            GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.1) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.5) }
        }
    }

    // Status pill: waiting notifications and battery.
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 28
        visible: Services.batteryAvailable || Services.notificationModel.count > 0
        implicitWidth: statusRow.implicitWidth + 28
        implicitHeight: 36
        radius: height / 2
        color: root.glass
        border.width: 1
        border.color: root.glassEdge
        RowLayout {
            id: statusRow
            anchors.centerIn: parent
            spacing: Theme.gapM
            RowLayout {
                visible: Services.notificationModel.count > 0
                spacing: Theme.gapS
                C.Icon {
                    name: "bell"
                    size: 15
                }
                C.Label {
                    text: Services.notificationModel.count > 99 ? "99+" : String(Services.notificationModel.count)
                    font.pixelSize: Theme.small
                    font.weight: Font.Medium
                    font.features: {"tnum": 1}
                    elide: Text.ElideNone
                    Accessible.name: Services.notificationModel.count + " notifications waiting"
                }
            }
            RowLayout {
                visible: Services.batteryAvailable
                spacing: Theme.gapS
                C.Icon {
                    name: Services.batteryCharging ? "bolt" : "battery"
                    size: 15
                }
                C.Label {
                    text: Math.round(Services.batteryPercent) + "%"
                    font.pixelSize: Theme.small
                    font.weight: Font.Medium
                    font.features: {"tnum": 1}
                    elide: Text.ElideNone
                    color: !Services.batteryCharging && Services.batteryPercent <= 15 ? Theme.danger : Theme.text
                }
            }
        }
    }

    ColumnLayout {
        id: centre
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -30
        width: Math.min(parent.width - 48, 360)
        spacing: 0
        transform: Translate { y: Theme.reduced ? 0 : (1 - root.reveal) * 14 }
        C.Label {
            text: Qt.formatDateTime(clock.date, "dddd · d MMMM").toUpperCase()
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.95)
            font.pixelSize: 13
            font.weight: Font.DemiBold
            font.letterSpacing: 3
            elide: Text.ElideNone
            Layout.alignment: Qt.AlignHCenter
        }
        // Tabular figures keep the clock from shifting as the minutes change.
        C.Label {
            text: Qt.formatDateTime(clock.date, ShellState.setting("clock24h", true) ? "HH:mm" : "h:mm")
            font.pixelSize: 132
            font.weight: Font.ExtraLight
            font.letterSpacing: -4
            font.features: {"tnum": 1}
            elide: Text.ElideNone
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: -6
            Layout.bottomMargin: 36
        }
        // Your picture from ~/.face when there is one, otherwise your initial.
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 72
            Layout.preferredHeight: 72
            radius: 36
            color: Theme.selection
            border.width: 2
            border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55)
            C.Label {
                anchors.centerIn: parent
                visible: avatar.status !== Image.Ready
                text: root.user.charAt(0).toUpperCase()
                color: Theme.accentText
                font.pixelSize: 30
                font.weight: Font.Medium
                elide: Text.ElideNone
            }
            Image {
                id: avatar
                anchors.fill: parent
                anchors.margins: 3
                source: root.hasFace ? "file://" + root.face.split("/").map(encodeURIComponent).join("/") : ""
                sourceSize.width: 144
                sourceSize.height: 144
                fillMode: Image.PreserveAspectCrop
                visible: false
            }
            MultiEffect {
                anchors.fill: avatar
                source: avatar
                visible: avatar.status === Image.Ready
                maskEnabled: true
                maskSource: avatarMask
            }
            Item {
                id: avatarMask
                width: avatar.width
                height: avatar.height
                layer.enabled: true
                visible: false
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                }
            }
        }
        C.Label {
            text: root.user
            font.pixelSize: Theme.body + 1
            font.weight: Font.Medium
            elide: Text.ElideNone
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 12
            Layout.bottomMargin: 18
        }
        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(centre.width, 330)
            Layout.preferredHeight: 52
            // A short shake on a wrong password; reduced motion keeps only the message.
            transform: Translate { id: shakeOffset }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: shakeOffset; property: "x"; to: -10; duration: 45 }
                NumberAnimation { target: shakeOffset; property: "x"; to: 9; duration: 70 }
                NumberAnimation { target: shakeOffset; property: "x"; to: -6; duration: 60 }
                NumberAnimation { target: shakeOffset; property: "x"; to: 3; duration: 50 }
                NumberAnimation { target: shakeOffset; property: "x"; to: 0; duration: 40 }
            }
            Connections {
                target: root.context
                function onFailed() {
                    if (!Theme.reduced)
                        shake.restart();
                    field.forceActiveFocus();
                }
                function onPowerFailed() {
                    power.fired = false;
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
                leftPadding: 22
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
                    event.accepted = false;
                }
                background: Rectangle {
                    radius: height / 2
                    color: field.activeFocus ? Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.78) : root.glass
                    border.width: 1
                    border.color: root.context.status !== "" ? Theme.danger : field.activeFocus ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6) : root.glassEdge
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
        C.Label {
            // While PAM works, its own words: "Place your finger on the reader", "Touch your security key".
            readonly property string info: root.context.busy || root.context.prompt !== "" ? root.context.attemptMessage : ""
            readonly property string note: root.context.status !== "" ? root.context.status : info !== "" ? info : root.context.capsLock ? "Caps Lock is on" : ""
            text: note
            color: root.context.status !== "" ? Theme.danger : info !== "" ? Theme.text : Theme.warning
            font.pixelSize: Theme.small
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            opacity: note !== "" ? 1 : 0
            Layout.fillWidth: true
            Layout.topMargin: 12
            Layout.preferredHeight: Math.max(implicitHeight, 18)
            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
        }
    }

    // Bottom row: what's playing (with controls) and the power button.
    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 28
        spacing: Theme.gapL
        Rectangle {
            visible: !!root.player
            Layout.preferredWidth: Math.min(360, root.width / 2 - 40)
            implicitHeight: 68
            radius: 20
            color: root.glass
            border.width: 1
            border.color: root.glassEdge
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: Theme.gapM
                C.CoverArt {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    radius: 11
                    source: NowPlaying.artFile
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    C.Label {
                        text: root.player ? root.player.trackTitle || root.player.identity : ""
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                    }
                    C.Label {
                        text: root.player ? root.player.trackArtist || "" : ""
                        visible: text !== ""
                        color: Theme.muted
                        font.pixelSize: Theme.small
                        Layout.fillWidth: true
                    }
                }
                C.Button {
                    glyph: root.player && root.player.isPlaying ? "pause" : "play"
                    flat: true
                    implicitWidth: 38
                    implicitHeight: 38
                    cornerRadius: 19
                    focusPolicy: Qt.NoFocus
                    hint: root.player && root.player.isPlaying ? "Pause" : "Play"
                    enabled: !!root.player && root.player.canTogglePlaying
                    onClicked: root.player.togglePlaying()
                }
                C.Button {
                    glyph: "next"
                    flat: true
                    implicitWidth: 38
                    implicitHeight: 38
                    cornerRadius: 19
                    focusPolicy: Qt.NoFocus
                    hint: "Next track"
                    enabled: !!root.player && root.player.canGoNext
                    onClicked: root.player.next()
                }
            }
        }
        Item {
            Layout.fillWidth: true
        }
        // Shut down: press and hold, like the Power page, so a stray click never powers off.
        C.Label {
            id: powerHint
            property bool shown: false
            text: power.fired ? "Shutting down…" : power.pressed ? "Keep holding…" : "Hold to shut down"
            color: power.fired || power.pressed ? Theme.text : Theme.muted
            font.pixelSize: Theme.small
            font.weight: Font.Medium
            elide: Text.ElideNone
            opacity: shown || power.hovered || power.pressed || power.fired ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
            Timer {
                id: hintTimer
                interval: 2200
                onTriggered: powerHint.shown = false
            }
        }
        AbstractButton {
            id: power
            objectName: "powerButton"
            property real progress: 0
            property bool fired: false
            property double startedAt: 0
            readonly property int delay: 1200
            implicitWidth: 52
            implicitHeight: 52
            hoverEnabled: true
            // The password field keeps the keyboard.
            focusPolicy: Qt.NoFocus
            enabled: !fired && !root.context.unlocking
            Accessible.name: "Shut down"
            Accessible.description: "Press and hold to power off the computer."
            function cancel() {
                holdTimer.stop();
                progress = 0;
            }
            onPressed: {
                startedAt = Date.now();
                holdTimer.restart();
            }
            onReleased: {
                // A quick click explains what the button needs instead of doing nothing silently.
                if (!fired && progress < 1) {
                    powerHint.shown = true;
                    hintTimer.restart();
                }
                cancel();
                field.forceActiveFocus();
            }
            onCanceled: cancel()
            Timer {
                id: holdTimer
                interval: 16
                repeat: true
                onTriggered: {
                    if (!power.pressed) {
                        power.cancel();
                        return;
                    }
                    power.progress = Math.min(1, (Date.now() - power.startedAt) / power.delay);
                    if (power.progress >= 1) {
                        stop();
                        power.fired = true;
                        root.context.shutdown();
                    }
                }
            }
            background: Rectangle {
                radius: width / 2
                color: power.pressed || power.fired ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.22) : power.hovered ? Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.85) : root.glass
                border.width: 1
                border.color: power.hovered || power.pressed ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.5) : root.glassEdge
                Behavior on color { ColorAnimation { duration: Theme.fast } }
            }
            contentItem: Item {
                C.Icon {
                    anchors.centerIn: parent
                    name: "power"
                    size: 20
                }
                // Hold progress drawn as a ring around the button.
                Shape {
                    anchors.fill: parent
                    visible: power.progress > 0 || power.fired
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: Theme.danger
                        strokeWidth: 2.5
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: power.width / 2
                            centerY: power.height / 2
                            radiusX: power.width / 2 - 1.5
                            radiusY: power.height / 2 - 1.5
                            startAngle: -90
                            sweepAngle: 360 * (power.fired ? 1 : power.progress)
                        }
                    }
                }
            }
        }
    }
}
