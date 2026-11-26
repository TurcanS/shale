import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import "../core"
import "../components" as C

// System-wide 10-band equalizer as a module: a switch, the presets, and a graph whose band points drag up and down.
// The backend owns the PipeWire filter; settings keep it across restarts.
Rectangle {
    id: root
    property bool active: false
    // The graph's height when nothing stretches it.
    property int graphHeight: 200
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
    // Band drags send several applies at once; busy holds until the last one answers.
    property int applying: 0
    readonly property bool busy: applying > 0
    // Only the on/off switch reports progress; live band updates stay silent.
    property bool switching: false
    // Presets and resets glide from the previous curve instead of jumping.
    property var glideFrom: []
    property real glide: 1
    readonly property var shown: glide >= 1 ? levels : levels.map((value, i) => {
        const from = glideFrom[i] === undefined ? value : glideFrom[i];
        return from + (value - from) * glide;
    })

    function matchingPreset(values) {
        return Object.keys(presets).find(key => presets[key].every((value, i) => value === values[i])) || "custom";
    }
    function apply() {
        applying++;
        Backend.request("eq.apply", {enabled: eqOn, bands: levels}, (r, e) => {
            if (e) {
                ShellState.message(e.message || "The equalizer is unavailable", "error");
                if (ShellState.setting("eqEnabled", false))
                    ShellState.setSetting("eqEnabled", false);
            }
            // Control closed meanwhile.
            if (!root)
                return;
            applying = Math.max(0, applying - 1);
            if (applying === 0)
                switching = false;
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
    // Closing the panel within the save delay must not lose the curve just dragged.
    Component.onDestruction: commit()
    // Picks up a filter that stopped outside the shell, e.g. after a PipeWire restart.
    onActiveChanged: if (active && eqOn)
        Backend.request("eq.status", {}, (r, e) => {
            if (!e && !r.enabled && root.eqOn && !root.busy)
                root.apply();
        }, {owner: root})

    implicitHeight: column.implicitHeight + 24
    radius: Theme.radiusModule
    color: Theme.module

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
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gapS
            C.Label {
                text: "Equalizer"
                font.pixelSize: 15
                font.weight: 650
                elide: Text.ElideNone
            }
            C.Label {
                text: root.switching ? (root.eqOn ? "starting…" : "turning off…") : root.eqOn ? "all audio" : "off"
                color: Theme.textDim
                font.pixelSize: 12
                Layout.fillWidth: true
            }
            C.Switch {
                hint: root.eqOn ? "Turn the equalizer off" : "Turn the equalizer on"
                selected: root.eqOn
                onClicked: if (!root.switching)
                    root.setEnabled(!root.eqOn)
            }
        }
        C.Segmented {
            Layout.fillWidth: true
            trackColor: Theme.well
            segmentHeight: 30
            proportional: true
            model: root.presetLabels.map(item => ({key: item[0], text: item[1], hint: item[1] + " preset"}))
            current: root.preset
            onActivated: key => root.glideTo(root.presets[key], key)
        }
        // The curve over a grid (+6, 0 dashed, −6 dB); each band point drags, and a double-click resets it.
        Rectangle {
            id: graph
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: root.graphHeight
            Layout.minimumHeight: Math.min(130, root.graphHeight)
            radius: Theme.radiusCard
            color: Theme.well
            clip: true
            Item {
                id: bands
                anchors.fill: parent
                opacity: root.eqOn ? 1 : 0.45
                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.fast
                    }
                }
                readonly property real plotTop: 10
                readonly property real plotBottom: height - 24
                readonly property real knob: 10
                readonly property real columnWidth: width / root.levels.length
                function xFor(index) {
                    return columnWidth * (index + 0.5);
                }
                function yFor(value) {
                    return plotTop + (1 - (value + root.limit) / (2 * root.limit)) * (plotBottom - plotTop);
                }
                // Catmull-Rom through the points, drawn as cubic Béziers, flat out to both edges.
                function curve(values) {
                    const p = values.map((v, i) => [xFor(i), yFor(v)]);
                    let path = "M 0 " + p[0][1] + " L " + p[0][0] + " " + p[0][1];
                    for (let i = 0; i < p.length - 1; i++) {
                        const a = p[Math.max(0, i - 1)], b = p[i], c = p[i + 1], d = p[Math.min(p.length - 1, i + 2)];
                        path += " C " + (b[0] + (c[0] - a[0]) / 6) + " " + (b[1] + (c[1] - a[1]) / 6) + " " + (c[0] - (d[0] - b[0]) / 6) + " " + (c[1] - (d[1] - b[1]) / 6) + " " + c[0] + " " + c[1];
                    }
                    return path + " L " + width + " " + p[p.length - 1][1];
                }
                readonly property string curvePath: curve(root.shown)

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: Theme.mix(Theme.well, Theme.text, 0.06)
                        strokeWidth: 1
                        fillColor: "transparent"
                        PathSvg {
                            path: "M 0 " + bands.yFor(root.limit / 2) + " L " + bands.width + " " + bands.yFor(root.limit / 2)
                                  + " M 0 " + bands.yFor(-root.limit / 2) + " L " + bands.width + " " + bands.yFor(-root.limit / 2)
                        }
                    }
                    ShapePath {
                        strokeColor: Theme.mix(Theme.well, Theme.text, 0.16)
                        strokeWidth: 1
                        strokeStyle: ShapePath.DashLine
                        dashPattern: [3, 4]
                        fillColor: "transparent"
                        PathSvg {
                            path: "M 0 " + bands.yFor(0) + " L " + bands.width + " " + bands.yFor(0)
                        }
                    }
                    ShapePath {
                        strokeWidth: 0
                        strokeColor: "transparent"
                        fillGradient: LinearGradient {
                            x1: 0
                            y1: bands.plotTop
                            x2: 0
                            y2: bands.height
                            GradientStop { position: 0; color: Theme.tint(Theme.accent, 0.35) }
                            GradientStop { position: 1; color: Theme.tint(Theme.accent, 0) }
                        }
                        PathSvg {
                            path: bands.curvePath + " L " + bands.width + " " + bands.height + " L 0 " + bands.height + " Z"
                        }
                    }
                    ShapePath {
                        strokeWidth: 2
                        strokeColor: Theme.accent
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
                        x: bands.columnWidth * index
                        width: bands.columnWidth
                        height: bands.height
                        Slider {
                            id: slider
                            x: (parent.width - width) / 2
                            y: bands.plotTop - bands.knob / 2
                            width: Math.min(parent.width, 28)
                            height: bands.plotBottom - bands.plotTop + bands.knob
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
                            background: Item {}
                            handle: Rectangle {
                                x: (slider.width - width) / 2
                                y: bands.yFor(slider.value) - slider.y - height / 2
                                width: slider.pressed ? 13 : slider.hovered || slider.visualFocus ? 12 : bands.knob
                                height: width
                                radius: width / 2
                                color: Theme.knob
                                border.width: 2
                                border.color: Theme.well
                                C.FocusRing {
                                    visible: slider.visualFocus
                                    inset: 3
                                }
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
                        // Gain readout while adjusting; sits on the far side of the point from the edge.
                        Rectangle {
                            readonly property real knobY: bands.yFor(slider.value)
                            visible: slider.pressed || slider.hovered
                            x: (parent.width - width) / 2
                            y: knobY < bands.plotTop + 30 ? knobY + 11 : knobY - height - 11
                            z: 2
                            width: gainText.implicitWidth + 10
                            height: gainText.implicitHeight + 4
                            radius: height / 2
                            color: Theme.keySelected
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
                            anchors.bottomMargin: 4
                            text: root.frequencies[band.index]
                            color: slider.pressed ? Theme.text : Theme.textDim
                            font.family: Theme.mono
                            font.pixelSize: 9
                        }
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gapS
            C.Label {
                Layout.fillWidth: true
                text: root.headroom > 0 ? "Level lowered " + root.headroom.toFixed(1) + " dB to prevent clipping" : "Double-click a point to reset it"
                color: Theme.textDim
                font.pixelSize: 12
            }
            C.Button {
                text: "Reset"
                flat: true
                implicitHeight: 28
                labelSize: 12
                enabled: root.levels.some(v => v !== 0)
                hint: "Reset all bands to flat"
                onClicked: root.glideTo(root.presets.flat, "flat")
            }
        }
    }
}
