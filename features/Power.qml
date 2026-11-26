import "../components" as C
import "../core"
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

// The session menu: Lock, Sleep, Sign out and Restart as keyed tiles (each letter works too; Sign out and Restart
// ask for a second press), and Power off, which needs a one-second hold.
FocusScope {
    id: root
    readonly property string title: "Session"
    readonly property string headerNote: [uptime, ShellState.recording.active ? "recording in progress" : ""].filter(part => part).join(" · ")
    readonly property int panelWidth: 440
    readonly property int panelHeight: Theme.body >= 18 ? 236 : 212

    property bool leaving: false
    // The action waiting for its second press: "logout", "reboot" or none.
    property string picked: ""
    // Session actions only run from the panel in front, never from a covered or locked one.
    readonly property bool ready: !leaving && ShellState.panel === "power" && !ShellState.locked && root.Window.active
    property string uptime: ""
    // The note of the tile under the pointer or keyboard focus, shown in the status line.
    property string spotlight: ""

    // ShellState runs the action, so a refusal still shows as a message after this panel closes.
    function endSession(action) {
        if (leaving)
            return;
        leaving = true;
        ShellState.close();
        ShellState.sessionAction(action);
    }
    function choose(action) {
        if (!ready)
            return;
        if (action === "lock") {
            ShellState.action("lock");
        } else if (action === "suspend") {
            endSession("suspend");
        } else if (picked === action) {
            endSession(action);
        } else {
            picked = action;
            pickTimeout.restart();
        }
    }
    function duration(seconds) {
        const days = Math.floor(seconds / 86400), hours = Math.floor(seconds % 86400 / 3600), minutes = Math.floor(seconds % 3600 / 60);
        return days ? "Up " + days + " d " + hours + " h" : hours ? "Up " + hours + " h " + minutes + " min" : "Up " + Math.max(1, minutes) + " min";
    }

    Keys.onPressed: event => {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return;
        const action = ({[Qt.Key_L]: "lock", [Qt.Key_S]: "suspend", [Qt.Key_O]: "logout", [Qt.Key_R]: "reboot"})[event.key];
        if (action) {
            root.choose(action);
            event.accepted = true;
        }
    }
    Process {
        id: uptimeRead
        command: ["cat", "/proc/uptime"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const seconds = parseFloat(text);
                root.uptime = isNaN(seconds) ? "" : root.duration(seconds);
            }
        }
    }
    Timer {
        interval: 60000
        repeat: true
        running: ShellState.panel === "power"
        onTriggered: uptimeRead.running = true
    }
    // An unanswered second press lapses, so a stray key later doesn't end the session.
    Timer {
        id: pickTimeout
        interval: 5000
        onTriggered: root.picked = ""
    }

    // One keyed action: icon tile, name, a short note and its letter. Picked, it takes the accent.
    component SessionTile: C.Button {
        id: tile
        // Opening the menu, the tiles rise out of the case one after another (order: left to right).
        property int order: 0
        opacity: rise.shown
        transform: [
            Translate {
                y: tile.sunk
            },
            C.Cascade {
                id: rise
                panel: "power"
                order: tile.order
                dy: 64
                overshoot: 1
                duration: 380
                spacing: 1.6
            }
        ]
        property string note: ""
        property string key: ""
        property string sessionAction: ""
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        Layout.minimumWidth: 0
        topPadding: 10
        leftPadding: 8
        rightPadding: 8
        bottomPadding: 10
        cornerRadius: Theme.radiusCard + 2
        readonly property bool spotlit: hovered || visualFocus
        onSpotlitChanged: if (spotlit)
            root.spotlight = text + " · " + note;
        else if (root.spotlight === text + " · " + note)
            root.spotlight = ""
        enabled: root.ready
        Accessible.description: note + " Key " + key + "."
        background: Rectangle {
            radius: tile.cornerRadius
            color: tile.selected ? Theme.raised : tile.hovered || tile.down || tile.visualFocus ? Theme.mix(Theme.module, Theme.text, 0.04) : Theme.module
            Behavior on color {
                ColorAnimation {
                    duration: Theme.fast
                }
            }
            C.Raise {
                shown: tile.selected
            }
        }
        contentItem: ColumnLayout {
            spacing: 4
            C.GlyphTile {
                size: 32
                glyph: tile.glyph
                selected: tile.selected
            }
            Item {
                Layout.fillHeight: true
            }
            C.Label {
                text: tile.text
                font.pixelSize: 13
                font.weight: 650
                Layout.fillWidth: true
            }
            C.KeyHint {
                text: tile.key
                mono: true
                color: Theme.key
            }
        }
        onClicked: root.choose(sessionAction)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.gapS
            SessionTile {
                order: 0
                text: "Lock"
                glyph: "lock"
                key: "L"
                sessionAction: "lock"
                note: "Apps keep running."
            }
            SessionTile {
                order: 1
                text: "Sleep"
                glyph: "moon"
                key: "S"
                sessionAction: "suspend"
                note: "Locks first."
            }
            SessionTile {
                order: 2
                text: root.picked === "logout" ? "Sign out?" : "Sign out"
                glyph: "logout"
                key: "O"
                sessionAction: "logout"
                selected: root.picked === "logout"
                note: root.picked === "logout" ? "Press again to sign out." : "Closes every app."
            }
            SessionTile {
                order: 3
                text: root.picked === "reboot" ? "Restart?" : "Restart"
                glyph: "refresh"
                key: "R"
                sessionAction: "reboot"
                selected: root.picked === "reboot"
                note: root.picked === "reboot" ? "Press again to restart." : "Closes every app."
            }
            // Power off: hold for a second while the ring fills.
            C.HoldButton {
                id: powerOff
                text: "Power off"
                destructive: true
                Layout.preferredWidth: 88
                Layout.fillHeight: true
                implicitHeight: 100
                padding: 8
                armed: root.ready
                onConfirmed: root.endSession("shutdown")
                background: Rectangle {
                    radius: Theme.radiusCard + 2
                    color: powerOff.hovered || powerOff.visualFocus || powerOff.down ? Theme.tint(Theme.danger, 0.11) : Theme.dangerWash
                    border.width: 1
                    border.color: Theme.tint(Theme.danger, 0.4)
                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.fast
                        }
                    }
                }
                contentItem: ColumnLayout {
                    spacing: 4
                    Item {
                        Layout.fillHeight: true
                    }
                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 44
                        implicitHeight: 44
                        C.Ring {
                            anchors.fill: parent
                            size: 44
                            thickness: 3.5
                            value: powerOff.progress
                            color: Theme.danger
                            trackColor: Theme.tint(Theme.danger, 0.18)
                        }
                        C.Icon {
                            anchors.centerIn: parent
                            name: "power"
                            size: 18
                            color: Theme.dangerText
                        }
                    }
                    C.Label {
                        text: powerOff.progress > 0 ? "Keep holding" : "Power off"
                        color: Theme.dangerText
                        font.pixelSize: 13
                        font.weight: 650
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }
                    C.Label {
                        text: "hold 1 s"
                        color: Theme.mix(Theme.dangerText, Theme.module, 0.3)
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }
                    Item {
                        Layout.fillHeight: true
                    }
                }
            }
        }
        // What happens next: the default hint, a pending second press, the hold, or a recording to save first.
        Rectangle {
            id: statusLine
            readonly property string mode: powerOff.progress > 0 ? "hold" : root.picked !== "" ? "picked" : ShellState.recording.active ? "recording" : root.spotlight !== "" ? "spotlight" : ""
            Layout.fillWidth: true
            implicitHeight: 30
            radius: Theme.radiusKey
            color: Theme.module
            Accessible.role: Accessible.StatusBar
            Accessible.name: status.text
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: Theme.gapS
                Rectangle {
                    implicitWidth: 6
                    implicitHeight: 6
                    radius: 3
                    color: statusLine.mode === "hold" ? Theme.danger : statusLine.mode === "picked" ? Theme.accent
                         : statusLine.mode === "recording" ? Theme.warning : Theme.textFaint
                }
                C.Label {
                    id: status
                    text: ({
                            hold: "Keep holding · " + Math.round(powerOff.progress * 100) + "%",
                            picked: root.picked === "logout" ? "Press O again to sign out." : "Press R again to restart.",
                            recording: "Recording in progress · save it before ending your session.",
                            spotlight: root.spotlight
                        })[statusLine.mode] || "Press a letter, or hold Power off for a second."
                    color: statusLine.mode === "recording" ? Theme.warning : Theme.textSecondary
                    font.pixelSize: 12
                    Layout.fillWidth: true
                }
            }
        }
    }
}
