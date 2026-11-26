import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import "../core"
import "." as C

// One level on one line: a 32 px icon key (a mute button when muteable), the name, a 6 px track with a light knob,
// and the value. The fill is the accent; glow draws the volume fill as an accent gradient with a soft glow.
RowLayout {
    id: root
    property string title: ""
    property string glyph: "volume"
    property real value: 0
    property real maximum: 1
    // A muteable row turns its icon into a mute toggle; muted keeps the real level visible.
    property bool muteable: false
    property bool muted: false
    property string mutedGlyph: "mute"
    // With a hint, a trailing chevron opens this level's detail page.
    property string detailHint: ""
    // The name beside the track; rows a glyph already names (volume, brightness) can hide it.
    property bool showTitle: title !== ""
    property bool glow: false
    signal moved(real value)
    signal iconClicked()
    signal detailRequested()
    spacing: Theme.gapM
    opacity: enabled ? 1 : Theme.disabledOpacity
    Accessible.name: root.title
    Rectangle {
        visible: !root.muteable
        implicitWidth: 32
        implicitHeight: 32
        radius: Theme.radiusKey
        color: Theme.key
        C.Icon {
            anchors.centerIn: parent
            name: root.glyph
        }
    }
    C.Button {
        id: muteButton
        visible: root.muteable
        glyph: root.muted ? root.mutedGlyph : root.glyph
        implicitWidth: 32
        implicitHeight: 32
        // Muted reads as a soft danger key, whichever glyph it shows.
        foreground: root.muted ? Theme.dangerText : Theme.text
        background: Rectangle {
            radius: Theme.radiusKey
            color: root.muted ? (muteButton.hovered ? Theme.tint(Theme.danger, 0.24) : Theme.dangerSoft) : muteButton.hovered || muteButton.down ? Theme.keyHover : Theme.key
            Behavior on color { ColorAnimation { duration: Theme.fast } }
        }
        hint: (root.muted ? "Unmute " : "Mute ") + root.title.toLowerCase()
        Accessible.role: Accessible.CheckBox
        Accessible.checkable: true
        Accessible.checked: root.muted
        onClicked: root.iconClicked()
    }
    C.Label {
        visible: root.showTitle
        text: root.title
        color: root.muted ? Theme.textDim : Theme.textSecondary
        font.pixelSize: Theme.label
        // One width for every row, so stacked tracks line up.
        Layout.preferredWidth: 84
    }
    Slider {
        id: slider
        Layout.fillWidth: true
        from: 0
        to: root.maximum
        value: root.value
        stepSize: 0.05
        wheelEnabled: true
        implicitHeight: 32
        padding: 0
        leftPadding: 0
        rightPadding: 0
        Accessible.name: root.title
        onMoved: root.moved(value)
        // Where the fill and knob are drawn. Dragged, they follow the pointer exactly; a level changed elsewhere (keys,
        // the OSD, another app) swings there like a VU needle and stops at the ends.
        property real shown: visualPosition
        C.Ballistic on shown {
            enabled: !slider.pressed && !Motion.reduced
        }
        readonly property real drawn: Math.max(0, Math.min(1, shown))
        background: Rectangle {
            x: slider.leftPadding
            y: (slider.height - height) / 2
            width: slider.availableWidth
            height: 6
            radius: 3
            color: Theme.key
            Rectangle {
                id: fillBar
                readonly property bool lit: root.glow && !root.muted
                width: Math.max(height, slider.drawn * parent.width)
                height: parent.height
                radius: 3
                visible: slider.drawn > 0.002
                color: root.muted ? Theme.textFaint : Theme.accent
                gradient: lit ? volumeGradient : null
                Behavior on color {
                    ColorAnimation {
                        duration: Theme.fast
                    }
                }
                Gradient {
                    id: volumeGradient
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Theme.accentSoft }
                    GradientStop { position: 1; color: Theme.accent }
                }
                // The glow costs a blur pass; power saver goes without it.
                layer.enabled: lit && !Theme.lowPower
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Theme.accentGlow
                    shadowBlur: 1
                    blurMax: 12
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                }
            }
        }
        handle: Item {
            x: slider.leftPadding + slider.drawn * (slider.availableWidth - width)
            y: (slider.height - height) / 2
            width: 18
            height: 18
            // A soft shadow under the knob, drawn as a darker disc a pixel lower.
            Rectangle {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 1
                width: knob.width + 2
                height: width
                radius: width / 2
                color: Qt.rgba(0, 0, 0, 0.35)
            }
            C.FocusRing {
                visible: slider.visualFocus
                inset: 3
            }
            Rectangle {
                id: knob
                anchors.centerIn: parent
                width: slider.pressed ? 18 : 16
                height: width
                radius: width / 2
                color: Theme.knob
                Behavior on width {
                    NumberAnimation {
                        duration: Theme.fast
                    }
                }
            }
        }
    }
    C.Label {
        text: root.muted ? "Off" : String(Math.round((slider.pressed ? slider.value : root.value) * 100))
        color: root.muted ? Theme.textDim : Theme.textSecondary
        font.family: Theme.mono
        font.pixelSize: Theme.small
        font.features: {"tnum": 1}
        horizontalAlignment: Text.AlignRight
        Layout.preferredWidth: 34
    }
    C.Button {
        visible: root.detailHint !== ""
        glyph: "chevron"
        flat: true
        hint: root.detailHint
        implicitWidth: Theme.controlSmall
        implicitHeight: Theme.controlSmall
        Layout.leftMargin: -Theme.gapXs
        Layout.rightMargin: -4
        onClicked: root.detailRequested()
    }
}
