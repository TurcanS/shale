import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../core"
import "../services"

// Notification toasts: the Notifications card, stacked up from the bottom right corner, newest lowest.
PanelWindow {
    id: popups
    // Whether this window's screen is the one toasts show on now.
    property bool target: false
    // Transparent room around the cards for their shadow; the mask keeps it from taking clicks.
    readonly property int room: 32
    anchors {
        bottom: true
        right: true
    }
    implicitWidth: Math.min(360, screen.width - 48) + room + 24
    implicitHeight: Math.max(1, Math.min(screen.height - ShellState.barBottom - 96, popupList.contentHeight)) + room + 24
    property int retiring: 0
    readonly property bool wanted: popups.target && !ShellState.locked && (Services.popupModel.count > 0 || retiring > 0) && ShellState.panel !== "notifications"
    // Applied after the change settles: mapping the window as the session unlocks updates the focused
    // output (and so `target`) while `visible` is still being set, which Qt reports as a binding loop.
    visible: false
    onWantedChanged: Qt.callLater(() => popups.visible = popups.wanted)
    Component.onCompleted: visible = wanted
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shale-notifications"
    WlrLayershell.layer: WlrLayer.Overlay
    mask: Region {
        item: popupList
    }
    ListView {
        id: popupList
        x: popups.room
        y: popups.room
        width: parent.width - popups.room - 24
        height: parent.height - popups.room - 24
        spacing: 10
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        model: Services.popupModel
        delegate: Item {
            id: popupItem
            required property var notificationData
            width: popupList.width
            height: popupCard.implicitHeight
            // Swiped to the right, the card follows the pointer; let go past a third of the way it flies off and is
            // dismissed, short of that it springs back into its slot.
            property real swipeX: 0
            opacity: 1 - Math.min(1, swipeX / width) * 0.6
            transform: Translate {
                x: popupItem.swipeX
            }
            DragHandler {
                id: swipe
                target: null
                yAxis.enabled: false
                grabPermissions: PointerHandler.CanTakeOverFromAnything
                onTranslationChanged: if (active) popupItem.swipeX = Math.max(0, translation.x)
                onActiveChanged: {
                    if (active)
                        return;
                    if (popupItem.swipeX > popupItem.width / 3)
                        flingAway.start();
                    else
                        springBack.start();
                }
            }
            NumberAnimation {
                id: springBack
                target: popupItem
                property: "swipeX"
                to: 0
                duration: Motion.ms(260)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.seatCurve(Motion.ov(0.6))
            }
            SequentialAnimation {
                id: flingAway
                NumberAnimation { target: popupItem; property: "swipeX"; to: popupItem.width + 40; duration: Motion.ms(160); easing.type: Easing.InQuad }
                ScriptAction { script: popupCard.dismiss(false) }
            }
            ListView.onRemove: {
                popups.retiring++;
                removal.start();
            }
            SequentialAnimation {
                id: removal
                PropertyAction { target: popupItem; property: "ListView.delayRemove"; value: true }
                // Lively and Playful: it slides back out to the right as it goes.
                ParallelAnimation {
                    NumberAnimation { target: popupItem; property: "opacity"; to: 0; duration: Theme.leave }
                    NumberAnimation { target: popupItem; property: "swipeX"; to: Motion.calm ? popupItem.swipeX : popupItem.swipeX + 48 * Motion.travel; duration: Theme.leave; easing.type: Easing.InQuad }
                }
                ScriptAction { script: popups.retiring-- }
                PropertyAction { target: popupItem; property: "ListView.delayRemove"; value: false }
            }
            RectangularShadow {
                anchors.fill: popupCard
                visible: !Theme.lowPower
                radius: popupCard.radius
                blur: 32
                offset.y: 14
                color: Qt.rgba(0, 0, 0, 0.45)
            }
            NotificationCard {
                id: popupCard
                notification: popupItem.notificationData
                popup: true
                width: parent.width
                height: implicitHeight
            }
        }
        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.panelEnter }
                // Pushed in from the screen's edge into its slot, where it seats (a short slide under Calm).
                NumberAnimation {
                    property: "x"
                    from: Theme.reduced ? 0 : Motion.calm ? 24 : 90 * Motion.travel
                    to: 0
                    duration: Theme.reduced ? 0 : Motion.calm ? (Theme.lowPower ? 120 : 200) : Motion.ms(380)
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.calm ? Theme.easeOut : Motion.seatCurve(Motion.ov(0.8))
                }
            }
        }
        displaced: Transition {
            // The stack closes up, each card seating in its new slot.
            NumberAnimation {
                property: "y"
                duration: Theme.reduced ? 0 : Motion.calm ? Theme.enter : Motion.ms(300)
                easing.type: Motion.calm ? Easing.OutCubic : Easing.BezierSpline
                easing.bezierCurve: Motion.seatCurve(Motion.ov(0.6))
            }
        }
    }
}
