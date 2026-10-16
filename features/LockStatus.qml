import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "../components" as C

// Status pill: waiting notifications and battery. Only counts are shown; contents stay private.
Rectangle {
    id: root
    visible: Services.batteryAvailable || Services.notificationModel.count > 0
    implicitWidth: statusRow.implicitWidth + 28
    implicitHeight: 36
    radius: height / 2
    color: Qt.rgba(Theme.panel.r, Theme.panel.g, Theme.panel.b, 0.62)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)
    RowLayout {
        id: statusRow
        anchors.centerIn: parent
        spacing: Theme.gapM
        RowLayout {
            visible: Services.notificationModel.count > 0
            spacing: Theme.gapS
            C.Icon {
                name: "bell"
                size: 15
            }
            C.Label {
                text: Services.notificationModel.count > 99 ? "99+" : String(Services.notificationModel.count)
                font.pixelSize: Theme.small
                font.weight: Font.Medium
                font.features: {"tnum": 1}
                elide: Text.ElideNone
                Accessible.name: Services.notificationModel.count + " notifications waiting"
            }
        }
        RowLayout {
            visible: Services.batteryAvailable
            spacing: Theme.gapS
            C.Icon {
                name: Services.batteryCharging ? "bolt" : "battery"
                size: 15
            }
            C.Label {
                text: Math.round(Services.batteryPercent) + "%"
                font.pixelSize: Theme.small
                font.weight: Font.Medium
                font.features: {"tnum": 1}
                elide: Text.ElideNone
                color: !Services.batteryCharging && Services.batteryPercent <= 15 ? Theme.danger : Theme.text
            }
        }
    }
}
