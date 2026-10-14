import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

// The panel surface. The page decides its size and header: title, panelWidth, panelHeight, showHeader,
// chromeless, canGoBack/back() and headerTools (a Component shown beside the close button).
Rectangle {
    id: root
    property string panel: "launcher"
    property bool active: true
    readonly property var pageItem: loader.item
    function page(name, fallback) {
        return pageItem && pageItem[name] !== undefined && pageItem[name] !== null ? pageItem[name] : fallback;
    }
    readonly property bool chromeless: page("chromeless", false)
    readonly property bool canGoBack: page("canGoBack", false)
    objectName: "panel-" + panel
    readonly property int preferredWidth: page("panelWidth", 580)
    readonly property int preferredHeight: page("panelHeight", 520)
    color: chromeless ? "transparent" : Theme.panel
    radius: Theme.panelRadius
    // A hairline edge keeps the panel apart from dark wallpapers.
    border.width: chromeless ? 0 : 1
    border.color: Theme.border
    clip: true
    // Consume pointer presses inside the surface instead of dismissing its backdrop.
    MouseArea {
        anchors.fill: parent
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.chromeless ? 0 : Theme.panelPadding
        spacing: Theme.sectionSpacing
        RowLayout {
            visible: !root.chromeless && root.page("showHeader", true)
            Layout.fillWidth: true
            spacing: Theme.gapS
            C.Button {
                visible: root.canGoBack
                glyph: "back"
                flat: true
                hint: "Back"
                implicitWidth: 32
                implicitHeight: 32
                onClicked: root.pageItem.back()
            }
            C.Label {
                text: root.page("title", "Shale")
                font.pixelSize: Theme.titleSize
                font.weight: Font.DemiBold
                Layout.fillWidth: true
                Layout.leftMargin: root.canGoBack ? 0 : 2
                Layout.preferredHeight: 32
            }
            Loader {
                sourceComponent: root.page("headerTools", null)
                visible: !!item
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
                    activity: "Activity.qml",
                    system: "System.qml"
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
        if (canGoBack)
            pageItem.back();
        else
            ShellState.close();
    }
}
