import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell.Services.Mpris
import Quickshell.Widgets
import "../core"
import "../services"
import "../components" as C
import "../core/format.js" as Format

// The Player: the cover with a live level strip on the left; source, title, seek and transport on the right. The
// equalizer lives in Control → Sound; "on <output>" goes there.
ColumnLayout {
    id: root
    property bool active: false
    readonly property var player: Services.player
    readonly property bool playing: !!player && player.isPlaying
    readonly property bool showRemaining: ShellState.setting("mediaRemaining", false)
    readonly property bool visualizerOn: ShellState.setting("visualizer", true)
    readonly property bool seekable: !!player && player.lengthSupported && player.positionSupported && player.length > 0
    function timeLabel(seconds) {
        return Format.clock(seconds);
    }
    function cycleLoop() {
        const order = [MprisLoopState.None, MprisLoopState.Playlist, MprisLoopState.Track];
        player.loopState = order[(order.indexOf(player.loopState) + 1) % order.length];
    }
    // The default output as its kind of device ("Headphones", "Speakers", "HDMI"), or its own short name.
    readonly property string outputLabel: {
        const sink = Services.output;
        if (!sink)
            return "";
        const name = sink.description || sink.nickname || sink.name || "";
        if (/hdmi|displayport/i.test(name))
            return "HDMI";
        if (/head(phone|set)|earbud|earphone|airpods|buds/i.test(name))
            return "Headphones";
        return name.replace(/\s+(analog|digital) (stereo|surround|mono).*$/i, "").replace(/^built-in audio$/i, "Speakers") || name;
    }
    spacing: Theme.gapM
    C.EmptyState {
        visible: !root.player
        Layout.fillWidth: true
        Layout.topMargin: 20
        Layout.bottomMargin: 12
        glyph: "music"
        title: "Nothing playing"
        description: "Play audio in an app to control it here"
    }
    RowLayout {
        visible: !!root.player
        Layout.fillWidth: true
        Layout.preferredHeight: 232
        spacing: 14
        // The cover, whole at the top, its blurred copy filling the rest; the level strip sits along the bottom.
        ClippingRectangle {
            id: coverTile
            Layout.preferredWidth: 150
            Layout.fillHeight: true
            radius: Theme.radiusModule
            color: Theme.module
            Image {
                id: artwork
                anchors.fill: parent
                source: NowPlaying.artFile
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 300
                visible: false
            }
            MultiEffect {
                anchors.fill: parent
                source: artwork
                visible: artwork.status === Image.Ready
                blurEnabled: !Theme.lowPower
                blur: 1
                blurMax: 48
                brightness: -0.4
                saturation: -0.1
                opacity: artwork.status === Image.Ready ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.enter
                    }
                }
            }
            Image {
                id: cover
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: width
                source: artwork.source
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 300
                sourceSize.height: 300
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.enter
                    }
                }
            }
            // The cover's lower edge melts into the blur, so the strip below reads as one tile.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                y: cover.height - height
                height: 36
                visible: cover.status === Image.Ready
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.35) }
                }
            }
            C.Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 75 - height / 2
                visible: artwork.status !== Image.Ready
                name: "music"
                size: 30
                color: Theme.textDim
            }
            // Live levels from the shared cava while playing; quiet stubs otherwise. Motion-sensitive and
            // battery-saving setups never start cava.
            C.Spectrum {
                id: spectrum
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 12
                height: 26
                bars: 12
                spacing: 3
                maxRadius: 2
                curve: 0.7
                color: Theme.accent
                secondary: Theme.accent
                active: root.active && root.playing && root.visualizerOn && !Theme.reduced && !Theme.lowPower && !ShellState.locked
                visible: active && available
            }
            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 12
                visible: !spectrum.visible
                spacing: 3
                Repeater {
                    model: 12
                    Rectangle {
                        width: (126 - 11 * 3) / 12
                        height: 3
                        radius: 1.5
                        color: root.playing ? Theme.accent : Theme.key
                        opacity: root.playing ? 0.6 : 1
                    }
                }
            }
            HoverHandler {
                id: coverHover
            }
            C.Button {
                visible: spectrum.available && !Theme.reduced
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 6
                implicitWidth: 28
                implicitHeight: 28
                cornerRadius: 14
                flat: true
                glyph: "visualizer"
                foreground: root.visualizerOn ? Theme.accent : Theme.text
                opacity: coverHover.hovered || visualFocus ? 1 : 0
                hint: root.visualizerOn ? "Hide visualizer" : "Show visualizer"
                Accessible.role: Accessible.CheckBox
                Accessible.checkable: true
                Accessible.checked: root.visualizerOn
                onClicked: ShellState.setSetting("visualizer", !root.visualizerOn)
                background: Rectangle {
                    radius: 14
                    color: Qt.rgba(0, 0, 0, 0.45)
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.fast
                    }
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            spacing: 4
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                // The source: which app plays, its dot lit while it plays.
                Rectangle {
                    implicitWidth: sourceRow.implicitWidth + 16
                    implicitHeight: 24
                    radius: 12
                    color: Theme.module
                    Layout.maximumWidth: 160
                    Row {
                        id: sourceRow
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - 16)
                        spacing: 6
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6
                            height: 6
                            radius: 3
                            color: root.playing ? Theme.accent : Theme.textFaint
                        }
                        C.Label {
                            width: Math.min(implicitWidth, 130)
                            text: root.player ? root.player.identity : ""
                            color: Theme.textSecondary
                            font.pixelSize: 12
                        }
                    }
                }
                C.Button {
                    visible: root.outputLabel !== ""
                    text: "on " + root.outputLabel
                    flat: true
                    implicitHeight: 24
                    leftPadding: 4
                    rightPadding: 4
                    labelSize: 12
                    cornerRadius: 8
                    foreground: hovered || visualFocus ? Theme.textSecondary : Theme.textDim
                    hint: "Sound and equalizer"
                    Layout.minimumWidth: 0
                    onClicked: ShellState.detail = "audio"
                }
                Item {
                    Layout.fillWidth: true
                }
            }
            C.Label {
                text: root.player ? (root.player.trackTitle || "Unknown track") : ""
                font.pixelSize: 19
                font.weight: 650
                lineHeight: 1.1
                maximumLineCount: 2
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                Layout.topMargin: 8
            }
            C.Label {
                text: root.player ? [root.player.trackArtist || root.player.identity, root.player.trackAlbum].filter(part => !!part).join(" · ") : ""
                color: Theme.textMuted
                font.pixelSize: 14
                Layout.fillWidth: true
            }
            Item {
                Layout.fillHeight: true
            }
            Slider {
                id: seek
                visible: root.seekable
                Layout.fillWidth: true
                implicitHeight: 18
                padding: 0
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
                background: Rectangle {
                    x: seek.leftPadding
                    y: (seek.height - height) / 2
                    width: seek.availableWidth
                    height: 4
                    radius: 2
                    color: Theme.key
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
                    width: 12
                    height: 12
                    radius: 6
                    color: Theme.knob
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, 0.35)
                    C.FocusRing {
                        visible: seek.visualFocus
                        inset: 4
                    }
                    scale: seek.pressed && !Theme.reduced ? 1.2 : 1
                    Behavior on scale {
                        NumberAnimation {
                            duration: Theme.fast
                        }
                    }
                }
            }
            RowLayout {
                visible: root.seekable
                Layout.fillWidth: true
                C.Label {
                    text: root.timeLabel(seek.value)
                    color: Theme.textDim
                    font.pixelSize: 11
                    font.features: ({"tnum": 1})
                }
                Item {
                    Layout.fillWidth: true
                }
                C.Label {
                    text: root.showRemaining ? "-" + root.timeLabel((root.player ? root.player.length : 0) - seek.value) : root.timeLabel(root.player ? root.player.length : 0)
                    color: remainingArea.containsMouse ? Theme.text : Theme.textDim
                    font.pixelSize: 11
                    font.features: ({"tnum": 1})
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
            // Shuffle, previous, the big round play, next, repeat. Unsupported modes keep their space.
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 0
                C.Button {
                    readonly property bool lit: enabled && root.player.shuffle
                    glyph: "shuffle"
                    implicitWidth: 34
                    implicitHeight: 34
                    flat: true
                    enabled: !!root.player && root.player.shuffleSupported
                    opacity: enabled ? 1 : 0
                    foreground: lit ? Theme.accent : hovered || visualFocus ? Theme.text : Theme.textDim
                    hint: lit ? "Turn off shuffle" : "Shuffle"
                    Accessible.role: Accessible.CheckBox
                    Accessible.checkable: true
                    Accessible.checked: lit
                    onClicked: root.player.shuffle = !root.player.shuffle
                }
                Item {
                    Layout.fillWidth: true
                }
                TransportKey {
                    glyph: "previous"
                    hint: "Previous track"
                    enabled: !!root.player && root.player.canGoPrevious
                    onClicked: root.player.previous()
                }
                Item {
                    Layout.fillWidth: true
                }
                Item {
                    implicitWidth: 50
                    implicitHeight: 50
                    // A soft accent glow under the play key.
                    RectangularShadow {
                        anchors.fill: playKey
                        visible: !Theme.lowPower && playKey.enabled
                        radius: 25
                        blur: 18
                        offset.y: 6
                        color: Theme.tint(Theme.accent, 0.3)
                    }
                    C.Button {
                        id: playKey
                        anchors.fill: parent
                        glyph: root.playing ? "pause" : "play"
                        accent: true
                        cornerRadius: 25
                        hint: root.playing ? "Pause" : "Play"
                        enabled: !!root.player && root.player.canTogglePlaying
                        onClicked: root.player.togglePlaying()
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                TransportKey {
                    glyph: "next"
                    hint: "Next track"
                    enabled: !!root.player && root.player.canGoNext
                    onClicked: root.player.next()
                }
                Item {
                    Layout.fillWidth: true
                }
                C.Button {
                    readonly property int loop: enabled ? root.player.loopState : MprisLoopState.None
                    glyph: loop === MprisLoopState.Track ? "repeat-one" : "repeat"
                    implicitWidth: 34
                    implicitHeight: 34
                    flat: true
                    enabled: !!root.player && root.player.loopSupported
                    opacity: enabled ? 1 : 0
                    foreground: loop !== MprisLoopState.None ? Theme.accent : hovered || visualFocus ? Theme.text : Theme.textDim
                    hint: loop === MprisLoopState.None ? "Repeat all" : loop === MprisLoopState.Playlist ? "Repeat this track" : "Turn off repeat"
                    onClicked: root.cycleLoop()
                }
            }
        }
    }
    // More than one player: choose which one this page follows.
    Flow {
        visible: Services.players.length > 1 || Services.selectedPlayer !== ""
        Layout.fillWidth: true
        spacing: Theme.gapS
        C.Chip {
            text: "Automatic"
            hint: "Follow the active player"
            selected: Services.selectedPlayer === ""
            onClicked: Services.selectedPlayer = ""
        }
        Repeater {
            model: Services.players
            C.Chip {
                required property var modelData
                text: modelData.identity
                hint: "Control " + modelData.identity
                selected: Services.selectedPlayer === modelData.dbusName
                onClicked: Services.selectedPlayer = modelData.dbusName
            }
        }
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.active && root.playing && !seek.pressed
        onTriggered: root.player.positionChanged()
    }
    // Previous and next: 38 px module keys with 12 px corners.
    component TransportKey: C.Button {
        id: key
        implicitWidth: 38
        implicitHeight: 38
        cornerRadius: Theme.radiusCard
        background: Rectangle {
            radius: Theme.radiusCard
            color: key.hovered || key.down || key.visualFocus ? Theme.mix(Theme.module, Theme.text, 0.06) : Theme.module
            opacity: key.enabled ? 1 : Theme.disabledOpacity
            Behavior on color {
                ColorAnimation {
                    duration: Theme.fast
                }
            }
        }
    }
}
