pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../core"
import "../core/station.js" as Station
import "../services"
import "../components" as C

FocusScope {
    readonly property string title: ShellState.word("signalLog")
    readonly property int panelWidth: 420
    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.gapM
        C.Toggle {
            text: ShellState.word("quiet") === "QUIET" ? "Quiet" : "Do not disturb"
            selected: ShellState.setting("dnd", false)
            Layout.fillWidth: true
            onClicked: ShellState.setSetting("dnd", !ShellState.setting("dnd", false))
        }
        // Today's signals as ticks on the 24-hour scale, tall when urgent; a tick takes the list to its signal.
        Item {
            id: drum
            visible: ShellState.setting("stationWords", true) && ticks.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 26 : 0
            readonly property double dayStart: new Date(new Date().setHours(0, 0, 0, 0)).getTime()
            readonly property var ticks: {
                list.count;
                return Station.ticks(Services.notifications.map(n => ({id: n.id, at: n.timestamp, urgent: n.urgency === 2})), dayStart, dayStart + 86400000, width);
            }
            Accessible.role: Accessible.Graphic
            Accessible.name: ticks.length + " notifications today"
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Theme.border
            }
            Repeater {
                model: drum.ticks
                Rectangle {
                    id: tick
                    required property var modelData
                    x: modelData.x - 1
                    width: 2
                    height: modelData.urgent ? 20 : 11
                    anchors.bottom: parent.bottom
                    color: modelData.urgent ? Theme.accent2 : Theme.accent
                    opacity: tickArea.containsMouse ? 1 : 0.7
                    MouseArea {
                        id: tickArea
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        onClicked: {
                            for (let i = 0; i < Services.notificationModel.count; i++) {
                                if (Services.notificationModel.get(i).id === tick.modelData.id) {
                                    list.positionViewAtIndex(i, ListView.Beginning);
                                    return;
                                }
                            }
                        }
                    }
                }
            }
        }
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: Theme.gapS
            model: Services.notificationModel
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
            section.property: "appName"
            section.criteria: ViewSection.FullString
            section.delegate: RowLayout {
                id: sectionRow
                required property string section
                readonly property var latest: Services.notifications.find(n => n.appName === section)
                width: list.width
                height: 38
                spacing: Theme.gapS
                Image {
                    id: sectionIcon
                    visible: status === Image.Ready
                    source: sectionRow.latest && sectionRow.latest.appIcon ? Quickshell.iconPath(sectionRow.latest.appIcon, true) : ""
                    sourceSize.width: 16
                    sourceSize.height: 16
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16
                    Layout.leftMargin: 2
                }
                C.Icon {
                    visible: !sectionIcon.visible
                    name: "bell"
                    color: Theme.muted
                    Layout.leftMargin: 2
                }
                C.SectionHeader {
                    text: sectionRow.section || "Notification"
                    C.Button {
                        text: "Clear"
                        flat: true
                        implicitHeight: Theme.controlSmall
                        Accessible.name: "Clear notifications from " + (sectionRow.section || "this app")
                        onClicked: Services.dismissApplication(sectionRow.section)
                    }
                }
            }
            // Fade inside the delegate: a ListView add transition freezes later rows
            // at stale positions when a card's height settles ("Show more").
            delegate: NotificationCard {
                id: historyCard
                required property var notificationData
                required property int index
                width: list.width
                notification: notificationData
                onActiveFocusChanged: if (activeFocus) list.positionViewAtIndex(index, ListView.Contain)
                onRemoving: list.refocus = index
                NumberAnimation {
                    id: arrival
                    target: historyCard
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: Theme.enter
                }
                Component.onCompleted: if (Date.now() - (notificationData.timestamp || 0) < 2000) arrival.start()
            }
            remove: Transition {
                NumberAnimation {
                    property: "opacity"
                    to: 0
                    duration: Theme.leave
                }
            }
            displaced: Transition {
                NumberAnimation {
                    properties: "x,y"
                    duration: Theme.reduced ? 0 : Theme.enter
                    easing.type: Easing.OutCubic
                }
            }
            ScrollBar.vertical: C.ScrollBar {}
            C.EmptyState {
                anchors.centerIn: parent
                width: parent.width - 20
                visible: list.count === 0
                title: "All caught up"
                glyph: ShellState.setting("dnd", false) ? "bell-off" : "bell"
                description: ShellState.setting("dnd", false) ? "Do not disturb is on" : ""
            }
        }
        RowLayout {
            visible: list.count > 0
            Layout.fillWidth: true
            spacing: Theme.gapS
            C.Label {
                text: list.count + (list.count === 1 ? " notification" : " notifications")
                color: Theme.muted
                font.pixelSize: Theme.small
                Layout.fillWidth: true
            }
            C.Button {
                text: "Clear all"
                flat: true
                onClicked: Services.dismissAllNotifications()
            }
        }
    }
}
