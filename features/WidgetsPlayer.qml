import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "../components" as C

// The Player card: the cover, the track and artist, and previous / play / next. With nothing playing it says so and
// keeps its place. A click beside the keys opens Control.
WidgetsCard {
    id: root
    readonly property var player: Services.player
    panel: "control"
    padding: 16
    Accessible.role: Accessible.Grouping
    Accessible.name: player ? "Playing " + (player.trackTitle || player.identity) : "Nothing playing"
    ColumnLayout {
        anchors.fill: parent
        spacing: 12
        RowLayout {
            spacing: 12
            Layout.fillWidth: true
            C.CoverArt {
                source: root.player ? root.player.trackArtUrl || "" : ""
                implicitWidth: 84
                implicitHeight: 84
                radius: 14
            }
            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true
                C.Label {
                    text: root.player ? root.player.identity || "Player" : "Player"
                    color: Theme.textDim
                    font.pixelSize: 12
                    Layout.fillWidth: true
                }
                C.Label {
                    text: root.player ? root.player.trackTitle || "Unknown track" : "Nothing playing"
                    font.pixelSize: 17
                    font.weight: 650
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    Layout.fillWidth: true
                }
                C.Label {
                    visible: text !== ""
                    text: root.player ? root.player.trackArtist || "" : ""
                    color: Theme.textSecondary
                    font.pixelSize: 13
                    Layout.fillWidth: true
                }
            }
        }
        Item {
            Layout.fillHeight: true
        }
        RowLayout {
            spacing: 8
            Layout.alignment: Qt.AlignHCenter
            C.Button {
                glyph: "previous"
                hint: "Previous"
                implicitWidth: 44
                implicitHeight: 44
                enabled: !!root.player && root.player.canGoPrevious
                onClicked: root.player.previous()
            }
            C.Button {
                glyph: root.player && root.player.isPlaying ? "pause" : "play"
                hint: root.player && root.player.isPlaying ? "Pause" : "Play"
                accent: true
                implicitWidth: 56
                implicitHeight: 44
                enabled: !!root.player && root.player.canTogglePlaying
                onClicked: root.player.togglePlaying()
            }
            C.Button {
                glyph: "next"
                hint: "Next"
                implicitWidth: 44
                implicitHeight: 44
                enabled: !!root.player && root.player.canGoNext
                onClicked: root.player.next()
            }
        }
    }
}
