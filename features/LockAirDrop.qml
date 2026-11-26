pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "../core/format.js" as Format
import "../core/airdrop.js" as Words
import "../components" as C

// AirDrop requests on the lock screen, top right: who sends how much, and Decline / Accept. Nothing more is given
// away or done while locked: no file names, no Always, nothing opens; saved files wait for the unlock. The keys
// never take focus from the password field.
ColumnLayout {
    id: root
    spacing: 8
    Repeater {
        model: AirDrop.incoming
        Rectangle {
            id: card
            required property string key
            required property string sender
            required property string kind
            required property string filesJson
            required property string urlsJson
            required property real total
            required property real done
            required property string phase
            required property int timeout
            required property real deadline
            readonly property string what: Words.summary(JSON.parse(filesJson || "[]"), JSON.parse(urlsJson || "[]"))
            readonly property bool shownPhase: ["asking", "accepted", "receiving", "done", "link"].indexOf(phase) >= 0
            visible: shownPhase || opacity > 0
            opacity: shownPhase ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.leave
                }
            }
            Layout.preferredWidth: 340
            Layout.alignment: Qt.AlignRight
            implicitHeight: face.implicitHeight + 24
            radius: 16
            color: Theme.tint(Theme.caseColor, 0.7)
            border.width: 1
            border.color: phase === "asking" ? Theme.accentLine : Theme.cardEdge
            // Arrives sliding in from the edge.
            property real reveal: 0
            Component.onCompleted: reveal = 1
            Behavior on reveal {
                NumberAnimation {
                    duration: Theme.enter + 60
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.1
                }
            }
            transform: Translate {
                x: Theme.reduced ? 0 : (1 - card.reveal) * 24
            }
            ColumnLayout {
                id: face
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 10
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Rectangle {
                        implicitWidth: 34
                        implicitHeight: 34
                        radius: 17
                        color: card.phase === "done" || card.phase === "link" ? Theme.accent : Theme.accentSoft
                        C.Icon {
                            anchors.centerIn: parent
                            name: card.phase === "done" || card.phase === "link" ? "check" : Words.deviceGlyph(card.kind)
                            size: 17
                            color: card.phase === "done" || card.phase === "link" ? Theme.accentInk : Theme.accentText
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        C.Label {
                            text: card.phase === "asking" ? (card.sender || "A nearby device") + " wants to share " + card.what
                                : card.phase === "done" || card.phase === "link" ? "Saved " + card.what + " · unlock to open"
                                : "Receiving " + card.what
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            Layout.fillWidth: true
                        }
                        C.Label {
                            text: card.phase === "receiving" && card.total > 0 ? Format.bytes(card.done) + " of " + Format.bytes(card.total)
                                : card.total > 0 ? Format.bytes(card.total) : ""
                            visible: text !== ""
                            color: Theme.textDim
                            font.pixelSize: 12
                            font.features: ({"tnum": 1})
                        }
                    }
                }
                Rectangle {
                    visible: card.phase === "receiving"
                    Layout.fillWidth: true
                    implicitHeight: 4
                    radius: 2
                    color: Theme.key
                    Rectangle {
                        property real fraction: card.total > 0 ? Math.min(1, card.done / card.total) : 0
                        width: parent.width * fraction
                        height: parent.height
                        radius: 2
                        color: Theme.accent
                        Behavior on fraction {
                            NumberAnimation {
                                duration: Theme.reduced ? 0 : 220
                            }
                        }
                    }
                }
                RowLayout {
                    visible: card.phase === "asking"
                    Layout.fillWidth: true
                    spacing: 8
                    Item {
                        Layout.fillWidth: true
                    }
                    C.Button {
                        text: "Decline"
                        implicitHeight: 30
                        focusPolicy: Qt.NoFocus
                        onClicked: AirDrop.answer(card.key, "decline")
                    }
                    C.Button {
                        text: "Accept"
                        accent: true
                        implicitHeight: 30
                        focusPolicy: Qt.NoFocus
                        onClicked: AirDrop.answer(card.key, "accept")
                    }
                }
            }
        }
    }
}
