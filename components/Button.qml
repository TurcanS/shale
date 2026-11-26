import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
// Qualified: QtQuick.Controls has its own Label, which would ignore the shell font and text size.
import "." as C

// Secondary keys by default; accent is the primary action (accent fill, dark ink), danger is destructive (danger
// edge, wash and text), selected is "on" (a raised neutral key with an accent glyph), flat has no key until hovered.
AbstractButton {
    id: root
    property string glyph: ""
    property string hint: ""
    // A Tooltip that shows `hint` while the pointer rests here; for icon-only controls outside panels.
    property var tooltip: null
    property bool selected: false
    property bool danger: false
    property bool flat: false
    property bool accent: false
    // Optional status tint for the label: "warning" or "danger".
    property string tone: ""
    property int labelSize: Theme.label
    property real cornerRadius: height > 40 ? Theme.radiusCard : Theme.radiusKey
    readonly property bool iconOnly: text === "" && glyph !== ""
    // Label and glyph share one colour, except that an "on" key keeps the accent on its glyph only. Controls built on
    // Button may set their own.
    property color foreground: !enabled ? Theme.textFaint : danger || tone === "danger" ? Theme.dangerText : tone === "warning" ? Theme.warning : accent ? Theme.accentInk : Theme.text
    property color glyphColor: enabled && selected && !accent && !danger && tone === "" ? Theme.accentText : foreground
    // Hover and press tints for keys without a fill of their own; translucent so they work on any surface.
    readonly property color wash: Theme.keyWash(down)
    // implicitContentWidth is the control's own measure of its content item: it follows a custom content item and
    // text measured late (the bundled fonts load after the first layout), where a binding through contentItem doesn't.
    implicitWidth: iconOnly ? Math.max(implicitHeight, implicitContentWidth + leftPadding + rightPadding)
                            : Math.max(28, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Theme.controlHeight
    Layout.minimumWidth: 0
    padding: iconOnly ? 8 : height > 32 ? 16 : 12
    topPadding: 4
    bottomPadding: 4
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    Accessible.name: text || hint
    Accessible.role: Accessible.Button
    // Return and Enter press a focused key, as Space does. A key with its own Keys.onReturnPressed keeps it: Qt calls
    // that first and stops there.
    Keys.onPressed: event => {
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !event.isAutoRepeat && enabled) {
            clicked();
            event.accepted = true;
        }
    }
    onHoveredChanged: if (tooltip) hovered ? tooltip.show(root) : tooltip.hide(root, false)
    onPressedChanged: if (tooltip && pressed) tooltip.hide(root, true)
    scale: down && !Theme.reduced ? Theme.pressScale : 1
    Behavior on scale {
        NumberAnimation {
            duration: Theme.press
            easing.type: Easing.OutCubic
        }
    }
    // Key travel: a press also sinks the key a pixel with a darker top edge, like a real key going down, and letting
    // go brings it straight back. Whole rows set pressDepth 0. Calm keeps only the scale.
    property real pressDepth: 1
    property real sunk: down && !Motion.calm ? pressDepth : 0
    Behavior on sunk {
        NumberAnimation {
            duration: root.down ? Motion.ms(60) : Motion.ms(110)
            easing.type: Easing.OutQuad
        }
    }
    transform: Translate {
        y: root.sunk
    }
    background: Rectangle {
        readonly property bool lit: root.hovered || root.down || root.visualFocus
        radius: root.cornerRadius
        color: !root.enabled ? (root.flat ? "transparent" : Theme.module)
             : root.accent ? (lit ? Theme.accentHover : Theme.accent)
             : root.danger && !root.flat ? (lit ? Theme.dangerSoft : Theme.dangerWash)
             : root.danger ? (lit ? Theme.dangerWash : "transparent")
             : root.selected ? Theme.raised
             : root.flat ? (lit ? root.wash : "transparent")
             : lit ? Theme.keyHover : Theme.key
        border.width: root.enabled && !root.flat && root.danger ? 1 : 0
        border.color: Theme.dangerLine
        Behavior on color {
            ColorAnimation {
                duration: Theme.fast
            }
        }
        // Keys sit up a little; an "on" key a little more. Flat keys only when on; danger keys keep their edge.
        C.Raise {
            readonly property bool on: root.selected && !root.accent && !root.danger
            shown: root.enabled && (on || !root.flat && !root.danger)
            resting: !on
            sunk: root.sunk
        }
        // Hovering an "on" key lays a light wash on top instead of swapping colours.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: root.enabled && root.selected && !root.accent && !root.danger
            color: root.wash
            opacity: parent.lit ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.fast
                }
            }
        }
    }
    Rectangle {
        anchors.fill: parent
        visible: root.sunk > 0.01 && !root.flat
        radius: root.cornerRadius
        opacity: root.sunk
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.28) }
            GradientStop { position: 0.35; color: "transparent" }
        }
    }
    // Keyboard focus only (visualFocus is false for mouse clicks), so there are still no click outlines.
    Rectangle {
        anchors.fill: parent
        z: 10
        visible: root.visualFocus
        color: "transparent"
        radius: root.background && root.background.radius !== undefined ? root.background.radius : root.cornerRadius
        border.width: 2
        border.color: root.accent ? Theme.accentInk : Theme.text
        opacity: 0.85
    }
    contentItem: Item {
        // Summed from the parts rather than read from the layout, which only measures again on its next polish.
        // Rounded up: the layout gives the label whole pixels, and a fraction short would elide it.
        implicitWidth: Math.ceil((root.glyph !== "" ? glyphIcon.implicitWidth : 0) + (root.text !== "" ? label.implicitWidth : 0)
                       + (root.glyph !== "" && root.text !== "" ? contents.spacing : 0))
        implicitHeight: Math.max(root.glyph !== "" ? glyphIcon.implicitHeight : 0, root.text !== "" ? label.implicitHeight : 0)
        RowLayout {
            id: contents
            anchors.centerIn: parent
            width: Math.min(parent.width, implicitWidth)
            spacing: Theme.gapS
            C.Icon {
                id: glyphIcon
                visible: root.glyph !== ""
                name: root.glyph
                color: root.glyphColor
                Layout.alignment: Qt.AlignVCenter
            }
            C.Label {
                id: label
                visible: root.text !== ""
                text: root.text
                font.pixelSize: root.labelSize
                font.weight: root.accent ? 650 : Font.DemiBold
                color: root.foreground
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
    }
}
