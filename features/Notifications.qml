import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../services"
import "../components" as C

// Newest first under "New" (the last hour), "Earlier today", "Yesterday" and "Earlier". Dismissing or clearing
// hides the cards at once and only lets go of the notifications when the undo bar goes, or the panel closes.
FocusScope {
    id: page
    readonly property string title: "Notifications"
    readonly property int headerCount: timeline.count
    readonly property int panelWidth: 420
    // Tall enough for the cards (and the empty state), up to 580; the host keeps it on screen.
    readonly property int panelHeight: Math.min(580, Math.ceil(Theme.casePadding * 2 + 32 + 10 + 48 + 10
                                                               + Math.max(list.count === 0 ? 220 : 0, list.contentHeight)))
    readonly property Component headerTools: timeline.count > 0 ? clearTool : null
    readonly property bool dnd: ShellState.setting("dnd", false)
    // Ids hidden here and waiting for the undo bar to go.
    property var pending: []
    property double now: Date.now()
    Component {
        id: clearTool
        C.Button {
            text: "Clear all"
            implicitHeight: 30
            labelSize: 12
            cornerRadius: 9
            onClicked: page.clearAll()
        }
    }
    function groupOf(timestamp) {
        const today = new Date(now);
        const startOfToday = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
        if (now - timestamp < 3600000)
            return "New";
        if (timestamp >= startOfToday)
            return "Earlier today";
        return timestamp >= startOfToday - 86400000 ? "Yesterday" : "Earlier";
    }
    // Transient notifications only pop up; they never enter history.
    function refresh() {
        const records = Services.notifications.filter(n => !n.transient && page.pending.indexOf(n.id) < 0)
            .sort((a, b) => (b.timestamp || 0) - (a.timestamp || 0));
        Services.reconcileNotifications(timeline, records);
        for (let i = 0; i < timeline.count; i++) {
            const group = groupOf(timeline.get(i).notificationData.timestamp || 0);
            if (timeline.get(i).group !== group)
                timeline.setProperty(i, "group", group);
        }
    }
    function commit() {
        const ids = pending;
        pending = [];
        for (const id of ids)
            Services.dismissNotification(id);
    }
    function hide(ids, message) {
        commit();
        if (!ids.length)
            return;
        pending = ids;
        refresh();
        undoBar.show(message);
    }
    function dismiss(id) {
        hide([id], "Notification dismissed");
    }
    function dismissApp(name) {
        const ids = Services.notifications.filter(n => n.appName === name && !n.transient).map(n => n.id);
        hide(ids, ids.length === 1 ? "Notification dismissed" : "Cleared " + ids.length + " from " + name);
    }
    function clearAll() {
        hide(Services.notifications.filter(n => !n.transient).map(n => n.id), "All notifications cleared");
    }
    function undo() {
        pending = [];
        refresh();
    }
    Component.onCompleted: refresh()
    Component.onDestruction: commit()
    Connections {
        target: Services
        function onNotificationsChanged() {
            page.refresh();
        }
    }
    // Moves cards from New to Earlier today as they age.
    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: {
            page.now = Date.now();
            page.refresh();
        }
    }
    ListModel {
        id: timeline
        dynamicRoles: true
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 10
        C.ListRow {
            id: dndRow
            text: "Do not disturb"
            subtitle: page.dnd ? "On · only urgent ones pop up" : Focus.active ? "Off · focus is holding new ones"
                : ShellState.quietNow ? "Off · quiet hours until " + String(ShellState.quietHours[1]).padStart(2, "0") + ":00" : "Off · urgent ones always pop up"
            glyph: "moon"
            selected: page.dnd
            checkmark: false
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            cornerRadius: 14
            Accessible.role: Accessible.CheckBox
            Accessible.checkable: true
            Accessible.checked: selected
            onClicked: ShellState.setSetting("dnd", !page.dnd)
            trailing: C.Switch {
                selected: page.dnd
                focusPolicy: Qt.NoFocus
                hint: "Do not disturb"
                onClicked: ShellState.setSetting("dnd", !page.dnd)
            }
        }
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: Theme.gapS
            model: timeline
            property int refocus: -1
            onCountChanged: if (refocus >= 0) {
                const index = Math.min(refocus, count - 1);
                refocus = -1;
                Qt.callLater(() => {
                    const card = list.itemAtIndex(index);
                    if (card)
                        card.forceActiveFocus(Qt.TabFocusReason);
                });
            }
            section.property: "group"
            section.criteria: ViewSection.FullString
            section.delegate: C.Label {
                required property string section
                width: list.width
                height: 22
                leftPadding: 4
                verticalAlignment: Text.AlignBottom
                text: section
                color: Theme.textDim
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            // Fade inside the delegate: a ListView add transition freezes later rows
            // at stale positions when a card's height settles ("Show more").
            delegate: NotificationCard {
                id: historyCard
                required property var notificationData
                required property int index
                width: list.width
                notification: notificationData
                dismissWith: id => page.dismiss(id)
                dismissAppWith: name => page.dismissApp(name)
                onActiveFocusChanged: if (activeFocus)
                    list.positionViewAtIndex(index, ListView.Contain)
                onRemoving: list.refocus = index
                property real rise: 1
                opacity: rise * feed.shown
                // Opening the panel, the cards are fed down one after another like paper, flattening as they land.
                transform: [
                    Translate {
                        y: (1 - historyCard.rise) * -6
                    },
                    C.Cascade {
                        id: feed
                        panel: "notifications"
                        order: historyCard.index
                        dy: -10
                        spacing: 2.2
                    },
                    Rotation {
                        origin.x: historyCard.width / 2
                        origin.y: 0
                        axis { x: 1; y: 0; z: 0 }
                        angle: feed.progress < 1 ? -34 * (1 - feed.progress) : 0
                    }
                ]
                NumberAnimation {
                    id: arrival
                    target: historyCard
                    property: "rise"
                    from: 0
                    to: 1
                    duration: Theme.panelEnter
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.easeOut
                }
                Component.onCompleted: if (Date.now() - (notificationData.timestamp || 0) < 2000)
                    arrival.start()
            }
            remove: Transition {
                NumberAnimation {
                    property: "opacity"
                    to: 0
                    duration: Theme.panelLeave
                }
            }
            displaced: Transition {
                NumberAnimation {
                    properties: "x,y"
                    duration: Theme.reduced ? 0 : Theme.enter
                    easing.type: Easing.OutCubic
                }
            }
            // Room under the last card for the undo bar.
            footer: Item {
                width: list.width
                height: undoBar.open ? undoBar.height + 14 : 0
            }
            ScrollBar.vertical: C.ScrollBar {}
            C.EmptyState {
                anchors.centerIn: parent
                width: parent.width - 20
                visible: list.count === 0
                title: "All caught up"
                glyph: page.dnd ? "bell-off" : "bell"
                description: page.dnd ? "Do not disturb is on" : ""
            }
        }
    }
    C.UndoBar {
        id: undoBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        onUndone: page.undo()
        onExpired: page.commit()
    }
}
