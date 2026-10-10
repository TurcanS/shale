import QtQuick
import QtQuick.Layouts
import Quickshell
import "../core"
import "../services"
import "../components" as C

Rectangle {
    id: root
    required property var notification
    property bool popup: false
    // In grouped history the section header already names the app.
    readonly property bool grouped: !popup
    property bool expanded: false
    property double now: Date.now()
    readonly property bool clickable: Services.defaultActionIndex(notification) >= 0 || popup
    onNotificationChanged: expanded = false
    // Delete dismissed this card from the keyboard; the list can hand focus to the next one.
    signal removing()
    // Enter or Space does what a click does, Delete dismisses.
    function activate() {
        if (!Services.invokeDefault(notification.id) && popup)
            Services.hidePopup(notification.id);
    }
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: (notification.appName || "Notification") + ": " + (notification.summary || "")
    Accessible.description: notification.body || ""
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            activate();
            event.accepted = true;
        } else if (event.key === Qt.Key_Delete) {
            removing();
            Services.dismissNotification(notification.id);
            event.accepted = true;
        }
    }
    function when(timestamp) {
        const then = new Date(timestamp);
        const seconds = (now - timestamp) / 1000;
        const time = Qt.formatDateTime(then, ShellState.timeFormat);
        if (seconds < 60)
            return "now";
        if (seconds < 3600)
            return Math.floor(seconds / 60) + " min";
        const today = new Date(now);
        const startOfToday = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
        if (timestamp >= startOfToday)
            return time;
        if (timestamp >= startOfToday - 86400000)
            return "Yesterday " + time;
        if (timestamp >= startOfToday - 6 * 86400000)
            return Qt.formatDateTime(then, "ddd ") + time;
        return Qt.formatDateTime(then, "d MMM");
    }
    Timer {
        interval: 30000
        repeat: true
        running: root.visible
        onTriggered: root.now = Date.now()
    }
    onVisibleChanged: if (visible) now = Date.now()
    width: 380
    implicitHeight: body.implicitHeight + 28
    color: (cardArea.containsMouse || activeFocus) && root.clickable ? (root.popup ? Theme.hover : Theme.raised) : root.popup ? Theme.raised : Theme.surface
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    radius: Theme.controlRadius
    // Only Tab gives a card focus (its MouseArea never does), so this is a keyboard-only ring.
    border.width: activeFocus ? 1.5 : 0
    border.color: Theme.accent
    // Sits beneath the content so buttons keep their own clicks.
    MouseArea {
        id: cardArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton)
                Services.dismissNotification(root.notification.id);
            else
                root.activate();
        }
    }
    Rectangle {
        x: 0
        y: 18
        width: 3
        height: 20
        radius: 1.5
        color: Theme.danger
        visible: root.notification.urgency === 2
    }
    HoverHandler {
        onHoveredChanged: if (root.popup) Services.pausePopup(root.notification.id, hovered)
    }
    ColumnLayout {
        id: body
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 14
        }
        spacing: 8
        RowLayout {
            Image {
                id: appIcon
                visible: !root.grouped && !!root.notification.appIcon && status === Image.Ready
                source: root.notification.appIcon ? Quickshell.iconPath(root.notification.appIcon, "dialog-information") : ""
                sourceSize.width: 18
                sourceSize.height: 18
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
            }
            C.Icon {
                visible: !root.grouped && !appIcon.visible
                name: "bell"
                size: 18
                opacity: 0.55
            }
            C.Label {
                id: headerTitle
                text: root.grouped ? root.notification.summary : (root.notification.appName || "Notification")
                color: root.grouped ? Theme.text : Theme.muted
                font.pixelSize: root.grouped ? Theme.body : Theme.small
                font.weight: root.grouped ? Font.DemiBold : Font.Medium
                wrapMode: root.grouped ? Text.WordWrap : Text.NoWrap
                maximumLineCount: root.grouped ? (root.expanded ? 1000 : 3) : 1
                Layout.fillWidth: true
                Layout.alignment: root.grouped ? Qt.AlignTop : Qt.AlignVCenter
            }
            C.Label {
                text: root.when(root.notification.timestamp)
                color: Theme.disabled
                font.pixelSize: Theme.caption
                Layout.alignment: root.grouped ? Qt.AlignTop : Qt.AlignVCenter
                Layout.topMargin: root.grouped ? 2 : 0
            }
            C.Button {
                glyph: "close"
                flat: true
                Layout.alignment: root.grouped ? Qt.AlignTop : Qt.AlignVCenter
                Layout.topMargin: root.grouped ? -5 : 0
                implicitHeight: 28
                implicitWidth: 28
                hint: "Dismiss " + (root.notification.appName || "notification")
                onClicked: Services.dismissNotification(root.notification.id)
            }
        }
        C.Label {
            visible: !root.grouped
            text: root.notification.summary
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            maximumLineCount: root.expanded ? 1000 : 3
        }
        C.Label {
            id: notificationBody
            visible: !!root.notification.body
            text: root.notification.body
            color: Theme.muted
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            maximumLineCount: root.expanded ? 1000 : root.popup ? 4 : 5
        }
        C.Button {
            visible: !root.popup && (notificationBody.truncated || headerTitle.truncated || root.expanded)
            text: root.expanded ? "Show less" : "Show more"
            flat: true
            implicitHeight: 30
            Layout.alignment: Qt.AlignLeft
            onClicked: root.expanded = !root.expanded
        }
        Image {
            visible: !!root.notification.image && status === Image.Ready
            source: root.notification.image || ""
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 110 : 0
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            sourceSize.width: 700
        }
        Flow {
            // The default action belongs to the card itself, not a button.
            readonly property var buttons: (root.notification.actions || []).map((action, index) => ({action: action, index: index})).filter(item => item.action && item.action.identifier !== "default")
            visible: buttons.length > 0
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: parent.buttons
                C.Button {
                    required property var modelData
                    text: modelData.action.text || "Open"
                    width: Math.min(implicitWidth, parent.width)
                    implicitHeight: 32
                    onClicked: Services.invokeNotification(root.notification.id, modelData.index)
                }
            }
        }
    }
}
