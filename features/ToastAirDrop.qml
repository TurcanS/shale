pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../core"
import "../services"
import "../core/format.js" as Format
import "../core/airdrop.js" as Words
import "../components" as C

// AirDrop requests from other devices, one card each under the bar's right end: who sends what, a ring that runs
// down to the automatic decline, and Decline / Accept (Always for a named sender). Accepted, the card shows the
// files arriving, then Open and Show. Shown through Do not disturb and over full-screen apps: a request needs an
// answer. Never takes the keyboard by itself; a click on a card gives it Enter (accept) and Escape (decline).
// While locked the lock screen asks instead (LockAirDrop).
PanelWindow {
    id: window
    property bool target: false
    readonly property bool shown: target && !ShellState.locked && cards.count > 0
    anchors {
        top: true
        right: true
    }
    margins.top: ShellState.barBottomOn(window.screen ? window.screen.name : "") + 9
    margins.right: 12
    implicitWidth: Math.min(392, screen.width - 24)
    implicitHeight: Math.max(1, stack.implicitHeight)
    visible: shown || stack.leaving > 0
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shale-airdrop"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    ColumnLayout {
        id: stack
        property int leaving: 0
        width: parent.width
        spacing: 8
        Repeater {
            id: cards
            model: AirDrop.incoming
            Card {}
        }
    }
    component Card: Item {
        id: card
        required property int index
        required property string key
        required property string sender
        required property string kind
        required property bool known
        required property int timeout
        required property real deadline
        required property string filesJson
        required property string urlsJson
        required property real total
        required property string icon
        required property string phase
        required property real done
        required property real rate
        required property string savedJson
        required property string message
        readonly property var files: JSON.parse(filesJson || "[]")
        readonly property var urls: JSON.parse(urlsJson || "[]")
        readonly property var saved: JSON.parse(savedJson || "[]")
        readonly property string who: sender || "A nearby device"
        readonly property string what: Words.summary(files, urls)
        readonly property bool ended: ["done", "link", "declined", "missed", "failed", "cancelled"].indexOf(phase) >= 0
        readonly property bool good: phase === "done" || phase === "link"
        Layout.fillWidth: true
        implicitHeight: (face.implicitHeight + 28) * reveal
        clip: true
        focus: true
        // Arrives dropping in from under the bar; leaves folding up.
        property real reveal: 0
        property bool leaving: false
        Component.onCompleted: reveal = 1
        Behavior on reveal {
            NumberAnimation {
                duration: card.leaving ? Theme.leave + 60 : Theme.enter + 60
                easing.type: card.leaving ? Easing.InCubic : Easing.OutBack
                easing.overshoot: 1.1
                onRunningChanged: if (!running && card.leaving) {
                    stack.leaving = Math.max(0, stack.leaving - 1);
                    AirDrop.dismiss(card.key);
                }
            }
        }
        function leave() {
            if (leaving)
                return;
            leaving = true;
            stack.leaving++;
            reveal = 0;
            if (Theme.reduced) {
                stack.leaving = Math.max(0, stack.leaving - 1);
                AirDrop.dismiss(card.key);
            }
        }
        // Finished cards go on their own; a refusal sooner, success after time to press Open. Hovering holds them.
        Timer {
            running: card.ended && window.shown && !hover.hovered && !card.leaving
            interval: card.good ? 9000 : 3500
            onTriggered: card.leave()
        }
        HoverHandler {
            id: hover
        }
        Keys.onReturnPressed: if (phase === "asking")
            AirDrop.answer(key, "accept")
        Keys.onEnterPressed: if (phase === "asking")
            AirDrop.answer(key, "accept")
        Keys.onEscapePressed: phase === "asking" ? AirDrop.answer(key, "decline") : leave()
        // Seconds left to answer, for the ring.
        property int secondsLeft: Math.max(0, Math.round((deadline - Date.now()) / 1000))
        Timer {
            running: card.phase === "asking"
            interval: 1000
            repeat: true
            triggeredOnStart: true
            onTriggered: card.secondsLeft = Math.max(0, Math.round((card.deadline - Date.now()) / 1000))
        }
        Rectangle {
            id: surface
            anchors.fill: parent
            radius: 18
            color: Theme.module
            border.width: 1
            border.color: card.phase === "asking" ? Theme.accentLine : Theme.cardEdge
            opacity: card.reveal
            transform: Translate {
                y: Theme.reduced ? 0 : (1 - card.reveal) * -12
            }
            Behavior on border.color {
                ColorAnimation {
                    duration: Theme.fast
                }
            }
            TapHandler {
                onTapped: card.forceActiveFocus()
            }
            ColumnLayout {
                id: face
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    // The sender, with the time left to answer running down around it.
                    Item {
                        implicitWidth: 48
                        implicitHeight: 48
                        Layout.alignment: Qt.AlignTop
                        C.Ring {
                            anchors.fill: parent
                            size: 48
                            thickness: 3
                            visible: card.phase === "asking" && card.timeout > 0
                            trackColor: Theme.key
                            property real shown: card.timeout > 0 ? card.secondsLeft / card.timeout : 0
                            value: shown
                            Behavior on shown {
                                NumberAnimation {
                                    duration: Theme.reduced ? 0 : 1000
                                }
                            }
                        }
                        Rectangle {
                            id: disc
                            anchors.centerIn: parent
                            width: 38
                            height: 38
                            radius: 19
                            color: card.good ? Theme.accent : card.ended ? Theme.key : Theme.raisedOnKey
                            Behavior on color {
                                ColorAnimation {
                                    duration: Theme.fast
                                }
                            }
                            C.Icon {
                                anchors.centerIn: parent
                                name: card.good ? "check" : card.ended ? "close" : Words.deviceGlyph(card.kind)
                                size: 19
                                color: card.good ? Theme.accentInk : card.ended ? Theme.textDim : Theme.accentText
                            }
                            // Saved: the disc pops once.
                            SequentialAnimation {
                                id: pop
                                NumberAnimation { target: disc; property: "scale"; to: 1.18; duration: 120; easing.type: Easing.OutCubic }
                                NumberAnimation { target: disc; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2 }
                            }
                            Connections {
                                target: card
                                function onGoodChanged() {
                                    if (card.good && !Theme.reduced && !Theme.lowPower)
                                        pop.restart();
                                }
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        C.Label {
                            text: {
                                switch (card.phase) {
                                case "asking":
                                    return card.who + " wants to share " + card.what;
                                case "accepted":
                                    return "Waiting for " + card.who;
                                case "receiving":
                                    return "Receiving " + card.what + " from " + card.who;
                                case "done":
                                    return card.saved.length === 1 ? "Saved " + ShellState.fileName(card.saved[0]) : "Saved " + card.what;
                                case "link":
                                    return card.who + " shared a link";
                                case "declined":
                                    return "Declined " + card.what + " from " + card.who;
                                case "missed":
                                    return "Declined: no answer in time";
                                case "cancelled":
                                    return card.who + " stopped sending";
                                }
                                return "Couldn't receive " + card.what;
                            }
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            Layout.fillWidth: true
                        }
                        C.Label {
                            text: {
                                if (card.phase === "receiving")
                                    return [Format.bytes(card.done) + " of " + Format.bytes(card.total), card.rate > 0 ? Format.bytes(card.rate) + "/s" : "",
                                            Words.left(card.done, card.total, card.rate)].filter(part => part).join(" · ");
                                if (card.phase === "cancelled" && card.message)
                                    return card.message;
                                if (card.phase === "link")
                                    return card.saved[0] || card.urls[0] || "";
                                if (card.phase === "failed" && card.message)
                                    return card.message;
                                if (card.phase === "asking" && card.timeout > 0)
                                    return (card.urls.length ? card.urls[0] : Words.names(card.files) + (card.total > 0 ? " · " + Format.bytes(card.total) : ""));
                                if (card.phase === "done")
                                    return Format.bytes(card.done || card.total) + " · in " + AirDrop.folder;
                                if (card.phase === "missed")
                                    return Words.capital(card.what) + " from " + card.who;
                                return card.urls.length ? card.urls[0] : Words.names(card.files);
                            }
                            color: card.phase === "failed" ? Theme.dangerText : Theme.textDim
                            font.pixelSize: 12
                            font.features: ({"tnum": 1})
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                    }
                    // The sender's preview, when Qt can read it (iPhones send JPEG 2000).
                    Rectangle {
                        visible: preview.status === Image.Ready && !card.ended
                        implicitWidth: 52
                        implicitHeight: 52
                        radius: 10
                        color: Theme.well
                        clip: true
                        Layout.alignment: Qt.AlignTop
                        Image {
                            id: preview
                            anchors.fill: parent
                            // Qt reads no JPEG 2000 (what iPhones send): not loading it spares an error per request.
                            source: /\.jp2$/i.test(card.icon) ? "" : card.icon
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize: Qt.size(104, 104)
                        }
                    }
                    C.Button {
                        visible: card.ended || card.phase === "accepted"
                        glyph: "close"
                        flat: true
                        hint: "Dismiss"
                        implicitWidth: 28
                        implicitHeight: 28
                        Layout.alignment: Qt.AlignTop
                        onClicked: card.leave()
                    }
                }
                // Arriving: a bar that fills as the files come in.
                Rectangle {
                    visible: card.phase === "receiving" || card.phase === "accepted"
                    Layout.fillWidth: true
                    implicitHeight: 6
                    radius: 3
                    color: Theme.key
                    Rectangle {
                        id: fill
                        property real fraction: card.total > 0 ? Math.min(1, card.done / card.total) : 0
                        width: parent.width * fraction
                        height: parent.height
                        radius: 3
                        color: Theme.accent
                        Behavior on fraction {
                            NumberAnimation {
                                duration: Theme.reduced ? 0 : 220
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                    // Waiting for the first byte: a short light sweeping along the track.
                    Rectangle {
                        visible: card.phase === "accepted" && !Theme.reduced && !Theme.lowPower
                        width: parent.width * 0.25
                        height: parent.height
                        radius: 3
                        color: Theme.accentLine
                        NumberAnimation on x {
                            running: card.phase === "accepted" && !Theme.reduced && !Theme.lowPower
                            from: -card.width * 0.25
                            to: card.width
                            duration: 1200
                            loops: Animation.Infinite
                        }
                    }
                }
                // The answers.
                RowLayout {
                    visible: card.phase === "asking"
                    Layout.fillWidth: true
                    spacing: 8
                    C.Button {
                        visible: card.sender !== ""
                        text: "Always from " + card.sender
                        flat: true
                        implicitHeight: 32
                        labelSize: 12
                        Layout.fillWidth: true
                        Layout.maximumWidth: implicitWidth
                        onClicked: AirDrop.answer(card.key, "always")
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    C.Button {
                        text: "Decline"
                        implicitHeight: 32
                        onClicked: AirDrop.answer(card.key, "decline")
                    }
                    C.Button {
                        text: "Accept"
                        accent: true
                        implicitHeight: 32
                        onClicked: AirDrop.answer(card.key, "accept")
                    }
                }
                // Done: what to do with it.
                RowLayout {
                    visible: card.good
                    Layout.fillWidth: true
                    spacing: 8
                    Item {
                        Layout.fillWidth: true
                    }
                    C.Button {
                        visible: card.phase === "link"
                        text: "Copy"
                        implicitHeight: 32
                        onClicked: {
                            Quickshell.clipboardText = card.saved[0] || "";
                            card.leave();
                        }
                    }
                    C.Button {
                        visible: card.phase === "done"
                        text: "Show in folder"
                        implicitHeight: 32
                        onClicked: {
                            const path = card.saved[0] || AirDrop.folderPath;
                            ShellState.openPath(card.saved.length === 1 ? path.slice(0, path.lastIndexOf("/")) : AirDrop.folderPath);
                            card.leave();
                        }
                    }
                    C.Button {
                        text: card.phase === "link" ? "Open link" : "Open"
                        accent: true
                        implicitHeight: 32
                        onClicked: {
                            if (card.phase === "link")
                                AirDrop.openLink(card.saved[0] || "");
                            else
                                ShellState.openPath(card.saved.length === 1 ? card.saved[0] : AirDrop.folderPath);
                            card.leave();
                        }
                    }
                }
            }
        }
    }
}
