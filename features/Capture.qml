import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../components" as C

FocusScope {
    id: root
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
        spacing: 16
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: ["screenshot", "recording"]
                C.Button {
                    required property string modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    text: modelData === "screenshot" ? "Screenshot" : "Recording"
                    glyph: modelData === "screenshot" ? "camera" : "record"
                    selected: root.kind === modelData
                    enabled: !root.pending
                    onClicked: { root.kind = modelData; root.error = ""; }
                }
            }
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
                spacing: 16
                C.Label {
                    text: root.kind === "recording" && ShellState.recording.active ? "Recording area" : "Capture area"
                    color: Theme.muted
                    font.pixelSize: Theme.small
                    Layout.fillWidth: true
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    enabled: !root.pending && !(root.kind === "recording" && ShellState.recording.active)
                    Repeater {
                        model: ["region", "output", "window"]
                        C.ActionTile {
                            required property string modelData
                            text: modelData === "region" ? "Region" : modelData === "output" ? "Display" : "Window"
                            glyph: modelData === "region" ? "grid" : modelData === "output" ? "camera" : "window"
                            selected: root.mode === modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: Math.max(92, Theme.body + 70)
                            onClicked: root.mode = modelData
                        }
                    }
                }
                RowLayout {
                    visible: root.kind === "screenshot"
                    Layout.fillWidth: true
                    spacing: 8
                    C.Label {
                        text: "Delay"
                        Layout.fillWidth: true
                    }
                    Repeater {
                        model: [0, 3, 5, 10]
                        C.Button {
                            required property int modelData
                            text: modelData === 0 ? "None" : modelData + "s"
                            selected: ShellState.setting("captureDelay", 0) === modelData
                            enabled: !root.pending
                            onClicked: ShellState.setSetting("captureDelay", modelData)
                        }
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
                    spacing: 8
                    C.Label {
                        text: "Audio"
                        Layout.fillWidth: true
                    }
                    Repeater {
                        model: [{id: "none", text: "None"}, {id: "system", text: "System"}, {id: "microphone", text: "Microphone"}]
                        C.Button {
                            required property var modelData
                            text: modelData.text
                            selected: root.audio === modelData.id
                            enabled: !root.pending && !ShellState.recording.active
                            Accessible.role: Accessible.RadioButton
                            Accessible.checkable: true
                            Accessible.checked: selected
                            Accessible.name: modelData.id === "none" ? "No audio" : modelData.id === "system" ? "System audio" : "Microphone"
                            onClicked: ShellState.setSetting("recordAudio", modelData.id)
                        }
                    }
                }
                C.Label {
                    visible: root.kind === "recording"
                    text: "One source at a time: what your speakers play, or your microphone."
                    color: Theme.muted
                    font.pixelSize: Theme.small
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    Layout.topMargin: -8
                }
                RowLayout {
                    visible: root.kind === "recording" && ShellState.recording.active
                    Layout.fillWidth: true
                    spacing: 8
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
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: destination.implicitHeight + 32
                    color: Theme.surface
                    radius: Theme.controlRadius
                    ColumnLayout {
                        id: destination
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 4
                        C.Label {
                            text: "Save location"
                            color: Theme.muted
                            font.pixelSize: Theme.caption
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
            spacing: 8
            C.Button {
                visible: Backend.has("hyprpicker", true)
                text: "Pick color"
                flat: true
                glyph: "palette"
                enabled: !root.pending && Backend.ready
                implicitHeight: 44
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
                implicitHeight: 44
                enabled: !root.pending && Backend.ready && !root.missingTool
                onClicked: root.capture()
            }
        }
    }
}
