import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "../components" as C

// What's playing as a chip, "Title · Artist", with play/pause and next at its end.
Rectangle {
    id: root
    readonly property var player: Services.player
    // The most the chip may take; the title is shortened to fit.
    property real maxWidth: 360
    visible: !!player
    implicitWidth: Math.min(maxWidth, mediaRow.implicitWidth + 16)
    implicitHeight: 32
    radius: height / 2
    color: Theme.tint(Theme.caseColor, 0.55)
    RowLayout {
        id: mediaRow
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 4
        spacing: 2
        C.Label {
            readonly property string title: root.player ? root.player.trackTitle || root.player.identity : ""
            readonly property string artist: root.player ? root.player.trackArtist || "" : ""
            text: artist !== "" ? title + " · " + artist : title
            color: Theme.tint(Theme.text, 0.75)
            font.pixelSize: 13
            Layout.fillWidth: true
            Layout.maximumWidth: implicitWidth
            Layout.rightMargin: 4
        }
        C.Button {
            glyph: root.player && root.player.isPlaying ? "pause" : "play"
            flat: true
            implicitWidth: 24
            implicitHeight: 24
            cornerRadius: 12
            padding: 0
            focusPolicy: Qt.NoFocus
            hint: root.player && root.player.isPlaying ? "Pause" : "Play"
            enabled: !!root.player && root.player.canTogglePlaying
            onClicked: root.player.togglePlaying()
        }
        C.Button {
            glyph: "next"
            flat: true
            implicitWidth: 24
            implicitHeight: 24
            cornerRadius: 12
            padding: 0
            focusPolicy: Qt.NoFocus
            hint: "Next track"
            enabled: !!root.player && root.player.canGoNext
            onClicked: root.player.next()
        }
    }
}
