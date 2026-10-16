import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "../components" as C

// What's playing, with play/pause and next.
Rectangle {
    id: root
    readonly property var player: Services.player
    visible: !!player
    implicitHeight: 68
    radius: 20
    color: Qt.rgba(Theme.panel.r, Theme.panel.g, Theme.panel.b, 0.62)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)
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
