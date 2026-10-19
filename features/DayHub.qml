pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

// Placeholder Day hub for the morph spike: the bar's Day pill grows into it, and every visual is a function of
// one number, progress (0: the pill, 1: the open hub), so a reversal at any moment needs no special case.
Item {
    id: hub
    property real progress: 0
    // True while opening; closing runs the same curves backwards, without the stagger.
    property bool opening: false
    property bool edge: false
    // Where the pill sits in the bar, in this item's coordinates.
    property rect pill: Qt.rect(0, 0, 0, 0)
    readonly property int openWidth: 640
    readonly property int openHeight: 460
    readonly property alias shape: shape
    signal dismissed()
    function settle(from, to, t) {
        return from + (to - from) * t;
    }
    function clamp(t) {
        return Math.max(0, Math.min(1, t));
    }
    // A small overshoot on the width only: on a 460 px height the same overshoot would be 9+ px and look sloppy.
    function outBack(t) {
        const s = Theme.lowPower || Theme.reduced ? 0 : 0.6;
        return 1 + (s + 1) * Math.pow(t - 1, 3) + s * Math.pow(t - 1, 2);
    }
    function outCubic(t) {
        return 1 - Math.pow(1 - t, 3);
    }
    component Piece: Item {
        id: piece
        property int order: 0
        // Each piece rises 6 px in order while opening, about 30 ms apart; closing fades all at once.
        readonly property real shown: hub.opening ? hub.clamp((hub.progress - 0.45 - order * 0.07) / 0.35) : hub.clamp((hub.progress - 0.3) / 0.7)
        Layout.fillWidth: true
        opacity: shown
        transform: Translate { y: Theme.reduced ? 0 : (1 - hub.outCubic(piece.shown)) * 6 }
    }
    readonly property real grow: clamp((progress - 0.2) / 0.8)
    function focusCapture() {
        capture.forceActiveFocus();
    }
    Rectangle {
        id: shape
        visible: hub.progress > 0
        // Snapped to whole pixels so the edges stay sharp at fractional scales.
        width: Math.round(hub.settle(hub.pill.width, hub.openWidth, hub.outBack(hub.grow)))
        height: Math.round(hub.settle(hub.pill.height, hub.openHeight, hub.outCubic(hub.grow)))
        x: Math.round(hub.settle(hub.pill.x + hub.pill.width / 2, hub.width / 2, hub.outCubic(hub.grow)) - width / 2)
        y: Math.round(hub.settle(hub.pill.y, 0, hub.outCubic(hub.grow)))
        // The pill's radius grows into the panel radius, staying concentric with the bar's own corners.
        radius: hub.settle(Theme.radiusSmall, Theme.panelRadius, hub.grow)
        topLeftRadius: hub.edge ? hub.settle(radius, 0, hub.grow) : radius
        topRightRadius: topLeftRadius
        color: Theme.panel
        clip: true
        Keys.onEscapePressed: hub.dismissed()
        ColumnLayout {
            x: Theme.panelPadding
            y: Theme.panelPadding
            width: hub.openWidth - 2 * Theme.panelPadding
            spacing: Theme.gapL
            Piece {
                order: 0
                Layout.preferredHeight: Theme.heading + 4
                C.Label {
                    anchors.fill: parent
                    text: "Today"
                    font.pixelSize: Theme.heading
                }
            }
            Piece {
                order: 1
                Layout.preferredHeight: 28
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 10
                    radius: 5
                    color: Theme.surface
                }
            }
            Piece {
                order: 2
                Layout.preferredHeight: Theme.controlLarge
                C.Field {
                    id: capture
                    anchors.fill: parent
                    placeholderText: "Add a to-do"
                    Keys.onEscapePressed: hub.dismissed()
                }
            }
            Piece {
                order: 3
                Layout.preferredHeight: 260
                RowLayout {
                    anchors.fill: parent
                    spacing: Theme.gapL
                    Repeater {
                        model: 2
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Theme.controlRadius
                            color: Theme.surface
                        }
                    }
                }
            }
        }
    }
}
