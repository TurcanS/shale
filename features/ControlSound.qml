import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "../components" as C

// Control → Sound: the devices in use, the mixer's channel strips, then the equalizer.
ColumnLayout {
    // The Control page this view belongs to: its state, requests and helpers.
    required property var control
    visible: ShellState.detail === "audio"
    Layout.fillWidth: true
    spacing: Theme.gapS
    C.StatusCard {
        visible: !Services.audioAvailable
        Layout.fillWidth: true
        glyph: "volume"
        title: "Audio unavailable"
        subtitle: "No output device or audio service"
    }
    ColumnLayout {
        visible: Services.audioAvailable
        Layout.fillWidth: true
        spacing: Theme.gapS
        C.Card {
            Layout.fillWidth: true
            implicitHeight: mixer.implicitHeight + 24
            ColumnLayout {
                id: mixer
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10
                // The devices in use; each chip opens the list to pick another.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.gapS
                    C.Label {
                        text: "Mixer"
                        font.pixelSize: 15
                        font.weight: 650
                        elide: Text.ElideNone
                    }
                    C.Chip {
                        text: "Out · " + (Services.output ? control.outputName(Services.output) : "none")
                        hint: "Choose the output"
                        rest: Theme.well
                        implicitHeight: 24
                        selected: control.deviceChooser === "out"
                        Layout.maximumWidth: 180
                        onClicked: control.deviceChooser = control.deviceChooser === "out" ? "" : "out"
                    }
                    C.Chip {
                        visible: Services.audioInputs.length > 0
                        text: "In · " + (Services.input ? control.outputName(Services.input) : "none")
                        hint: "Choose the microphone"
                        rest: Theme.well
                        implicitHeight: 24
                        selected: control.deviceChooser === "in"
                        Layout.maximumWidth: 160
                        onClicked: control.deviceChooser = control.deviceChooser === "in" ? "" : "in"
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                }
                Flow {
                    visible: control.deviceChooser !== ""
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: control.deviceChooser === "out" ? Services.audioOutputs : control.deviceChooser === "in" ? Services.audioInputs : []
                        C.Chip {
                            required property var modelData
                            text: modelData.description || modelData.name
                            glyph: control.deviceChooser === "in" ? "mic" : control.outputGlyph(text)
                            rest: Theme.key
                            selected: modelData === (control.deviceChooser === "in" ? Services.input : Services.output)
                            Accessible.role: Accessible.RadioButton
                            Accessible.checkable: true
                            Accessible.checked: selected
                            onClicked: {
                                if (control.deviceChooser === "in")
                                    Services.setInput(modelData);
                                else
                                    Services.setOutput(modelData);
                                control.deviceChooser = "";
                            }
                        }
                    }
                }
                Flickable {
                    id: stripView
                    Layout.fillWidth: true
                    Layout.preferredHeight: 236
                    contentWidth: strips.implicitWidth
                    contentHeight: height
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    Row {
                        id: strips
                        height: parent.height
                        spacing: 6
                        // Few channels share the module's width (up to 120 px each, centred); many scroll at 72.
                        readonly property int lanes: 1 + Services.audioStreams.length + (Services.input ? 1 : 0)
                        readonly property real lane: Math.max(72, Math.min(120, (stripView.width - spacing * (lanes - 1)) / lanes))
                        x: Math.max(0, (stripView.width - width) / 2)
                        ControlStrip {
                            height: strips.height
                            width: strips.lane
                            title: "Master"
                            tag: Theme.accent
                            fillColor: Theme.accent
                            value: control.level(Services.output)
                            maximum: ShellState.setting("amplification", false) ? 1.5 : 1
                            muted: Services.muted
                            meter: control.outputMeter.level
                            pan: control.balance(Services.output)
                            pannable: !!Services.output && !!Services.output.audio && (Services.output.audio.volumes || []).length === 2
                            onMoved: value => control.setLevel(Services.output, value, v => Services.setVolume(v))
                            onMuteClicked: Services.toggleMute()
                            onPanMoved: pan => control.setBalance(Services.output, pan)
                        }
                        Repeater {
                            model: Services.audioStreams
                            ControlStrip {
                                required property var modelData
                                readonly property bool shut: !!modelData.audio && modelData.audio.muted
                                height: strips.height
                                width: strips.lane
                                title: control.streamName(modelData)
                                tag: Theme.mix(Theme.moduleAlt, Theme.text, 0.25)
                                value: control.level(modelData)
                                muted: shut
                                silent: shut || (!!control.soloTarget && control.soloTarget !== modelData)
                                soloable: true
                                soloed: control.soloTarget === modelData
                                meter: control.outputMeter.level * Math.min(1, control.level(modelData))
                                pan: control.balance(modelData)
                                pannable: !!modelData.audio && (modelData.audio.volumes || []).length === 2
                                enabled: !!modelData.audio
                                onMoved: value => control.setLevel(modelData, value, v => Services.setStreamVolume(modelData, v))
                                onMuteClicked: if (modelData.audio) modelData.audio.muted = !modelData.audio.muted
                                onSoloClicked: control.toggleSolo(modelData)
                                onPanMoved: pan => control.setBalance(modelData, pan)
                            }
                        }
                        ControlStrip {
                            visible: !!Services.input
                            height: strips.height
                            width: strips.lane
                            title: "Mic"
                            tag: Theme.textSecondary
                            fillColor: Theme.textSecondary
                            meterColor: Theme.textSecondary
                            value: control.level(Services.input)
                            muted: Services.micMuted
                            pan: control.balance(Services.input)
                            pannable: !!Services.input && !!Services.input.audio && (Services.input.audio.volumes || []).length === 2
                            onMoved: value => control.setLevel(Services.input, value, v => Services.setMicVolume(v))
                            onMuteClicked: Services.toggleMicMute()
                            onPanMoved: pan => control.setBalance(Services.input, pan)
                        }
                    }
                }
                C.Caption {
                    visible: Services.audioStreams.length === 0
                    text: "Apps get a strip of their own while they play"
                    Layout.fillWidth: true
                }
            }
        }
        Equalizer {
            Layout.fillWidth: true
            graphHeight: 130
            active: ShellState.detail === "audio"
        }
    }
}
