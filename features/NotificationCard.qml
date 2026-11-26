import QtQuick
import QtQuick.Layouts
import Quickshell
import "../core"
import "../services"
import "../components" as C

// One notification: app icon tile (accent when urgent), "App · time", dismiss, title, body, picture and action
// buttons. The same card is the toast (popup: a little larger, with Later) and the row in Notifications.
Rectangle {
    id: root
    required property var notification
    property bool popup: false
    property bool expanded: false
    property double now: Date.now()
    readonly property bool clickable: Services.defaultActionIndex(notification) >= 0 || popup
    readonly property bool urgent: notification.urgency === 2
    // How the card goes away: Notifications defers it behind its undo bar; a toast dismisses at once.
    property var dismissWith: id => Services.dismissNotification(id)
    property var dismissAppWith: name => Services.dismissApplication(name)
    onNotificationChanged: expanded = false
    // Delete dismissed this card from the keyboard; the list can hand focus to the next one.
    signal removing()
    // Enter or Space does what a click does, Delete dismisses, Shift+Delete dismisses everything from the app.
    function activate() {
        if (!Services.invokeDefault(notification.id) && popup)
            Services.hidePopup(notification.id);
    }
    function dismiss(everything) {
        if (everything)
            dismissAppWith(notification.appName);
        else
            dismissWith(notification.id);
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
            dismiss(event.modifiers & Qt.ShiftModifier);
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
    // An icon name, a file path or a URL, as senders give it.
    function iconSource(icon) {
        if (!icon)
            return "";
        if (icon.startsWith("/"))
            return "file://" + icon;
        if (/^[a-z]+:/.test(icon))
            return icon;
        return Quickshell.iconPath(icon, true);
    }
    Timer {
        interval: 30000
        repeat: true
        running: root.visible
        onTriggered: root.now = Date.now()
    }
    onVisibleChanged: if (visible)
        now = Date.now()
    readonly property int padding: popup ? 14 : 12
    width: 360
    implicitHeight: Math.max(content.implicitHeight, thumbnail.visible ? thumbnail.y - content.y + thumbnail.height : 0) + 2 * padding
    color: cardArea.containsMouse && root.clickable ? Theme.mix(Theme.module, Theme.text, 0.04) : Theme.module
    Behavior on color {
        ColorAnimation {
            duration: Theme.fast
        }
    }
    radius: popup ? 18 : 14
    border.width: urgent || popup ? 1 : 0
    border.color: urgent ? Theme.accentLine : Theme.cardEdge
    // Sits beneath the content so buttons keep their own clicks.
    MouseArea {
        id: cardArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton)
                root.dismiss(false);
            else
                root.activate();
        }
    }
    HoverHandler {
        onHoveredChanged: if (root.popup)
            Services.pausePopup(root.notification.id, hovered)
    }
    // Only Tab gives a card focus (its MouseArea never does), so this is a keyboard-only ring.
    Rectangle {
        anchors.fill: parent
        z: 10
        visible: root.activeFocus
        color: "transparent"
        radius: root.radius
        border.width: 2
        border.color: Theme.text
        opacity: 0.85
    }
    // Avatars and icons sent as the image sit beside the text, at no more than their own size. Kept out of the
    // layout: the labels only reserve its width.
    Image {
        id: thumbnail
        visible: picture.small
        source: visible ? picture.source : ""
        sourceSize: picture.sourceSize
        x: content.x + body.x + body.width - width
        y: content.y + body.y + (summary.visible ? summary.y : notificationBody.y)
        width: Math.min(56, picture.nativeSize.width)
        height: Math.min(56, picture.nativeSize.height)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }
    RowLayout {
        id: content
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.padding
        }
        spacing: Theme.gapM
        Rectangle {
            readonly property int size: root.popup ? 36 : 34
            Layout.preferredWidth: size
            Layout.preferredHeight: size
            Layout.alignment: Qt.AlignTop
            radius: Theme.radiusKey
            color: root.urgent ? Theme.accent : Theme.key
            Image {
                id: appIcon
                anchors.centerIn: parent
                visible: status === Image.Ready
                source: root.iconSource(root.notification.appIcon || "")
                sourceSize.width: 20
                sourceSize.height: 20
                width: 20
                height: 20
            }
            C.Icon {
                anchors.centerIn: parent
                visible: !appIcon.visible
                name: "bell"
                color: root.urgent ? Theme.accentInk : Theme.textSecondary
            }
        }
        ColumnLayout {
            id: body
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 2
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                spacing: 6
                // A long app name elides first; the time and the close key keep their size. (Not a maximum width from
                // the column's own width: that fed back into the column, a recursive rearrange.)
                C.Label {
                    text: root.notification.appName || "Notification"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    Layout.minimumWidth: 0
                }
                C.Label {
                    text: "· " + root.when(root.notification.timestamp)
                    color: Theme.textDim
                    font.pixelSize: 12
                    elide: Text.ElideNone
                    Layout.minimumWidth: implicitWidth
                }
                Item {
                    Layout.fillWidth: true
                }
                C.Button {
                    glyph: "close"
                    flat: true
                    implicitWidth: 24
                    implicitHeight: 24
                    Layout.minimumWidth: 24
                    padding: 4
                    cornerRadius: 7
                    foreground: hovered || visualFocus ? Theme.text : Theme.textDim
                    hint: "Dismiss " + (root.notification.appName || "notification") + " · Shift-click for all from it"
                    // Keys reach onClicked; the pointer goes through the area below, which sees Shift.
                    onClicked: root.dismiss(false)
                    MouseArea {
                        anchors.fill: parent
                        onClicked: mouse => root.dismiss(mouse.modifiers & Qt.ShiftModifier)
                    }
                }
            }
            C.Label {
                id: summary
                visible: !!root.notification.summary
                text: root.notification.summary
                font.pixelSize: 14
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.rightMargin: thumbnail.visible ? thumbnail.width + 12 : 0
                maximumLineCount: root.expanded ? 1000 : 3
            }
            C.Label {
                id: notificationBody
                visible: !!root.notification.body
                text: root.notification.body
                color: Theme.textMuted
                font.pixelSize: 13
                lineHeight: 1.1
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                Layout.rightMargin: thumbnail.visible ? thumbnail.width + 12 : 0
                maximumLineCount: root.expanded ? 1000 : root.popup ? 4 : 5
            }
            C.Button {
                visible: !root.popup && (notificationBody.truncated || summary.truncated || root.expanded)
                text: root.expanded ? "Show less" : "Show more"
                flat: true
                labelSize: 12
                implicitHeight: 26
                leftPadding: 6
                rightPadding: 6
                Layout.leftMargin: -6
                Layout.alignment: Qt.AlignLeft
                onClicked: root.expanded = !root.expanded
            }
            // Shown at its own size or smaller, never stretched. Images arrive three ways:
            // - image-data: Quickshell's provider always hands over the native image.
            // - image-path: Quickshell's icon provider draws the file at the size asked for (100×100 when none is, the
            //   old blur), but never larger than the file, so asking for 700×700 gives the file's own size up to that.
            // - file: URLs: a sourceSize would scale a small image up, so these load natively first and only images
            //   wider than 700 px load again smaller.
            Image {
                id: picture
                property size nativeSize: Qt.size(0, 0)
                // image://icon//abs/path.png for an image-path that is a file, image://icon/name for an icon name.
                readonly property string kind: !source.toString().startsWith("image://icon/") ? "image"
                    : source.toString().startsWith("image://icon//") || source.toString().indexOf("?path=") >= 0 ? "path" : "icon"
                readonly property bool ready: !!root.notification.image && status === Image.Ready && nativeSize.width > 0
                readonly property bool small: ready && (kind === "icon" || Math.max(nativeSize.width, nativeSize.height) <= 128)
                visible: ready && !small
                source: root.notification.image || ""
                function measure() {
                    if (status === Image.Ready && nativeSize.width === 0)
                        nativeSize = Qt.size(implicitWidth, implicitHeight);
                }
                // A cached image stays Ready from one source to the next without a statusChanged, so measure once the
                // new source has settled as well.
                onSourceChanged: {
                    nativeSize = Qt.size(0, 0);
                    Qt.callLater(measure);
                }
                onStatusChanged: measure()
                sourceSize: kind === "path" ? Qt.size(700, 700) : kind === "icon" ? Qt.size(112, 112)
                    : nativeSize.width > 700 ? Qt.size(700, Math.round(700 * nativeSize.height / nativeSize.width)) : undefined
                Layout.fillWidth: true
                Layout.topMargin: visible ? 6 : 0
                // Wide images get no taller than they draw at a card's usual text width. Not this item's own width: that
                // shifts with the list's scroll bar, and the height would feed back into it (a polish loop).
                Layout.preferredHeight: visible ? Math.min(160, implicitHeight, 300 * implicitHeight / Math.max(1, implicitWidth)) : 0
                fillMode: Image.PreserveAspectFit
                horizontalAlignment: Image.AlignLeft
                asynchronous: true
                smooth: true
                mipmap: true
            }
            Flow {
                // The default action belongs to the card itself, not a button. A toast adds Later, which leaves it
                // in Notifications.
                readonly property var buttons: (root.notification.actions || []).map((action, index) => ({action: action, index: index})).filter(item => item.action && item.action.identifier !== "default")
                visible: buttons.length > 0 || root.popup
                Layout.fillWidth: true
                Layout.topMargin: root.popup ? 8 : 6
                spacing: 6
                Repeater {
                    model: parent.buttons
                    C.Button {
                        required property var modelData
                        required property int index
                        text: modelData.action.text || "Open"
                        // The first action leads; it takes the accent when the notification is urgent.
                        accent: index === 0 && root.urgent
                        width: Math.min(implicitWidth, parent.width)
                        implicitHeight: root.popup ? 30 : 28
                        leftPadding: root.popup ? 14 : 12
                        rightPadding: root.popup ? 14 : 12
                        cornerRadius: 8
                        labelSize: 12
                        onClicked: Services.invokeNotification(root.notification.id, modelData.index)
                    }
                }
                C.Button {
                    visible: root.popup
                    text: "Later"
                    hint: "Later · keep it in Notifications"
                    implicitHeight: 30
                    leftPadding: 14
                    rightPadding: 14
                    cornerRadius: 8
                    labelSize: 12
                    onClicked: Services.hidePopup(root.notification.id)
                }
            }
        }
    }
}
