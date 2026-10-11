import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../core"
import "../core/paths.js" as Paths
import "../components" as C

FocusScope {
    id: root
    property string category: "Appearance"
    readonly property bool compactNavigation: width < 620
    property var stats: ({})
    property bool statsBusy: false
    property string statsError: ""
    property string folderError: ""
    property real pageProgress: 1
    property bool alive: true
    Component.onDestruction: alive = false
    // The installer copies VERSION next to shell.qml; a checkout without one shows no number.
    property string version: ""
    FileView {
        path: Paths.localPath(Qt.resolvedUrl("../VERSION"))
        printErrors: false
        onLoaded: root.version = text().trim().split("\n")[0].slice(0, 40)
    }
    Connections {
        target: Backend
        function onReadyChanged() {
            if (Backend.ready && root.category === "Diagnostics") root.refreshStats();
        }
    }
    function saveFolder(key, value) {
        const path = value.trim();
        if (!(path.startsWith("~/") || path.startsWith("/")) || /[\r\n]/.test(path)) {
            folderError = "Enter an absolute folder path or a path beginning with ~/";
            return;
        }
        folderError = "";
        ShellState.setSetting(key, path);
    }
    NumberAnimation {
        id: pageEntrance
        target: root
        property: "pageProgress"
        from: 0
        to: 1
        duration: Theme.enter
        easing.type: Easing.OutCubic
    }
    function refreshStats() {
        if (statsBusy || !Backend.ready)
            return;
        statsBusy = true;
        statsError = "";
        Backend.request("system.stats", {}, (result, failure) => {
            if (!root.alive)
                return;
            statsBusy = false;
            statsError = failure ? failure.message : "";
            if (!failure)
                stats = result;
        });
    }
    readonly property var toggles: ({
            Appearance: [
                {
                    label: "24-hour clock",
                    key: "clock24h",
                    defaultValue: true
                }
            ],
            Motion: [
                {
                    label: "Reduced motion",
                    key: "reducedMotion"
                },
                {
                    label: "Reduce effects in every mode",
                    key: "batterySaving"
                },
                {
                    label: "Window preview snapshots",
                    key: "windowPreviews",
                    defaultValue: true
                }
            ],
            Bar: [
                {
                    label: "Hide bar over fullscreen windows",
                    key: "hideFullscreen",
                    defaultValue: true
                },
                {
                    label: "Show what's playing in the bar",
                    key: "barMedia",
                    defaultValue: true
                },
                {
                    label: "Show a card when the track changes",
                    key: "trackChangeCard",
                    defaultValue: true
                }
            ],
            Notifications: [
                {
                    label: "Do not disturb",
                    key: "dnd"
                },
                {
                    label: "Keep notification history across restarts",
                    key: "persistNotifications"
                }
            ],
            Audio: [
                {
                    label: "Allow volume amplification up to 150%",
                    key: "amplification"
                }
            ]
        })
    readonly property var categories: [
        {name: "Appearance", icon: "palette", description: "Shape the way your desktop feels."},
        {name: "Motion", icon: "bolt", description: "Choose a pace that feels right."},
        {name: "Bar", icon: "window", description: "Keep the essentials where you need them."},
        {name: "Notifications", icon: "bell", description: "Decide what needs your attention."},
        {name: "Audio", icon: "volume", description: "Set the limits for your listening."},
        {name: "Capture", icon: "camera", description: "A home for screenshots and recordings."},
        {name: "Activity", icon: "activity", description: "Your private desktop history."},
        {name: "Shortcuts", icon: "grid", description: "Keyboard shortcuts and the commands behind them."},
        {name: "Diagnostics", icon: "info", description: "Check the services behind your desktop."}
    ]
    function revealCategory() {
        if (!compactNavigation) return;
        const index = categories.findIndex(item => item.name === category);
        const item = compactNavigationItems.itemAt(index);
        if (!item) return;
        if (item.x < compactCategories.contentX)
            compactCategories.contentX = item.x;
        else if (item.x + item.width > compactCategories.contentX + compactCategories.width)
            compactCategories.contentX = Math.min(compactCategories.contentWidth - compactCategories.width, item.x + item.width - compactCategories.width);
    }
    onCategoryChanged: {
        settingsScroll.contentItem.contentY = 0;
        folderError = "";
        pageEntrance.restart();
        if (category === "Diagnostics")
            refreshStats();
        Qt.callLater(() => root.revealCategory());
    }
    onCompactNavigationChanged: if (compactNavigation) Qt.callLater(() => root.revealCategory())
    RowLayout {
        anchors.fill: parent
        spacing: 16
        Rectangle {
            visible: !root.compactNavigation
            Layout.preferredWidth: Theme.body >= 18 ? 206 : 190
            Layout.fillHeight: true
            color: Theme.surface
            radius: Theme.controlRadius + 2
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8
                C.Label {
                    text: "Your desktop"
                    font.pixelSize: Theme.small
                    font.weight: Font.Medium
                    color: Theme.muted
                    Layout.leftMargin: 10
                    Layout.topMargin: 8
                    Layout.bottomMargin: 10
                }
                ScrollView {
                    id: navigationScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: availableWidth
                    clip: true
                    ScrollBar.vertical: C.ScrollBar {
                        parent: navigationScroll
                        x: navigationScroll.width - width
                        y: navigationScroll.topPadding
                        height: navigationScroll.availableHeight
                    }
                    ColumnLayout {
                        width: navigationScroll.availableWidth
                        spacing: 4
                        Repeater {
                            id: navigationItems
                            model: root.categories
                            C.Button {
                                id: navigation
                                required property var modelData
                                required property int index
                                text: modelData.name
                                selected: root.category === modelData.name
                                Layout.fillWidth: true
                                implicitHeight: Math.max(40, Theme.body + 22)
                                padding: 10
                                onClicked: root.category = modelData.name
                                Keys.onDownPressed: {
                                    const next = navigationItems.itemAt(Math.min(index + 1, root.categories.length - 1));
                                    root.category = next.modelData.name;
                                    next.forceActiveFocus();
                                }
                                Keys.onUpPressed: {
                                    const previous = navigationItems.itemAt(Math.max(0, index - 1));
                                    root.category = previous.modelData.name;
                                    previous.forceActiveFocus();
                                }
                                background: Rectangle {
                                    radius: 9
                                    color: navigation.selected ? (navigation.hovered || navigation.visualFocus ? Theme.selectionHover : Theme.selection) : navigation.hovered || navigation.visualFocus ? Theme.hover : "transparent"
                                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                                }
                                contentItem: RowLayout {
                                    spacing: 8
                                    C.Icon { name: navigation.modelData.icon; size: 16; opacity: navigation.selected ? 1 : 0.6 }
                                    C.Label {
                                        text: navigation.text
                                        color: navigation.selected ? Theme.accentText : Theme.muted
                                        font.weight: navigation.selected ? Font.DemiBold : Font.Normal
                                        font.pixelSize: Theme.body
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                    }
                }
                C.Label {
                    text: "Shale"
                    font.pixelSize: Theme.label
                    font.weight: Font.DemiBold
                    Layout.leftMargin: 10
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8
            Flickable {
                id: compactCategories
                visible: root.compactNavigation
                Layout.fillWidth: true
                Layout.preferredHeight: root.compactNavigation ? 38 : 0
                contentWidth: compactCategoryRow.implicitWidth
                contentHeight: height
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                Row {
                    id: compactCategoryRow
                    height: parent.height
                    spacing: 6
                    Repeater {
                        id: compactNavigationItems
                        model: root.categories
                        C.Button {
                            required property var modelData
                            text: modelData.name
                            selected: root.category === modelData.name
                            implicitHeight: 36
                            onClicked: root.category = modelData.name
                        }
                    }
                }
            }
            ScrollView {
            id: settingsScroll
            ScrollBar.vertical: C.ScrollBar {
                parent: settingsScroll
                x: settingsScroll.width - width
                y: settingsScroll.topPadding
                height: settingsScroll.availableHeight
            }
            opacity: root.pageProgress
            transform: Translate { x: Theme.reduced ? 0 : (1 - root.pageProgress) * 6 }
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true
            ColumnLayout {
                width: settingsScroll.availableWidth
                spacing: 16
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        C.Label {
                            text: root.category
                            font.pixelSize: 22
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                        }
                        C.Button {
                            visible: root.category === "Diagnostics"
                            text: root.statsBusy ? "Refreshing…" : "Refresh"
                            glyph: "refresh"
                            enabled: !root.statsBusy && Backend.ready
                            onClicked: root.refreshStats()
                        }
                    }
                    C.Label {
                        text: {
                            const current = root.categories.find(item => item.name === root.category);
                            return current ? current.description : "";
                        }
                        color: Theme.muted
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
                C.Label {
                    visible: root.folderError !== ""
                    text: root.folderError
                    color: Theme.danger
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                C.Label {
                    visible: (root.toggles[root.category] || []).length > 0
                    text: "Preferences"
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }
                Repeater {
                    model: root.toggles[root.category] || []
                    C.Toggle {
                        required property var modelData
                        text: modelData.label
                        selected: ShellState.setting(modelData.key, modelData.defaultValue || false)
                        Layout.fillWidth: true
                        onClicked: ShellState.setSetting(modelData.key, !ShellState.setting(modelData.key, modelData.defaultValue || false))
                    }
                }
                ColumnLayout {
                    visible: root.category === "Appearance"
                    Layout.fillWidth: true
                    spacing: 16
                    ColorSettings { Layout.fillWidth: true }
                    C.Label { text: "Wallpapers"; font.weight: Font.DemiBold; Layout.fillWidth: true; Layout.topMargin: 4 }
                    C.Label { text: "Wallpaper folder" }
                    C.Field {
                        Layout.fillWidth: true
                        Accessible.name: "Wallpaper folder"
                        text: ShellState.setting("wallpaperDirectory", "~/Pictures/Wallpapers")
                        onEditingFinished: root.saveFolder("wallpaperDirectory", text)
                    }
                    C.Button {
                        text: "Choose wallpaper"
                        glyph: "palette"
                        Layout.fillWidth: true
                        onClicked: ShellState.open("wallpaper")
                    }
                    C.Label { text: "Lock screen"; font.weight: Font.DemiBold; Layout.fillWidth: true; Layout.topMargin: 4 }
                    C.Toggle {
                        readonly property bool hyprlock: Backend.has("hyprlock", true)
                        readonly property bool builtin: ShellState.setting("lockScreen", "builtin") === "builtin" || !hyprlock
                        Layout.fillWidth: true
                        enabled: hyprlock
                        text: "Use the built-in lock screen"
                        description: !hyprlock ? "Install hyprlock to use it instead." : builtin ? "Blurred wallpaper, clock and media controls. hyprlock takes over if the shell stops." : "hyprlock locks the screen."
                        selected: builtin
                        onClicked: ShellState.setSetting("lockScreen", builtin ? "hyprlock" : "builtin")
                    }
                    C.Label { text: "Typography"; font.weight: Font.DemiBold; Layout.fillWidth: true; Layout.topMargin: 4 }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        C.Label {
                            text: "Text size"
                            Layout.fillWidth: true
                        }
                        Repeater {
                            model: [12, 14, 16, 18]
                            C.Button {
                                required property int modelData
                                text: String(modelData)
                                implicitWidth: 42
                                selected: Theme.body === modelData
                                onClicked: ShellState.setSetting("fontSize", modelData)
                            }
                        }
                    }
                }
                ColumnLayout {
                    visible: root.category === "Bar"
                    Layout.fillWidth: true
                    C.Label {
                        text: "Displays"
                        color: Theme.muted
                        font.weight: Font.Medium
                        Layout.fillWidth: true
                    }
                    Repeater {
                        model: Quickshell.screens
                        C.Toggle {
                            required property var modelData
                            Layout.fillWidth: true
                            text: modelData.name
                            selected: ShellState.setting("hiddenOutputs", []).indexOf(modelData.name) < 0
                            onClicked: {
                                const hidden = ShellState.setting("hiddenOutputs", []);
                                ShellState.setSetting("hiddenOutputs", hidden.indexOf(modelData.name) < 0 ? hidden.concat([modelData.name]) : hidden.filter(n => n !== modelData.name));
                            }
                        }
                    }
                }
                C.Label {
                    visible: root.category === "Notifications"
                    text: "Keep up to 200 notifications for seven days when history is enabled. Contents stay hidden on the lock screen."
                    color: Theme.muted
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                ColumnLayout {
                    visible: root.category === "Capture"
                    Layout.fillWidth: true
                    spacing: 12
                    C.Label {
                        text: "Screenshot folder"
                    }
                    C.Field {
                        Layout.fillWidth: true
                        Accessible.name: "Screenshot folder"
                        text: ShellState.setting("screenshotDirectory", "~/Pictures/Screenshots")
                        onEditingFinished: root.saveFolder("screenshotDirectory", text)
                    }
                    C.Label {
                        text: "Recording folder"
                    }
                    C.Field {
                        Layout.fillWidth: true
                        Accessible.name: "Recording folder"
                        text: ShellState.setting("recordingDirectory", "~/Videos/Recordings")
                        onEditingFinished: root.saveFolder("recordingDirectory", text)
                    }
                }
                ColumnLayout {
                    visible: root.category === "Activity"
                    Layout.fillWidth: true
                    spacing: 12
                    C.Toggle {
                        Layout.fillWidth: true
                        text: "Record activity"
                        description: "How long you use each app and when you're active. It stays on this computer."
                        selected: ShellState.setting("activityTracking", "ask") === "on"
                        onClicked: ShellState.setSetting("activityTracking", selected ? "off" : "on")
                    }
                    C.Label { text: "Desktop activity is stored locally and kept until you clear it. Active time ends at your last input; time with a video playing or an app keeping the screen awake counts as watching. Window titles are never recorded."; color: Theme.muted; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    C.Label { text: "App history contains visible app IDs and time ranges. Window titles are never saved."; color: Theme.muted; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    C.Button { text: "Open activity"; glyph: "activity"; Layout.fillWidth: true; onClicked: ShellState.open("activity") }
                    C.Label { text: "Pause recording or hold Clear history from the Activity panel."; color: Theme.muted; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                }
                ColumnLayout {
                    visible: root.category === "Shortcuts"
                    Layout.fillWidth: true
                    spacing: 12
                    C.Label {
                        text: "Keys come from the installed Hyprland fragment. Copy a command to bind it elsewhere."
                        color: Theme.muted
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: shortcutList.implicitHeight + 8
                        radius: Theme.controlRadius
                        color: Theme.surface
                        ColumnLayout {
                            id: shortcutList
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 4
                            spacing: 0
                            Repeater {
                                // Mirrors integration/shale.lua; Wallpapers is bound only when installed with --wallpaper-shortcut.
                                model: [
                                    {title: "Launcher", keys: ["Super", "Space"], command: "shale launcher"},
                                    {title: "Clipboard", keys: ["Super", "V"], command: "shale clipboard"},
                                    {title: "Control center", keys: ["Super", "A"], command: "shale control"},
                                    {title: "Notifications", keys: ["Super", "N"], command: "shale notifications"},
                                    {title: "Workspaces", keys: ["Super", "O"], command: "shale overview"},
                                    {title: "Activity", keys: ["Super", "Shift", "A"], command: "shale activity"},
                                    {title: "System monitor", keys: ["Ctrl", "Shift", "Esc"], command: "shale system"},
                                    {title: "Wallpapers (opt-in shortcut)", keys: ["Super", "Shift", "W"], command: "shale wallpaper"},
                                    {title: "Settings", keys: ["Super", ","], command: "shale settings"},
                                    {title: "Region screenshot", keys: ["Print"], command: "shale screenshot region"},
                                    {title: "Display screenshot", keys: ["Shift", "Print"], command: "shale screenshot output"},
                                    {title: "Capture", keys: ["Super", "Print"], command: "shale capture"},
                                    {title: "Session", keys: ["Super", "M"], command: "shale power"},
                                    {title: "Lock screen", keys: ["Super", "L"], command: "shale lock"},
                                    {title: "Close panel", keys: ["Esc"], command: "shale close"}
                                ]
                                RowLayout {
                                    id: shortcut
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Math.max(40, Theme.body + 26)
                                    spacing: 6
                                    C.Label {
                                        text: shortcut.modelData.title
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 10
                                    }
                                    Repeater {
                                        model: shortcut.modelData.keys
                                        Rectangle {
                                            required property string modelData
                                            implicitWidth: Math.max(26, keyLabel.implicitWidth + 14)
                                            implicitHeight: Math.max(24, Theme.caption + 12)
                                            radius: 6
                                            color: Theme.raised
                                            C.Label {
                                                id: keyLabel
                                                anchors.centerIn: parent
                                                text: parent.modelData
                                                font.family: Theme.mono
                                                font.pixelSize: Theme.caption
                                            }
                                        }
                                    }
                                    C.Button {
                                        glyph: "copy"
                                        hint: "Copy command " + shortcut.modelData.command
                                        flat: true
                                        implicitWidth: 32
                                        implicitHeight: 32
                                        onClicked: ShellState.run("clipboard.write", {text: shortcut.modelData.command}, () => ShellState.message("Copied · " + shortcut.modelData.command, "success"))
                                    }
                                }
                            }
                        }
                    }
                }
                ColumnLayout {
                    visible: root.category === "Diagnostics"
                    Layout.fillWidth: true
                    spacing: 12
                    C.StatusCard {
                        title: Backend.ready ? "Connected" : "Helper offline"
                        subtitle: Backend.ready ? "Desktop services are available" : "Desktop controls may be unavailable"
                        glyph: "info"
                        positive: Backend.ready
                        Layout.fillWidth: true
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        C.Label { text: "Version"; Layout.fillWidth: true }
                        C.Label {
                            text: root.version ? "Shale " + root.version : "Shale · version unknown"
                            font.family: Theme.mono
                            color: Theme.muted
                        }
                    }
                    C.Label {
                        text: Backend.capabilities.dbus ? "D-Bus adapter available" : "Install python-dbus-next for Wi-Fi and power controls"
                        color: Theme.muted
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                    Repeater {
                        model: Object.keys(Backend.capabilities.commands || {})
                        RowLayout {
                            required property string modelData
                            Layout.fillWidth: true
                            C.Label {
                                text: parent.modelData
                                font.family: Theme.mono
                                wrapMode: Text.WrapAnywhere
                                Layout.fillWidth: true
                            }
                            C.Label {
                                text: Backend.has(parent.modelData, false) ? "Available" : "Not installed"
                                color: Backend.has(parent.modelData, false) ? Theme.success : Theme.muted
                            }
                        }
                    }
                    C.Label {
                        text: root.statsError || ShellState.settings.diagnostic || Backend.lastError
                        visible: text !== ""
                        color: Theme.warning
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Repeater {
                        model: root.stats.memoryTotal > 0 ? [
                            {title: "Memory", used: root.stats.memoryUsed, total: root.stats.memoryTotal},
                            {title: "Home storage", used: root.stats.diskUsed, total: root.stats.diskTotal}
                        ] : []
                        Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: resourceContent.implicitHeight + 32
                            radius: Theme.controlRadius
                            color: Theme.surface
                            ColumnLayout {
                                id: resourceContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 16
                                spacing: 12
                                RowLayout {
                                    Layout.fillWidth: true
                                    C.Label { text: modelData.title; Layout.fillWidth: true }
                                    C.Label {
                                        text: (modelData.used / 1073741824).toFixed(1) + " / " + (modelData.total / 1073741824).toFixed(1) + " GiB"
                                        color: Theme.muted
                                        font.pixelSize: Theme.small
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 5
                                    radius: 2.5
                                    color: Theme.raised
                                    Rectangle {
                                        width: parent.width * Math.max(0, Math.min(1, modelData.total > 0 ? modelData.used / modelData.total : 0))
                                        height: parent.height
                                        radius: parent.radius
                                        color: modelData.used / modelData.total > 0.9 ? Theme.warning : Theme.text
                                    }
                                }
                            }
                        }
                    }
                    C.Label {
                        visible: root.stats.memoryTotal > 0
                        text: "System load · " + Number(root.stats.load).toFixed(2)
                        color: Theme.muted
                        Layout.fillWidth: true
                    }
                }
                Item {
                    Layout.preferredHeight: 10
                }
            }
            }
        }
    }
}
