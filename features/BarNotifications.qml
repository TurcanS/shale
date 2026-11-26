import QtQuick
import "../core"
import "../services"
import "../components" as C

BarKey {
    id: bell
    // The bar this item is on: its screen, layout, weather and helpers.
    required property var bar
    readonly property int count: Services.notifications.length
    readonly property bool dnd: ShellState.setting("dnd", false) || ShellState.quietNow
    implicitWidth: 32
    // Do not disturb swaps the bell so suppressed popups are never a surprise.
    glyph: dnd ? "bell-off" : "bell"
    selected: ShellState.panel === "notifications" && ShellState.screenName === bar.outputName
    hint: "Notifications"
    tooltip: bar.tooltip
    Accessible.name: "Notifications" + (dnd ? ", do not disturb" : "") + (count ? ", " + count + " waiting" : "")
    onClicked: ShellState.toggle("notifications", bar.outputName)
    // A new notification: the badge pops and warms up. Do not disturb coming on: the bell rocks once on its hook.
    property int seen: count
    onCountChanged: {
        if (count > seen && !Motion.calm)
            pop.restart();
        seen = count;
    }
    onDndChanged: if (dnd && !Motion.calm) rock.restart()
    SequentialAnimation {
        id: rock
        PropertyAction { target: bell.contentItem; property: "transformOrigin"; value: Item.Top }
        NumberAnimation { target: bell.contentItem; property: "rotation"; to: -16 * Motion.travel; duration: Motion.ms(80); easing.type: Easing.OutQuad }
        NumberAnimation { target: bell.contentItem; property: "rotation"; to: 11 * Motion.travel; duration: Motion.ms(120); easing.type: Easing.InOutQuad }
        NumberAnimation { target: bell.contentItem; property: "rotation"; to: -6 * Motion.travel; duration: Motion.ms(110); easing.type: Easing.InOutQuad }
        NumberAnimation { target: bell.contentItem; property: "rotation"; to: 0; duration: Motion.ms(140); easing.type: Easing.OutQuad }
    }
    property real badgePop: 1
    SequentialAnimation {
        id: pop
        ScriptAction { script: badgeLamp.flash() }
        NumberAnimation { target: bell; property: "badgePop"; from: 1.45; to: 1; duration: Motion.ms(320); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.seatCurve(Motion.ov(1.5)) }
    }
    Rectangle {
        visible: bell.count > 0
        z: 2
        x: parent.width - width - 4
        y: 1
        width: Math.max(14, badge.implicitWidth + 6)
        height: 14
        radius: 7
        color: Theme.accent
        scale: bell.badgePop
        C.WarmUp {
            id: badgeLamp
            anchors.fill: parent
            radius: parent.radius
            peak: 0.5
        }
        C.Label {
            id: badge
            anchors.centerIn: parent
            text: bell.count > 99 ? "99+" : String(bell.count)
            color: Theme.accentInk
            font.pixelSize: 10
            font.weight: Font.Bold
            font.features: ({"tnum": 1})
            elide: Text.ElideNone
        }
    }
}
