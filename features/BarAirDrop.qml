import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "../components" as C

// AirDrop while it does something: a quiet key while listening in the background, an accent chip while visible
// (with the minutes left), looking for devices, asking or moving files (with a small ring for the share done). When
// something went wrong (receiving in the background couldn't start, Wi-Fi was left paused) the key shows an alert
// until the panel's message is dismissed or dealt with.
// Opens the AirDrop panel; a file dragged over it for a moment opens the panel too, so the drop lands there.
BarLiveChip {
    id: chip
    // The bar this item is on: its screen, layout, weather and helpers.
    required property var bar
    readonly property bool live: AirDrop.mode === "visible" || AirDrop.looking || AirDrop.progress >= 0 || AirDrop.countPending > 0
                                 || AirDrop.receiverState === "waking"
    readonly property string label: {
        if (AirDrop.countPending > 0)
            return AirDrop.countPending === 1 ? "Request" : AirDrop.countPending + " requests";
        if (AirDrop.progress >= 0)
            return Math.round(AirDrop.progress * 100) + "%";
        if (AirDrop.looking)
            return "Looking";
        if (AirDrop.mode === "visible")
            return Math.ceil(AirDrop.visibleLeft / 60) + " min";
        return "";
    }
    readonly property bool trouble: !!AirDrop.error && !live
    // Going live (visible, looking, a request, files moving), the chip warms up.
    onLiveChanged: if (live) flash()
    shown: AirDrop.available && (AirDrop.active || !!AirDrop.error)
    rest: live ? Theme.accentSoft : "transparent"
    foreground: live ? Theme.accentText : trouble ? Theme.dangerText : Theme.text
    leftPadding: label ? 9 : 0
    rightPadding: label ? 10 : 0
    implicitWidth: label ? implicitContentWidth + leftPadding + rightPadding : 28
    selected: ShellState.panel === "airdrop" && ShellState.screenName === bar.outputName
    hint: (AirDrop.countPending > 0 ? "AirDrop request waiting"
        : AirDrop.sending && AirDrop.sending.phase === "sending" ? "AirDrop · sending to " + AirDrop.sending.name
        : AirDrop.incomingNow ? "AirDrop · receiving from " + (AirDrop.incomingNow.sender || "a device nearby")
        : AirDrop.mode === "visible" ? "AirDrop · visible for " + Math.ceil(AirDrop.visibleLeft / 60) + " more min"
        : AirDrop.mode === "background" ? "AirDrop · listening in the background" : "AirDrop")
        + (AirDrop.wifiPaused ? " · Wi-Fi paused" : "") + (AirDrop.error ? " · " + AirDrop.error.message : "")
    tooltip: bar.tooltip
    onClicked: ShellState.toggle("airdrop", bar.outputName)
    contentItem: RowLayout {
        spacing: 6
        Item {
            implicitWidth: 14
            implicitHeight: 14
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: chip.label ? 0 : 7
            // Files moving: a ring for the share done, in place of the glyph.
            C.Ring {
                anchors.fill: parent
                visible: AirDrop.progress >= 0
                size: 14
                thickness: 2
                trackColor: Theme.accentLine
                value: AirDrop.progress
            }
            C.Icon {
                id: glyph
                anchors.centerIn: parent
                visible: AirDrop.progress < 0
                name: chip.trouble ? "alert" : "airdrop"
                size: 14
                color: chip.foreground
                // Visible to others: the glyph breathes slowly.
                SequentialAnimation on opacity {
                    running: AirDrop.mode === "visible" && AirDrop.progress < 0 && !Theme.reduced && !Theme.lowPower && chip.bar.onScreen
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.45; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                    onStopped: glyph.opacity = 1
                }
            }
        }
        C.Label {
            visible: chip.label !== ""
            text: chip.label
            color: chip.foreground
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.features: ({"tnum": 1})
            elide: Text.ElideNone
        }
    }
    // A file dragged here and held opens the panel, where it can be dropped.
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onEntered: springOpen.restart()
        onExited: springOpen.stop()
        onDropped: event => {
            springOpen.stop();
            AirDrop.stage((event.urls || []).map(url => String(url)).filter(url => url.startsWith("file://")));
            ShellState.open("airdrop", chip.bar.outputName);
        }
    }
    Timer {
        id: springOpen
        interval: 450
        onTriggered: if (ShellState.panel !== "airdrop")
            ShellState.open("airdrop", chip.bar.outputName)
    }
}
