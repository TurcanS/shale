import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

// The panel case. The page decides its size and header: title, headerCount (a round count beside the title, when
// above 0), headerChip ({text, on}: a status chip beside the title, accent when on), headerNote (a short status beside
// the title; a page with noteClicked() makes it a button), titleSize,
// panelWidth, panelHeight, showHeader, chromeless, canGoBack/back() and headerTools (a Component shown beside the
// close button).
Rectangle {
    id: root
    property string panel: "launcher"
    property bool active: true
    // True while the host itself brings the case in; the page then skips its own entrance.
    property bool entering: false
    // The host draws the case's fill and edge itself, so they can take the entrance's shape.
    property bool bare: false
    readonly property var pageItem: loader.item
    function page(name, fallback) {
        return pageItem && pageItem[name] !== undefined && pageItem[name] !== null ? pageItem[name] : fallback;
    }
    readonly property bool chromeless: page("chromeless", false)
    readonly property bool canGoBack: page("canGoBack", false)
    objectName: "panel-" + panel
    readonly property int preferredWidth: page("panelWidth", 580)
    readonly property int preferredHeight: page("panelHeight", 520)
    color: chromeless || bare ? "transparent" : Theme.caseColor
    radius: Theme.radiusCase
    // A hairline edge keeps the case apart from dark wallpapers.
    border.width: chromeless || bare ? 0 : 1
    border.color: Theme.hairline
    clip: true
    // Consume pointer presses inside the surface instead of dismissing its backdrop.
    MouseArea {
        anchors.fill: parent
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.chromeless ? 0 : Theme.casePadding
        spacing: 10
        // Title 17/650, a short status in textDim, then the page's tools and close.
        RowLayout {
            visible: !root.chromeless && root.page("showHeader", true)
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            spacing: 10
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
                font.pixelSize: root.page("titleSize", 17)
                font.weight: 650
                elide: Text.ElideNone
                Layout.leftMargin: root.canGoBack ? -2 : 2
                Layout.preferredHeight: 32
            }
            Rectangle {
                readonly property int count: root.page("headerCount", 0)
                visible: count > 0
                implicitWidth: Math.max(22, countLabel.implicitWidth + 12)
                implicitHeight: 20
                radius: 10
                color: Theme.key
                Layout.leftMargin: -2
                C.Label {
                    id: countLabel
                    anchors.centerIn: parent
                    text: parent.count
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.weight: 650
                    font.features: ({"tnum": 1})
                }
            }
            Rectangle {
                id: headerChip
                readonly property var chip: root.page("headerChip", null)
                visible: !!chip
                implicitWidth: chipRow.implicitWidth + 18
                implicitHeight: 24
                radius: 12
                color: chip && chip.on ? Theme.accentSoft : Theme.key
                Layout.leftMargin: -2
                Behavior on color {
                    ColorAnimation {
                        duration: Theme.fast
                    }
                }
                RowLayout {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 6
                    Rectangle {
                        implicitWidth: 6
                        implicitHeight: 6
                        radius: 3
                        color: chipText.color
                    }
                    C.Label {
                        id: chipText
                        text: headerChip.chip ? headerChip.chip.text : ""
                        color: headerChip.chip && headerChip.chip.on ? Theme.accentText : Theme.textMuted
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideNone
                    }
                }
            }
            C.Label {
                readonly property string note: root.page("headerNote", "")
                visible: note !== "" && typeof root.page("noteClicked", null) !== "function"
                text: note
                color: Theme.textDim
                font.pixelSize: 13
                Layout.fillWidth: true
                Layout.minimumWidth: 0
            }
            C.Button {
                id: noteButton
                visible: root.page("headerNote", "") !== "" && typeof root.page("noteClicked", null) === "function"
                text: root.page("headerNote", "")
                hint: root.page("noteHint", "")
                flat: true
                labelSize: 13
                foreground: hovered || visualFocus ? Theme.textSecondary : Theme.textDim
                implicitHeight: 28
                leftPadding: 6
                rightPadding: 6
                Layout.leftMargin: -6
                Layout.minimumWidth: 0
                onClicked: root.pageItem.noteClicked()
            }
            Item {
                visible: root.page("headerNote", "") === "" || noteButton.visible
                Layout.fillWidth: true
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
            // Switching pages in an open case: the new page rises and fades in like the case itself.
            transform: Translate {
                y: (1 - loader.entrance) * Theme.panelRise
            }
            NumberAnimation {
                id: pageEntrance
                target: loader
                property: "entrance"
                from: 0
                to: 1
                duration: Theme.panelEnter
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.easeOut
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
                    system: "System.qml",
                    airdrop: "AirDropPanel.qml"
                })[root.panel] || "Launcher.qml"
            onLoaded: {
                if (root.entering) {
                    pageEntrance.stop();
                    entrance = 1;
                } else {
                    pageEntrance.restart();
                }
                const loaded = item as Item;
                if (loaded)
                    loaded.forceActiveFocus();
            }
            visible: status !== Loader.Error
        }
        // A page that can't be loaded (a damaged install, a half-finished update) says so instead of an empty case.
        C.EmptyState {
            visible: loader.status === Loader.Error
            title: "This panel couldn't be opened"
            description: "Run `shale logs` to see why, or update Shale."
            glyph: "info"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignCenter
        }
    }
    Keys.onEscapePressed: {
        if (canGoBack)
            pageItem.back();
        else
            ShellState.close();
    }
}
