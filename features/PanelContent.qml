import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

Rectangle {
    id: root
    property string panel: "launcher"
    property bool active: true
    readonly property var pageItem: loader.item
    objectName: "panel-" + panel
    readonly property int preferredWidth: panel === "wallpaper" ? 1180 : panel === "settings" ? 820 : panel === "activity" ? 720 : panel === "overview" ? 980 : ["control", "notifications"].indexOf(panel) >= 0 ? 420 : panel === "calendar" ? 360 : panel === "power" ? 440 : 580
    readonly property int preferredHeight: panel === "wallpaper" ? 570 : panel === "activity" ? 620 : panel === "launcher" && pageItem && pageItem.calculatorQuery && pageItem.results.length === 0 ? (pageItem.calculationError ? 310 : 250) : panel === "calendar" ? 460 + (pageItem && pageItem.extraHeight ? pageItem.extraHeight : 0) : panel === "power" ? (Theme.body >= 18 ? 470 : 440) : panel === "capture" ? 540 : panel === "settings" ? 600 : panel === "overview" ? 640 : panel === "control" && pageItem && pageItem.preferredContentHeight > 0 ? Math.max(200, Math.min(570, pageItem.preferredContentHeight + 88)) : panel === "control" ? 570 : 520
    color: panel === "wallpaper" ? "transparent" : Theme.panel
    radius: Theme.panelRadius
    border.width: 0
    clip: true
    // Consume pointer presses inside the surface instead of dismissing its backdrop.
    MouseArea {
        anchors.fill: parent
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.panel === "wallpaper" ? 0 : Theme.panelPadding
        spacing: Theme.sectionSpacing
        RowLayout {
            visible: root.panel !== "wallpaper"
            Layout.fillWidth: true
            spacing: 10
            Rectangle {
                visible: root.panel !== "control" || ShellState.detail === ""
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 8
                color: Theme.surface
                C.Icon {
                    anchors.centerIn: parent
                    size: 16
                    name: ({launcher: "grid", clipboard: "clipboard", control: "settings", notifications: "bell", calendar: "calendar", overview: "window", capture: "camera", settings: "settings", power: "power", activity: "activity"})[root.panel] || "grid"
                }
            }
            C.Button {
                visible: root.panel === "control" && ShellState.detail !== ""
                glyph: "back"
                flat: true
                hint: "Back to controls"
                implicitWidth: 32
                implicitHeight: 32
                onClicked: ShellState.detail = ""
            }
            C.Label {
                text: root.panel === "control" && ShellState.detail !== "" ? ({wifi: "Wi-Fi", bluetooth: "Bluetooth", audio: "Sound", power: "Battery & power", media: "Now playing", tray: "System tray"})[ShellState.detail] || "Control center" : ({
                        launcher: "Applications",
                        clipboard: "Clipboard",
                        control: "Control center",
                        notifications: "Notifications",
                        calendar: "Calendar",
                        overview: "Workspaces",
                        capture: "Capture",
                        settings: "Settings",
                        power: "Session",
                        activity: "Activity"
                    })[root.panel] || "Shale"
                font.pixelSize: Theme.titleSize
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }
            C.Button {
                visible: root.panel === "control" && ["wifi", "power"].indexOf(ShellState.detail) >= 0
                glyph: "refresh"
                flat: true
                hint: "Refresh"
                implicitWidth: 32
                implicitHeight: 32
                enabled: !!root.pageItem && !root.pageItem.busy
                onClicked: if (root.pageItem) root.pageItem.refresh()
            }
            C.Button {
                glyph: "close"
                implicitWidth: 32
                implicitHeight: 32
                flat: true
                hint: "Close · Escape"
                onClicked: ShellState.close()
            }
        }
        Loader {
            id: loader
            property real entrance: 1
            opacity: entrance
            transform: Translate {
                y: Theme.reduced ? 0 : (1 - loader.entrance) * 6
            }
            NumberAnimation {
                id: pageEntrance
                target: loader
                property: "entrance"
                from: 0
                to: 1
                duration: Theme.fast
                easing.type: Easing.OutCubic
            }
            Layout.fillWidth: true
            Layout.fillHeight: true
            active: root.active
            source: ({
                    launcher: "Launcher.qml",
                    clipboard: "Clipboard.qml",
                    control: "ControlCenter.qml",
                    notifications: "Notifications.qml",
                    calendar: "Calendar.qml",
                    overview: "Overview.qml",
                    capture: "Capture.qml",
                    settings: "Settings.qml",
                    power: "Power.qml",
                    wallpaper: "Wallpaper.qml",
                    activity: "Activity.qml"
                })[root.panel] || "Launcher.qml"
            onLoaded: {
                pageEntrance.restart();
                const loaded = item as Item;
                if (loaded)
                    loaded.forceActiveFocus();
            }
        }
    }
    Keys.onEscapePressed: {
        if (panel === "control" && ShellState.detail !== "")
            ShellState.detail = "";
        else
            ShellState.close();
    }
}
