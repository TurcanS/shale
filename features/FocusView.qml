import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "../components" as C

// Control's Focus page: a ring counting down the session, its length, how many notifications it is holding, Start /
// Pause and End now, then what came in once it ends. The session itself is the Focus service's: it holds popups,
// shows a ring in the bar and survives a restart; this only drives it.
ColumnLayout {
    id: root
    // The length the next session runs for; a running one shows its own.
    property int length: Focus.lastMinutes
    // {minutes, total, groups} once a session ends while this page is open, or one that ended with a digest still
    // waiting; null while one is ready or running.
    property var summary: null
    property real lastStarted: 0
    readonly property string phase: summary ? "done" : Focus.paused ? "paused" : Focus.active ? "running" : "ready"
    readonly property int held: Focus.active ? Services.notifications.filter(n => !n.transient && n.timestamp >= Focus.startedAt).length : 0
    // For Control's header: the chip beside the title.
    readonly property var chip: ({
            ready: {text: "Ready", on: false},
            running: {text: "Running · quiet on", on: true},
            paused: {text: "Paused", on: false},
            done: {text: "Finished", on: true}
        })[phase]
    spacing: 12
    // With Control's header and padding, the page is 440 high.
    Layout.preferredHeight: 358
    function primary() {
        if (phase === "done") {
            // Read here, so the digest card doesn't wait on the desktop and the page doesn't show it again.
            summary = null;
            Focus.digest = null;
        }
        else if (phase === "running")
            Focus.pause();
        else if (phase === "paused")
            Focus.unpause();
        else
            Focus.start(root.length);
    }
    Component.onCompleted: {
        if (Focus.active)
            lastStarted = Focus.startedAt;
        else if (Focus.digest)
            summary = Focus.digest;
    }
    Connections {
        target: Focus
        function onActiveChanged() {
            if (Focus.active) {
                root.lastStarted = Focus.startedAt;
                root.summary = null;
                return;
            }
            // The digest is worked out right after the session stops; its pauses are still known now.
            const worked = (Focus.pausedAt > 0 ? Focus.pausedAt : Date.now()) - root.lastStarted - Focus.pausedFor;
            Qt.callLater(() => {
                const digest = Focus.digest;
                root.summary = digest ? digest : {minutes: Math.max(1, Math.round(worked / 60000)), total: 0, groups: []};
            });
        }
    }
    // Space or Enter on the main key once the page opens.
    onVisibleChanged: if (visible) primaryKey.forceActiveFocus()

    RowLayout {
        visible: root.phase !== "done"
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 20
        // The ring empties as the session runs out; a soft halo of the accent stands in for its glow. The ring's
        // centre line has an 86 px radius, as the design's, so the halo stays inside the 196 px box.
        Item {
            readonly property real fraction: Focus.active ? Focus.progress : 1
            implicitWidth: 196
            implicitHeight: 196
            Layout.alignment: Qt.AlignVCenter
            Accessible.role: Accessible.StaticText
            Accessible.name: time.text + " " + under.text
            C.Ring {
                anchors.centerIn: parent
                visible: !Theme.lowPower
                size: 182 + 8
                thickness: 18
                value: parent.fraction
                color: Theme.tint(Theme.accent, 0.12)
                trackColor: "transparent"
            }
            C.Ring {
                anchors.centerIn: parent
                visible: !Theme.lowPower
                size: 182 + 4
                thickness: 14
                value: parent.fraction
                color: Theme.tint(Theme.accent, 0.18)
                trackColor: "transparent"
            }
            C.Ring {
                anchors.centerIn: parent
                size: 182
                thickness: 10
                value: parent.fraction
                trackColor: Theme.module
            }
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 2
                C.Label {
                    id: time
                    text: Focus.clockText(Focus.active ? Focus.remainingSeconds : root.length * 60)
                    // An hour or more ("1:30:00") steps down to fit inside the ring.
                    font.pixelSize: text.length > 5 ? 36 : 44
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.9
                    font.features: ({"tnum": 1})
                    elide: Text.ElideNone
                    Layout.alignment: Qt.AlignHCenter
                }
                C.Label {
                    id: under
                    text: root.phase === "running" ? "until " + Qt.formatDateTime(new Date(Focus.endsAt), ShellState.timeFormat) : root.phase === "paused" ? "paused" : "left"
                    color: Theme.textDim
                    font.pixelSize: 13
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 12
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                C.Label {
                    text: "Length"
                    color: Theme.textDim
                    font.pixelSize: 12
                }
                // Picked before a session starts; a running one keeps its length (the bar chip adds or takes 5 min).
                C.Segmented {
                    Layout.fillWidth: true
                    segmentHeight: 34
                    enabled: !Focus.active
                    model: [25, 50, 90].map(minutes => ({key: minutes, text: minutes + " min", accessibleName: "Focus for " + minutes + " minutes"}))
                    current: Focus.active ? Math.round((Focus.endsAt - Focus.startedAt - Focus.pausedFor) / 60000) : root.length
                    onActivated: key => root.length = key
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: heldRow.implicitHeight + 20
                radius: Theme.radiusCard
                color: Theme.module
                RowLayout {
                    id: heldRow
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10
                    Rectangle {
                        implicitWidth: Math.max(26, heldCount.implicitWidth + 12)
                        implicitHeight: 26
                        radius: 8
                        color: root.held > 0 ? Theme.raisedOnKey : Theme.key
                        C.Label {
                            id: heldCount
                            anchors.centerIn: parent
                            text: root.held
                            color: root.held > 0 ? Theme.accentText : Theme.text
                            font.pixelSize: 13
                            font.weight: 650
                            font.features: ({"tnum": 1})
                        }
                    }
                    C.Label {
                        text: (root.held === 1 ? "notification" : "notifications") + " held until you finish"
                        color: Theme.textSecondary
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                        lineHeight: 1.1
                        Layout.fillWidth: true
                    }
                }
            }
            C.Label {
                text: "Urgent notifications still pop up. The bar shows a ring while this runs."
                color: Theme.textDim
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                lineHeight: 1.2
                Layout.fillWidth: true
            }
        }
    }

    // What came in, an app to a row with its latest, the most first.
    ColumnLayout {
        visible: root.phase === "done"
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            C.Label {
                text: root.summary ? root.summary.minutes + " min done" : ""
                font.pixelSize: 28
                font.weight: 650
                font.features: ({"tnum": 1})
                elide: Text.ElideNone
            }
            C.Label {
                text: !root.summary || root.summary.total === 0 ? "nothing came in while you worked" : root.summary.total + " came in while you worked"
                color: Theme.textDim
                font.pixelSize: 13
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignBaseline
            }
        }
        Repeater {
            model: root.summary ? root.summary.groups.slice(0, 4) : []
            Rectangle {
                id: group
                required property var modelData
                required property int index
                Layout.fillWidth: true
                implicitHeight: groupRow.implicitHeight + 20
                radius: Theme.radiusCard
                color: Theme.module
                // The busiest app leads, edged in the accent.
                border.width: index === 0 ? 1 : 0
                border.color: Theme.accentLine
                RowLayout {
                    id: groupRow
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12
                    // The app's initial; filled with the accent for the busiest.
                    Rectangle {
                        implicitWidth: 28
                        implicitHeight: 28
                        radius: 8
                        color: group.index === 0 ? Theme.accent : Theme.key
                        C.Label {
                            anchors.centerIn: parent
                            text: (group.modelData.appName || "?").charAt(0).toUpperCase()
                            color: group.index === 0 ? Theme.accentInk : Theme.textSecondary
                            font.pixelSize: 12
                            font.weight: Font.Bold
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        C.Label {
                            text: group.modelData.appName || "Notification"
                            color: Theme.textDim
                            font.pixelSize: 12
                            Layout.fillWidth: true
                        }
                        C.Label {
                            text: group.modelData.latest
                            font.pixelSize: 14
                            Layout.fillWidth: true
                        }
                    }
                    C.Label {
                        visible: group.modelData.count > 1
                        text: "×" + group.modelData.count
                        color: Theme.textDim
                        font.pixelSize: 12
                        font.features: ({"tnum": 1})
                    }
                }
            }
        }
        C.Label {
            visible: !!root.summary && root.summary.groups.length > 4
            text: root.summary ? "and " + (root.summary.groups.length - 4) + " more apps in Notifications" : ""
            color: Theme.textDim
            font.pixelSize: 12
            Layout.fillWidth: true
        }
        Item {
            Layout.fillHeight: true
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        C.Button {
            id: primaryKey
            Layout.fillWidth: true
            implicitHeight: 44
            accent: root.phase !== "running"
            glyph: root.phase === "running" ? "pause" : "play"
            text: ({ready: "Start", running: "Pause", paused: "Resume", done: "Start another"})[root.phase]
            labelSize: 14
            onClicked: root.primary()
        }
        C.Button {
            implicitHeight: 44
            text: "End now"
            labelSize: 14
            enabled: Focus.active
            onClicked: Focus.end(true)
        }
    }
}
