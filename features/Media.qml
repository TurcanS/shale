import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell.Services.Mpris
import "../core"
import "../services"
import "../components" as C

ColumnLayout {
    id: root
    property bool active: false
    readonly property var player: Services.player
    readonly property bool playing: !!player && player.isPlaying
    readonly property bool showRemaining: ShellState.setting("mediaRemaining", false)
    readonly property bool visualizerOn: ShellState.setting("visualizer", true)
    function timeLabel(seconds) {
        if (!isFinite(seconds) || seconds < 0)
            return "0:00";
        return Math.floor(seconds / 60) + ":" + String(Math.floor(seconds % 60)).padStart(2, "0");
    }
    readonly property var artColors: NowPlaying.artColors
    function cycleLoop() {
        const order = [MprisLoopState.None, MprisLoopState.Playlist, MprisLoopState.Track];
        player.loopState = order[(order.indexOf(player.loopState) + 1) % order.length];
    }
    spacing: Theme.gapL
    C.EmptyState {
        visible: !root.player
        Layout.fillWidth: true
        Layout.topMargin: 20
        Layout.bottomMargin: 12
        glyph: "music"
        title: "Nothing playing"
        description: "Play audio in an app to control it here"
    }
    Rectangle {
        visible: !!root.player
        Layout.fillWidth: true
        Layout.preferredHeight: 176
        radius: Theme.controlRadius
        color: Theme.surface
        clip: true
        Image {
            id: artwork
            anchors.fill: parent
            source: NowPlaying.artFile
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 700
            visible: false
        }
        // Blurred, dimmed backdrop so square covers are shown whole instead of cropped to a banner.
        MultiEffect {
            anchors.fill: parent
            source: artwork
            visible: artwork.status === Image.Ready
            blurEnabled: !Theme.lowPower
            blur: 1
            blurMax: 48
            brightness: -0.35
            saturation: -0.1
            opacity: artwork.status === Image.Ready ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.reduced ? 0 : Theme.enter
                }
            }
        }
        Image {
            id: cover
            anchors.centerIn: parent
            width: parent.height - 32
            height: width
            source: artwork.source
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            sourceSize.width: 400
            visible: artwork.status === Image.Ready
            opacity: status === Image.Ready ? 1 : 0
            layer.enabled: !Theme.lowPower
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowBlur: 0.8
                shadowOpacity: 0.55
                shadowVerticalOffset: 4
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.reduced ? 0 : Theme.enter
                }
            }
        }
        Rectangle {
            anchors.centerIn: parent
            width: 124
            height: 124
            radius: Theme.panelRadius
            color: Theme.raised
            visible: artwork.status !== Image.Ready
            Rectangle {
                anchors.centerIn: parent
                width: 76
                height: 76
                radius: Theme.controlRadius
                color: Theme.hover
                C.Icon {
                    anchors.centerIn: parent
                    name: "music"
                    size: 26
                    opacity: 0.8
                }
            }
        }
        // Darkens the lower edge so the bars stay readable over bright covers.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 84
            opacity: spectrum.opacity
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.55) }
            }
        }
        // Drawn over the cover, tinted from the artwork's own palette.
        C.Spectrum {
            id: spectrum
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            height: 64
            color: root.artColors[0]
            secondary: root.artColors[1]
            // Motion-sensitive and battery-saving setups never start cava.
            active: root.active && root.playing && root.visualizerOn && !Theme.reduced && !Theme.lowPower && !ShellState.locked
            opacity: active ? 0.9 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.enter
                }
            }
        }
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 10
            width: Math.min(parent.width / 2 - 20, playerName.implicitWidth + 16)
            height: 24
            radius: Theme.controlRadius
            color: Qt.rgba(0, 0, 0, 0.4)
            C.Label {
                id: playerName
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width - 16)
                text: root.player ? root.player.identity : ""
                font.pixelSize: Theme.caption
            }
        }
        C.Button {
            visible: spectrum.available && !Theme.reduced
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 6
            implicitWidth: 32
            implicitHeight: 32
            cornerRadius: 16
            flat: true
            glyph: "visualizer"
            selected: root.visualizerOn
            opacity: selected || hovered ? 1 : 0.6
            hint: root.visualizerOn ? "Hide visualizer" : "Show visualizer"
            Accessible.role: Accessible.CheckBox
            Accessible.checkable: true
            Accessible.checked: selected
            onClicked: ShellState.setSetting("visualizer", !root.visualizerOn)
        }
    }
    ColumnLayout {
        visible: !!root.player
        Layout.fillWidth: true
        spacing: Theme.gapXs
        C.Label {
            text: root.player ? (root.player.trackTitle || "Unknown track") : ""
            font.pixelSize: Math.max(20, Theme.body + 4)
            font.weight: Font.DemiBold
            Layout.fillWidth: true
            maximumLineCount: 2
            wrapMode: Text.Wrap
        }
        C.Label {
            text: root.player ? [root.player.trackArtist || root.player.identity, root.player.trackAlbum].filter(part => !!part).join(" · ") : ""
            color: Theme.muted
            Layout.fillWidth: true
            maximumLineCount: 2
            wrapMode: Text.WordWrap
        }
    }
    ColumnLayout {
        visible: !!root.player && root.player.lengthSupported && root.player.positionSupported && root.player.length > 0
        Layout.fillWidth: true
        spacing: 2
        Slider {
            id: seek
            Layout.fillWidth: true
            enabled: !!root.player && root.player.canSeek
            from: 0
            to: root.player ? Math.max(1, root.player.length) : 1
            value: root.player ? root.player.position : 0
            stepSize: 5
            hoverEnabled: true
            Accessible.name: "Track position"
            // Seek once on release rather than on every drag step.
            onPressedChanged: if (!pressed && root.player)
                root.player.position = value
            onMoved: if (!pressed && root.player)
                root.player.position = value
            implicitHeight: 24
            background: Rectangle {
                x: seek.leftPadding
                y: (seek.height - height) / 2
                width: seek.availableWidth
                height: seek.hovered || seek.pressed ? 6 : 4
                radius: height / 2
                color: Theme.raised
                Behavior on height {
                    NumberAnimation {
                        duration: Theme.fast
                    }
                }
                Rectangle {
                    width: parent.width * seek.visualPosition
                    height: parent.height
                    radius: parent.radius
                    color: Theme.accent
                }
            }
            handle: Rectangle {
                x: seek.leftPadding + seek.visualPosition * (seek.availableWidth - width)
                y: (seek.height - height) / 2
                visible: seek.enabled
                width: seek.pressed ? 16 : seek.hovered ? 14 : 10
                height: width
                radius: width / 2
                color: Theme.accent
                Behavior on width {
                    NumberAnimation {
                        duration: Theme.fast
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            C.Label {
                text: root.timeLabel(seek.value)
                font.family: Theme.mono
                font.pixelSize: Theme.caption
                color: Theme.muted
            }
            Item {
                Layout.fillWidth: true
            }
            C.Label {
                text: root.showRemaining ? "-" + root.timeLabel((root.player ? root.player.length : 0) - seek.value) : root.timeLabel(root.player ? root.player.length : 0)
                font.family: Theme.mono
                font.pixelSize: Theme.caption
                color: remainingArea.containsMouse ? Theme.text : Theme.muted
                Accessible.role: Accessible.Button
                Accessible.name: root.showRemaining ? "Show track length" : "Show remaining time"
                MouseArea {
                    id: remainingArea
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ShellState.setSetting("mediaRemaining", !root.showRemaining)
                }
            }
        }
    }
    RowLayout {
        visible: !!root.player
        Layout.alignment: Qt.AlignHCenter
        spacing: Theme.gapM
        // Unsupported modes keep their space so play/pause stays centred.
        C.Button {
            glyph: "shuffle"
            implicitWidth: 36
            implicitHeight: Theme.controlHeight
            cornerRadius: 18
            flat: true
            enabled: !!root.player && root.player.shuffleSupported
            opacity: enabled ? 1 : 0
            selected: enabled && root.player.shuffle
            hint: selected ? "Turn off shuffle" : "Shuffle"
            Accessible.role: Accessible.CheckBox
            Accessible.checkable: true
            Accessible.checked: selected
            onClicked: root.player.shuffle = !root.player.shuffle
        }
        C.Button {
            glyph: "previous"
            implicitWidth: 44
            implicitHeight: Theme.controlLarge
            cornerRadius: 22
            hint: "Previous track"
            enabled: !!root.player && root.player.canGoPrevious
            onClicked: root.player.previous()
        }
        C.Button {
            glyph: root.playing ? "pause" : "play"
            accent: true
            hint: root.playing ? "Pause" : "Play"
            implicitWidth: 56
            implicitHeight: 56
            cornerRadius: 28
            enabled: !!root.player && root.player.canTogglePlaying
            onClicked: root.player.togglePlaying()
        }
        C.Button {
            glyph: "next"
            implicitWidth: 44
            implicitHeight: Theme.controlLarge
            cornerRadius: 22
            hint: "Next track"
            enabled: !!root.player && root.player.canGoNext
            onClicked: root.player.next()
        }
        C.Button {
            readonly property int loop: enabled ? root.player.loopState : MprisLoopState.None
            glyph: loop === MprisLoopState.Track ? "repeat-one" : "repeat"
            implicitWidth: 36
            implicitHeight: Theme.controlHeight
            cornerRadius: 18
            flat: true
            enabled: !!root.player && root.player.loopSupported
            opacity: enabled ? 1 : 0
            selected: loop !== MprisLoopState.None
            hint: loop === MprisLoopState.None ? "Repeat all" : loop === MprisLoopState.Playlist ? "Repeat this track" : "Turn off repeat"
            onClicked: root.cycleLoop()
        }
    }
    Flow {
        visible: Services.players.length > 1 || Services.selectedPlayer !== ""
        Layout.fillWidth: true
        spacing: Theme.gapS
        C.Button {
            text: "Automatic"
            implicitHeight: 30
            cornerRadius: 15
            hint: "Follow the active player"
            selected: Services.selectedPlayer === ""
            onClicked: Services.selectedPlayer = ""
        }
        Repeater {
            model: Services.players
            C.Button {
                required property var modelData
                text: modelData.identity
                implicitHeight: 30
                cornerRadius: 15
                hint: "Control " + modelData.identity
                selected: Services.selectedPlayer === modelData.dbusName
                onClicked: Services.selectedPlayer = modelData.dbusName
            }
        }
    }
    Equalizer {
        Layout.fillWidth: true
        active: root.active
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.active && root.playing && !seek.pressed
        onTriggered: root.player.positionChanged()
    }
}
