import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import "../core"
import "../components" as C

// System-wide 10-band equalizer. The backend owns the PipeWire filter; settings keep it across restarts.
Rectangle {
    id: root
    property bool active: false
    readonly property var frequencies: ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    // Mirrors PRESETS in helpers/equalizer.py.
    readonly property var presets: ({
        flat: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        bass: [6, 5.5, 4.5, 3, 1, 0, 0, 0, 0, 0],
        vocal: [-2, -2, -1, 0.5, 2.5, 3.5, 3, 2, 0.5, -1],
        treble: [0, 0, 0, 0, 0, 0.5, 2, 3.5, 5, 6],
        loudness: [5, 4, 2, 0, -1, -1, 0, 1.5, 3.5, 4.5]
    })
    readonly property var presetLabels: [["flat", "Flat"], ["bass", "Bass"], ["vocal", "Vocal"], ["treble", "Treble"], ["loudness", "Loudness"]]
    readonly property real limit: 12
    readonly property bool eqOn: ShellState.setting("eqEnabled", false)
    readonly property string preset: ShellState.setting("eqPreset", "flat")
    // Edits stay local while a band is being adjusted, then persist once.
    property var draft: null
    readonly property var levels: draft || ShellState.setting("eqBands", presets.flat)
    readonly property real headroom: Math.max(0, ...levels)
    property bool busy: false
    // Only the on/off switch reports progress; live band updates stay silent.
    property bool switching: false
    // Presets and resets glide from the previous curve instead of jumping.
    property var glideFrom: []
    property real glide: 1
    readonly property var shown: glide >= 1 ? levels : levels.map((value, i) => {
        const from = glideFrom[i] === undefined ? value : glideFrom[i];
        return from + (value - from) * glide;
    })

    function presetLabel(key) {
        const entry = presetLabels.find(item => item[0] === key);
        return entry ? entry[1] : "Custom";
    }
    function matchingPreset(values) {
        return Object.keys(presets).find(key => presets[key].every((value, i) => value === values[i])) || "custom";
    }
    function apply() {
        busy = true;
        Backend.request("eq.apply", {enabled: eqOn, bands: levels}, (r, e) => {
            busy = false;
            switching = false;
            if (!e)
                return;
            ShellState.message(e.message || "The equalizer is unavailable", "error");
            if (ShellState.setting("eqEnabled", false))
                ShellState.setSetting("eqEnabled", false);
        });
    }
    function setEnabled(value) {
        ShellState.setSetting("eqEnabled", value);
        switching = true;
        apply();
    }
    function glideTo(values, key) {
        commitTimer.stop();
        glideFrom = shown.slice();
        draft = null;
        ShellState.setSetting("eqBands", values.slice());
        ShellState.setSetting("eqPreset", key);
        if (!Theme.reduced) {
            glide = 0;
            glideAnimation.restart();
        }
        apply();
    }
    function setBand(index, value) {
        const next = levels.slice();
        next[index] = Math.abs(value) < 0.75 ? 0 : Math.round(value * 2) / 2;
        if (next[index] === levels[index])
            return;
        glideAnimation.stop();
        glide = 1;
        draft = next;
        if (!applyTimer.running)
            applyTimer.start();
        commitTimer.restart();
    }
    function resetBand(index) {
        const values = levels.map((value, i) => i === index ? 0 : value);
        glideTo(values, matchingPreset(values));
    }
    function commit() {
        if (!draft)
            return;
        const values = draft;
        ShellState.setSetting("eqBands", values);
        ShellState.setSetting("eqPreset", matchingPreset(values));
        draft = null;
    }
    // Picks up a filter that stopped outside the shell, e.g. after a PipeWire restart.
    onActiveChanged: if (active && eqOn)
        Backend.request("eq.status", {}, (r, e) => {
            if (!e && !r.enabled && root.eqOn && !root.busy)
                root.apply();
        })

    implicitHeight: column.implicitHeight
    radius: Theme.controlRadius
    color: Theme.surface
    clip: true

    NumberAnimation {
        id: glideAnimation
        target: root
        property: "glide"
        from: 0
        to: 1
        duration: Theme.enter + 60
        easing.type: Easing.OutCubic
    }
    // Throttles live updates while dragging; the filter follows the knob without flooding PipeWire.
    Timer {
        id: applyTimer
        interval: 80
        onTriggered: root.apply()
    }
    Timer {
        id: commitTimer
        interval: 350
        onTriggered: root.commit()
    }

    ColumnLayout {
        id: column
        width: parent.width
        spacing: 0
        C.Toggle {
            Layout.fillWidth: true
            glyph: "equalizer"
            text: "Equalizer"
            description: root.switching ? (root.eqOn ? "Starting…" : "Turning off…") : root.eqOn ? root.presetLabel(root.preset) + " · applies to all audio" : "Off"
            selected: root.eqOn
            onClicked: if (!root.switching)
                root.setEnabled(!root.eqOn)
        }
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.eqOn ? content.implicitHeight + 16 : 0
            visible: Layout.preferredHeight > 0
            opacity: root.eqOn ? 1 : 0
            clip: true
            Behavior on Layout.preferredHeight {
                NumberAnimation {
                    duration: Theme.enter
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.fast
                }
            }
            ColumnLayout {
                id: content
                x: 12
                width: parent.width - 24
                spacing: 12
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: root.presetLabels
                        C.Button {
                            required property var modelData
                            text: modelData[1]
                            implicitHeight: 30
                            padding: 12
                            cornerRadius: 15
                            selected: root.preset === modelData[0]
                            Accessible.role: Accessible.RadioButton
                            Accessible.checked: selected
                            onClicked: root.glideTo(root.presets[modelData[0]], modelData[0])
                        }
                    }
                }
                Item {
                    id: bands
                    Layout.fillWidth: true
                    Layout.preferredHeight: 164
                    readonly property real axisWidth: 26
                    readonly property real trackTop: 6
                    readonly property real trackHeight: 132
                    readonly property real knob: 14
                    readonly property real columnWidth: (width - axisWidth) / root.levels.length
                    function xFor(index) {
                        return axisWidth + columnWidth * (index + 0.5);
                    }
                    function yFor(value) {
                        return trackTop + knob / 2 + (1 - (value + root.limit) / (2 * root.limit)) * (trackHeight - knob);
                    }
                    // Catmull-Rom through the knobs, drawn as cubic Béziers.
                    function curve(values) {
                        const p = values.map((v, i) => [xFor(i), yFor(v)]);
                        let path = "M " + p[0][0] + " " + p[0][1];
                        for (let i = 0; i < p.length - 1; i++) {
                            const a = p[Math.max(0, i - 1)], b = p[i], c = p[i + 1], d = p[Math.min(p.length - 1, i + 2)];
                            path += " C " + (b[0] + (c[0] - a[0]) / 6) + " " + (b[1] + (c[1] - a[1]) / 6) + " " + (c[0] - (d[0] - b[0]) / 6) + " " + (c[1] - (d[1] - b[1]) / 6) + " " + c[0] + " " + c[1];
                        }
                        return path;
                    }
                    readonly property string curvePath: curve(root.shown)
                    readonly property real zero: yFor(0)

                    Repeater {
                        model: [root.limit, 0, -root.limit]
                        Item {
                            required property real modelData
                            width: bands.width
                            y: bands.yFor(modelData)
                            Rectangle {
                                x: bands.axisWidth
                                width: parent.width - bands.axisWidth
                                height: 1
                                color: Theme.border
                                opacity: modelData === 0 ? 1 : 0.45
                            }
                            C.Label {
                                width: bands.axisWidth - 6
                                y: -height / 2
                                horizontalAlignment: Text.AlignRight
                                text: modelData > 0 ? "+" + modelData : String(modelData)
                                color: Theme.disabled
                                font.family: Theme.mono
                                font.pixelSize: Theme.caption
                            }
                        }
                    }
                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeWidth: 0
                            strokeColor: "transparent"
                            fillColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                            PathSvg {
                                path: bands.curvePath + " L " + bands.xFor(root.levels.length - 1) + " " + bands.zero + " L " + bands.xFor(0) + " " + bands.zero + " Z"
                            }
                        }
                        ShapePath {
                            strokeWidth: 2
                            strokeColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.7)
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            joinStyle: ShapePath.RoundJoin
                            PathSvg {
                                path: bands.curvePath
                            }
                        }
                    }
                    Repeater {
                        model: root.levels.length
                        Item {
                            id: band
                            required property int index
                            x: bands.axisWidth + bands.columnWidth * index
                            width: bands.columnWidth
                            height: bands.height
                            Slider {
                                id: slider
                                x: (parent.width - width) / 2
                                y: bands.trackTop
                                width: Math.min(parent.width, 28)
                                height: bands.trackHeight
                                padding: 0
                                orientation: Qt.Vertical
                                from: -root.limit
                                to: root.limit
                                stepSize: 0.5
                                value: root.shown[band.index]
                                wheelEnabled: false
                                Accessible.name: root.frequencies[band.index] + " hertz band"
                                onMoved: root.setBand(band.index, value)
                                onPressedChanged: if (!pressed)
                                    root.commit()
                                background: Item {
                                    Rectangle {
                                        x: (slider.width - width) / 2
                                        y: bands.knob / 2
                                        width: 4
                                        height: slider.height - bands.knob
                                        radius: 2
                                        color: Theme.raised
                                    }
                                    Rectangle {
                                        readonly property real knobY: bands.yFor(slider.value) - bands.trackTop
                                        readonly property real zeroY: bands.zero - bands.trackTop
                                        x: (slider.width - width) / 2
                                        y: Math.min(knobY, zeroY)
                                        width: 4
                                        height: Math.abs(knobY - zeroY)
                                        radius: 2
                                        color: Theme.activityLevel3
                                    }
                                }
                                handle: Rectangle {
                                    x: (slider.width - width) / 2
                                    y: bands.yFor(slider.value) - bands.trackTop - height / 2
                                    width: slider.pressed ? 18 : slider.hovered ? 16 : bands.knob
                                    height: width
                                    radius: width / 2
                                    color: Theme.accent
                                    border.width: 2
                                    border.color: Theme.surface
                                    Behavior on width {
                                        NumberAnimation {
                                            duration: Theme.fast
                                        }
                                    }
                                }
                                TapHandler {
                                    onDoubleTapped: root.resetBand(band.index)
                                }
                            }
                            // Gain readout while adjusting; sits on the far side of the knob from the edge.
                            Rectangle {
                                readonly property real knobY: bands.yFor(slider.value)
                                visible: slider.pressed || slider.hovered
                                x: (parent.width - width) / 2
                                y: knobY < bands.trackTop + 30 ? knobY + 13 : knobY - height - 13
                                z: 2
                                width: gainText.implicitWidth + 10
                                height: gainText.implicitHeight + 4
                                radius: height / 2
                                color: Theme.raised
                                C.Label {
                                    id: gainText
                                    anchors.centerIn: parent
                                    text: (slider.value > 0 ? "+" : "") + slider.value.toFixed(1)
                                    font.family: Theme.mono
                                    font.pixelSize: Theme.caption
                                }
                            }
                            C.Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                text: root.frequencies[band.index]
                                color: slider.pressed ? Theme.text : Theme.muted
                                font.family: Theme.mono
                                font.pixelSize: Theme.caption
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    C.Label {
                        Layout.fillWidth: true
                        text: root.headroom > 0 ? "Level lowered " + root.headroom.toFixed(1) + " dB to prevent clipping" : "Double-click a band to reset it"
                        color: Theme.muted
                        font.pixelSize: Theme.caption
                    }
                    C.Button {
                        text: "Reset"
                        flat: true
                        implicitHeight: 28
                        enabled: root.levels.some(v => v !== 0)
                        hint: "Reset all bands to flat"
                        onClicked: root.glideTo(root.presets.flat, "flat")
                    }
                }
            }
        }
    }
}
