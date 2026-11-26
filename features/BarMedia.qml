import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "../components" as C

BarKey {
    id: mediaButton
    // The bar this item is on: its screen, layout, weather and helpers.
    required property var bar
    // Narrow bars keep the cover but drop the title.
    readonly property bool wide: bar.width > 1500
    readonly property var player: NowPlaying.player
    readonly property string artist: player ? player.trackArtist || "" : ""
    shown: !!player && bar.width > 1100 && ShellState.setting("barMedia", true)
    leftPadding: 8
    rightPadding: wide ? 12 : 8
    implicitWidth: Math.min(implicitContentWidth + leftPadding + rightPadding, wide ? 300 : 36)
    hint: "Player"
    Accessible.name: player ? "Player, " + (player.trackTitle || player.identity) + (artist ? " by " + artist : "") : "Media controls"
    selected: bar.controlActive("media")
    onClicked: bar.toggleControl("media")
    Component.onCompleted: bar.mediaButton = mediaButton
    Component.onDestruction: if (bar.mediaButton === mediaButton) {
        bar.mediaButton = null;
        bar.mediaHovered = false;
    }
    HoverHandler {
        onHoveredChanged: bar.mediaHovered = hovered
    }
    contentItem: RowLayout {
        spacing: 8
        C.CoverArt {
            id: cover
            // Moves while playing: the live spectrum when the visualizer runs, otherwise three bars on a loop.
            readonly property bool live: bar.onScreen && mediaButton.visible && NowPlaying.playing && ShellState.setting("visualizer", true) && !Theme.reduced && !Theme.lowPower
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            radius: 5
            glyphSize: 12
            source: NowPlaying.artFile
            // Darkens the cover under the bars; without a cover it hides the placeholder note.
            Rectangle {
                anchors.fill: parent
                visible: NowPlaying.playing
                color: cover.ready ? Qt.rgba(0, 0, 0, 0.5) : Theme.key
            }
            C.Spectrum {
                id: spectrum
                anchors.centerIn: parent
                width: 9
                height: 10
                visible: active && available
                bars: 3
                spacing: 1.5
                floor: 2
                maxRadius: 1
                curve: 0.6
                color: Theme.accent
                secondary: Theme.accent
                active: cover.live
            }
            Row {
                id: meter
                anchors.centerIn: parent
                visible: NowPlaying.playing && !spectrum.visible
                height: 10
                spacing: 1.5
                Repeater {
                    model: [0.8, 0.5, 0.65]
                    Rectangle {
                        id: meterBar
                        required property real modelData
                        required property int index
                        width: 2
                        height: 10
                        color: Theme.accent
                        transform: Scale {
                            id: level
                            origin.y: 10
                            yScale: meterBar.modelData
                        }
                        SequentialAnimation {
                            running: cover.live && meter.visible
                            loops: Animation.Infinite
                            NumberAnimation { target: level; property: "yScale"; to: 0.95; duration: 290 + meterBar.index * 40; easing.type: Easing.InOutSine }
                            NumberAnimation { target: level; property: "yScale"; to: 0.45; duration: 220 + meterBar.index * 30; easing.type: Easing.InOutSine }
                            NumberAnimation { target: level; property: "yScale"; to: 0.8; duration: 210 + meterBar.index * 50; easing.type: Easing.InOutSine }
                            NumberAnimation { target: level; property: "yScale"; to: 0.25; duration: 300 + meterBar.index * 20; easing.type: Easing.InOutSine }
                        }
                    }
                }
            }
        }
        C.Label {
            visible: mediaButton.wide
            text: mediaButton.player ? mediaButton.player.trackTitle || mediaButton.player.identity : ""
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.maximumWidth: 170
        }
        C.Label {
            visible: mediaButton.wide && mediaButton.artist !== ""
            text: " · " + mediaButton.artist
            color: Theme.textDim
            font.pixelSize: 12
            Layout.fillWidth: true
            Layout.maximumWidth: 130
            Layout.leftMargin: -8
        }
    }
}
