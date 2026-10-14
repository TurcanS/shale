import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../components" as C

FocusScope {
    id: root
    readonly property string title: "Capture"
    readonly property int panelHeight: 540
    property string mode: "region"
    property string kind: ShellState.recording.active ? "recording" : "screenshot"
    property bool copy: true
    // wf-recorder takes one audio source, so system audio and the microphone are alternatives.
    readonly property string audio: ShellState.setting("recordAudio", "none")
    property bool pending: false
    property string error: ""
    // The first tool this capture needs that isn't installed; stopping a recording needs none.
    readonly property string missingTool: {
        if (kind === "recording" && ShellState.recording.active)
            return "";
        const needs = [kind === "screenshot" ? "grim" : "wf-recorder"].concat(mode === "region" ? ["slurp"] : []);
        return needs.find(command => !Backend.has(command, true)) || "";
    }
    function capture() {
        if (pending || !Backend.ready || missingTool)
            return;
        pending = true;
        error = "";
        if (kind === "screenshot") {
            ShellState.screenshot(mode, copy);
        } else if (!ShellState.recording.active) {
            ShellState.record(mode, audio);
        } else {
            Backend.request("capture.record.stop", {}, (r, e) => {
                pending = false;
                if (e) {
                    error = e.message || "Could not stop recording. Try again.";
                    return;
                }
                ShellState.recording = r;
                ShellState.refreshRecording();
                ShellState.recordingResult(r);
            });
        }
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.gapL
        C.Segmented {
            Layout.fillWidth: true
            segmentHeight: Theme.controlLarge
            enabled: !root.pending
            model: [{key: "screenshot", text: "Screenshot", glyph: "camera"}, {key: "recording", text: "Recording", glyph: "record"}]
            current: root.kind
            onActivated: key => { root.kind = key; root.error = ""; }
        }
        ScrollView {
            id: scroll
            ScrollBar.vertical: C.ScrollBar {
                parent: scroll
                x: scroll.width - width
                y: scroll.topPadding
                height: scroll.availableHeight
            }
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true
            ColumnLayout {
                width: scroll.availableWidth
                spacing: Theme.gapL
                C.SectionHeader {
                    text: root.kind === "recording" && ShellState.recording.active ? "Recording area" : "Capture area"
                }
                C.Segmented {
                    Layout.fillWidth: true
                    Layout.topMargin: -Theme.gapS
                    segmentHeight: Theme.controlLarge
                    enabled: !root.pending && !(root.kind === "recording" && ShellState.recording.active)
                    model: [{key: "region", text: "Region", glyph: "region"}, {key: "output", text: "Display", glyph: "monitor"}, {key: "window", text: "Window", glyph: "window"}]
                    current: root.mode
                    onActivated: key => root.mode = key
                }
                RowLayout {
                    visible: root.kind === "screenshot"
                    Layout.fillWidth: true
                    spacing: Theme.gapM
                    C.Label {
                        text: "Delay"
                        Layout.fillWidth: true
                    }
                    C.Segmented {
                        fill: false
                        Layout.preferredWidth: 240
                        enabled: !root.pending
                        model: [0, 3, 5, 10].map(seconds => ({key: seconds, text: seconds === 0 ? "None" : seconds + "s"}))
                        current: ShellState.setting("captureDelay", 0)
                        onActivated: key => ShellState.setSetting("captureDelay", key)
                    }
                }
                C.Toggle {
                    visible: root.kind === "screenshot"
                    Layout.fillWidth: true
                    text: "Copy to clipboard"
                    selected: root.copy
                    enabled: !root.pending
                    onClicked: root.copy = !root.copy
                }
                RowLayout {
                    visible: root.kind === "recording"
                    Layout.fillWidth: true
                    spacing: Theme.gapM
                    C.Label {
                        text: "Audio"
                        Layout.fillWidth: true
                    }
                    C.Segmented {
                        fill: false
                        Layout.preferredWidth: 300
                        enabled: !root.pending && !ShellState.recording.active
                        model: [{key: "none", text: "None", accessibleName: "No audio"}, {key: "system", text: "System", accessibleName: "System audio"}, {key: "microphone", text: "Microphone"}]
                        current: root.audio
                        onActivated: key => ShellState.setSetting("recordAudio", key)
                    }
                }
                C.Label {
                    visible: root.kind === "recording"
                    text: "One source at a time: what your speakers play, or your microphone."
                    color: Theme.muted
                    font.pixelSize: Theme.small
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    Layout.topMargin: -Theme.gapS
                }
                RowLayout {
                    visible: root.kind === "recording" && ShellState.recording.active
                    Layout.fillWidth: true
                    spacing: Theme.gapS
                    Rectangle {
                        Layout.preferredWidth: 7
                        Layout.preferredHeight: 7
                        radius: 3.5
                        color: Theme.danger
                        SequentialAnimation on opacity {
                            running: !Theme.reduced && !Theme.lowPower && root.kind === "recording" && ShellState.recording.active
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.45; duration: 800; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 800; easing.type: Easing.InOutSine }
                        }
                    }
                    C.Label {
                        text: "Recording in progress"
                        color: Theme.danger
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                    }
                }
                C.Card {
                    Layout.fillWidth: true
                    implicitHeight: destination.implicitHeight + 2 * Theme.gapL
                    ColumnLayout {
                        id: destination
                        anchors.fill: parent
                        anchors.margins: Theme.gapL
                        spacing: Theme.gapXs
                        C.Caption {
                            text: "Save location"
                            Layout.fillWidth: true
                        }
                        C.Label {
                            text: root.kind === "screenshot" ? ShellState.setting("screenshotDirectory", "~/Pictures/Screenshots") : ShellState.recording.active ? (ShellState.recording.path || "Preparing recording…") : ShellState.setting("recordingDirectory", "~/Videos/Recordings")
                            font.pixelSize: Theme.small
                            font.family: Theme.mono
                            Layout.fillWidth: true
                            maximumLineCount: 3
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                }
                C.Label {
                    visible: root.error !== ""
                    text: root.error
                    color: Theme.danger
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gapS
            C.Button {
                visible: Backend.has("hyprpicker", true)
                text: "Pick color"
                flat: true
                glyph: "palette"
                enabled: !root.pending && Backend.ready
                implicitHeight: Theme.controlLarge
                onClicked: {
                    root.pending = true;
                    ShellState.action("color");
                }
            }
            C.Button {
                text: root.missingTool ? "Install " + root.missingTool + " to " + (root.kind === "screenshot" ? "take screenshots" : "record")
                    : root.pending ? "Working…" : root.kind === "screenshot" ? "Take screenshot" : ShellState.recording.active ? "Stop recording" : "Start recording"
                accent: !(root.kind === "recording" && ShellState.recording.active)
                danger: root.kind === "recording" && ShellState.recording.active
                glyph: root.kind === "screenshot" ? "camera" : ShellState.recording.active ? "stop" : "record"
                Layout.fillWidth: true
                implicitHeight: Theme.controlLarge
                enabled: !root.pending && Backend.ready && !root.missingTool
                onClicked: root.capture()
            }
        }
    }
}
