import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../components" as C

// One mixer channel: colour tag, name, pan ring, stereo meters beside the fader, level, then M and S.
Rectangle {
    id: strip
    property string title: ""
    property color tag: Theme.key
    property color fillColor: Theme.textDim
    property color meterColor: Theme.accent
    property real value: 0
    property real maximum: 1
    property bool muted: false
    property bool soloable: false
    property bool soloed: false
    // Muted, or silenced by another channel's solo.
    property bool silent: muted
    property real meter: 0
    property real pan: 0
    property bool pannable: false
    signal moved(real value)
    signal muteClicked()
    signal soloClicked()
    signal panMoved(real pan)
    implicitWidth: 72
    radius: Theme.radiusCard
    color: Theme.moduleAlt
    // The tag follows the strip's rounded top: the top 3 px of a rounded shape the strip's size.
    Item {
        width: parent.width
        height: 3
        clip: true
        Rectangle {
            width: strip.width
            height: strip.height
            radius: strip.radius
            color: strip.tag
        }
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 11
        anchors.bottomMargin: 8
        spacing: Theme.gapS
        C.Label {
            text: strip.title
            font.pixelSize: 12
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: strip.width - 8
        }
        // Pan: drag sideways or scroll; a double-click centres it.
        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 30
            implicitHeight: 30
            opacity: strip.pannable ? 1 : 0.5
            Accessible.name: strip.title + " pan"
            C.Ring {
                anchors.fill: parent
                size: 30
                thickness: 3
                span: 130
                value: strip.pan
                color: Theme.textSecondary
            }
            Rectangle {
                anchors.centerIn: parent
                width: 4
                height: 4
                radius: 2
                color: Theme.textDim
            }
            MouseArea {
                property real startX: 0
                property real startPan: 0
                anchors.fill: parent
                enabled: strip.pannable
                cursorShape: Qt.SizeHorCursor
                onPressed: mouse => {
                    startX = mouse.x;
                    startPan = strip.pan;
                }
                onPositionChanged: mouse => {
                    if (pressed)
                        strip.panMoved(startPan + (mouse.x - startX) / 40);
                }
                onDoubleClicked: strip.panMoved(0)
                onWheel: wheel => strip.panMoved(strip.pan + (wheel.angleDelta.y > 0 ? 0.1 : -0.1))
            }
        }
        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: true
            Layout.minimumHeight: 80
            implicitWidth: 56
            Repeater {
                // Left and right; the right one trails a little so the pair reads as stereo.
                model: [6, 12]
                Rectangle {
                    required property real modelData
                    required property int index
                    x: modelData
                    width: 4
                    height: parent.height
                    radius: 2
                    color: Theme.mix(Theme.backdrop, Qt.rgba(0, 0, 0, 1), 0.2)
                    clip: true
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: parent.height * (strip.silent ? 0 : strip.meter * (index ? 0.94 : 1))
                        gradient: Gradient {
                            GradientStop { position: 0; color: strip.meterColor }
                            GradientStop { position: 1; color: Theme.accentSoft }
                        }
                        Behavior on height {
                            NumberAnimation {
                                duration: Theme.fast
                                easing.type: Easing.OutQuad
                            }
                        }
                    }
                }
            }
            Slider {
                id: fader
                x: 22
                width: 24
                height: parent.height
                orientation: Qt.Vertical
                padding: 0
                topPadding: 7
                bottomPadding: 7
                from: 0
                to: strip.maximum
                stepSize: 0.01
                value: strip.value
                wheelEnabled: true
                Accessible.name: strip.title + " volume"
                onMoved: strip.moved(value)
                background: Item {
                    Rectangle {
                        x: (fader.width - width) / 2
                        y: fader.topPadding
                        width: 2
                        height: fader.availableHeight
                        radius: 1
                        color: Theme.key
                    }
                    Rectangle {
                        x: (fader.width - width) / 2
                        y: fader.topPadding + fader.visualPosition * fader.availableHeight
                        width: 2
                        height: (1 - fader.visualPosition) * fader.availableHeight
                        radius: 1
                        color: strip.silent ? Theme.textFaint : strip.fillColor
                    }
                }
                handle: Rectangle {
                    x: (fader.width - width) / 2
                    y: fader.topPadding + fader.visualPosition * fader.availableHeight - height / 2
                    width: 24
                    height: 14
                    radius: 4
                    color: Theme.knob
                    Rectangle {
                        anchors.centerIn: parent
                        width: 14
                        height: 2
                        radius: 1
                        color: Theme.accentInk
                    }
                    C.FocusRing {
                        visible: fader.visualFocus
                        inset: 3
                        radius: 7
                    }
                }
            }
        }
        C.Label {
            text: strip.muted ? "Off" : String(Math.round((fader.pressed ? fader.value : strip.value) * 100))
            color: strip.silent ? Theme.textFaint : Theme.textSecondary
            font.family: Theme.mono
            font.pixelSize: 11
            font.features: {"tnum": 1}
            Layout.alignment: Qt.AlignHCenter
        }
        Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: 4
            ControlStripKey {
                text: "M"
                hint: (strip.muted ? "Unmute " : "Mute ") + strip.title
                selected: strip.muted
                onColor: Theme.tint(Theme.danger, 0.2)
                onText: Theme.dangerText
                onClicked: strip.muteClicked()
            }
            ControlStripKey {
                visible: strip.soloable
                text: "S"
                hint: strip.soloed ? "Stop playing " + strip.title + " alone" : "Play only " + strip.title
                selected: strip.soloed
                onClicked: strip.soloClicked()
            }
        }
    }
}
