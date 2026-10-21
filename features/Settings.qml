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
    readonly property string title: "Settings"
    readonly property int panelWidth: 820
    readonly property int panelHeight: 600
    property string category: "Appearance"
    readonly property bool compactNavigation: width < 620
    property real pageProgress: 1
    // The installer writes the commit it installed next to shell.qml; a checkout run directly has none.
    property string version: ""
    FileView {
        path: Paths.localPath(Qt.resolvedUrl("../COMMIT"))
        printErrors: false
        onLoaded: root.version = text().trim().split("\n")[0].slice(0, 40)
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
    // A folder setting with its own error and a short confirmation once saved.
    component FolderField: ColumnLayout {
        id: folder
        property string label: ""
        property string key: ""
        property string fallback: ""
        property string error: ""
        property bool saved: false
        function save(value) {
            const path = value.trim();
            if (!(path.startsWith("~/") || path.startsWith("/")) || /[\r\n]/.test(path)) {
                error = "Enter an absolute folder path or a path beginning with ~/";
                return;
            }
            error = "";
            if (path === ShellState.setting(key, fallback))
                return;
            ShellState.setSetting(key, path);
            saved = true;
            savedTimer.restart();
        }
        Layout.fillWidth: true
        spacing: Theme.gapXs + 2
        C.Label {
            text: folder.label
            Layout.fillWidth: true
        }
        C.Field {
            Layout.fillWidth: true
            Accessible.name: folder.label
            text: ShellState.setting(folder.key, folder.fallback)
            onTextEdited: folder.saved = false
            onEditingFinished: folder.save(text)
        }
        C.Label {
            visible: folder.error !== "" || folder.saved
            text: folder.error || "Saved"
            color: folder.error ? Theme.danger : Theme.success
            font.pixelSize: Theme.small
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        Timer {
            id: savedTimer
            interval: 2500
            onTriggered: folder.saved = false
        }
    }
    // Plain on/off preferences, grouped per category.
    readonly property var toggles: ({
            Appearance: [
                {label: "Music visualizer", key: "visualizer", defaultValue: true, description: "In the bar and on the media page"}
            ],
            General: [
                {label: "24-hour clock", key: "clock24h", defaultValue: true},
                {label: "Check for updates", key: "updateCheck", defaultValue: true, description: "Asks GitHub every 12 hours. The control center shows what a new version changes."},
                {label: "Carry over at shift start", key: "autoCarry", description: "Moves yesterday's uncleared orders with no time to today by itself"}
            ],
            Motion: [
                {label: "Reduced motion", key: "reducedMotion", description: "Panels and controls change without animating"},
                {label: "Reduce effects in every mode", key: "batterySaving", description: "No visualizers, blur, shadows or live window previews"},
                {label: "Window preview snapshots", key: "windowPreviews", defaultValue: true}
            ],
            Bar: [
                {label: "Hide bar over fullscreen windows", key: "hideFullscreen", defaultValue: true},
                {label: "Show what's playing in the bar", key: "barMedia", defaultValue: true},
                {label: "Show a card when the track changes", key: "trackChangeCard", defaultValue: true}
            ],
            Notifications: [
                {label: "Keep notification history across restarts", key: "persistNotifications", description: "Up to 200 notifications for seven days. Contents stay hidden on the lock screen."}
            ],
            Audio: [
                {label: "Allow volume amplification up to 150%", key: "amplification"},
                {label: "Show time left instead of track length", key: "mediaRemaining"}
            ]
        })
    readonly property var categories: [
        {name: "Appearance", icon: "palette", description: "Shape the way your desktop feels."},
        {name: "Bar", icon: "window", description: "Keep the essentials where you need them."},
        {name: "Control center", icon: "settings", description: "The switches and buttons you reach for most."},
        {name: "Shortcuts", icon: "grid", description: "Keyboard shortcuts and the commands behind them."},
        {name: "General", icon: "calendar", description: "Time, units, search, the terminal and updates."},
        {name: "Motion", icon: "bolt", description: "Choose a pace that feels right."},
        {name: "Notifications", icon: "bell", description: "Decide what needs your attention."},
        {name: "Audio", icon: "volume", description: "Set the limits for your listening."},
        {name: "Capture", icon: "camera", description: "A home for screenshots and recordings."},
        {name: "Activity", icon: "activity", description: "Your private desktop history."},
        {name: "Backup", icon: "folder", description: "Keep a copy of your settings or move them."},
        {name: "Diagnostics", icon: "info", description: "Check the services behind your desktop."}
    ]
    // The settings each page owns, for its reset button.
    readonly property var resetKeys: ({
            Appearance: ["fontSize", "accentColor", "accentManual", "accentFromWallpaper", "surfaceTone", "visualizer", "wallpaperDirectory", "lockScreen", "lockStyle"],
            Bar: ["hideFullscreen", "barMedia", "trackChangeCard", "hiddenOutputs", "barLayout", "barStyle", "clockFormat", "clockSeconds",
                  "workspaceStyle", "workspaceSlots", "trayIcons", "batteryPercent"],
            "Control center": ["controlLayout"],
            General: ["clock24h", "weekStart", "weatherUnits", "searchEngine", "terminal", "updateCheck", "dailyTarget", "weeklyTarget", "daysOff", "shiftStart", "autoCarry"],
            Motion: ["reducedMotion", "batterySaving", "windowPreviews"],
            Notifications: ["persistNotifications", "focusMinutes"],
            Audio: ["amplification", "mediaRemaining"],
            Capture: ["screenshotDirectory", "recordingDirectory", "recordAudio", "captureDelay"]
        })
    // Opens a page by its name or as typed after `shale settings` ("control-center").
    function showPage(name) {
        const wanted = String(name || "").toLowerCase().replace(/[-_]/g, " ").trim();
        const found = categories.find(item => item.name.toLowerCase() === wanted);
        if (found)
            category = found.name;
    }
    Component.onCompleted: showPage(ShellState.detail)
    Connections {
        target: ShellState
        function onDetailChanged() {
            if (ShellState.panel === "settings")
                root.showPage(ShellState.detail);
        }
    }
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
        pageEntrance.restart();
        Qt.callLater(() => root.revealCategory());
    }
    // For previews of long pages.
    function scrollTo(y) {
        settingsScroll.contentItem.contentY = Math.max(0, Math.min(y, settingsScroll.contentItem.contentHeight - settingsScroll.height));
    }
    onCompactNavigationChanged: if (compactNavigation) Qt.callLater(() => root.revealCategory())
    RowLayout {
        anchors.fill: parent
        spacing: Theme.gapL
        C.Card {
            visible: !root.compactNavigation
            Layout.preferredWidth: Theme.body >= 18 ? 206 : 190
            Layout.fillHeight: true
            ScrollView {
                id: navigationScroll
                anchors.fill: parent
                anchors.margins: Theme.gapS
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
                    spacing: Theme.gapXs
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
                            padding: Theme.gapM - 2
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
                                radius: Theme.radiusSmall
                                color: navigation.selected ? (navigation.hovered || navigation.visualFocus ? Theme.selectionHover : Theme.selection) : navigation.hovered || navigation.visualFocus ? Theme.hover : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.fast } }
                            }
                            contentItem: RowLayout {
                                spacing: Theme.gapS
                                C.Icon { name: navigation.modelData.icon; color: navigation.selected ? Theme.accentText : Theme.muted }
                                C.Label {
                                    text: navigation.text
                                    color: navigation.selected ? Theme.accentText : Theme.muted
                                    font.weight: navigation.selected ? Font.DemiBold : Font.Normal
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.gapS
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
                    spacing: Theme.gapXs + 2
                    Repeater {
                        id: compactNavigationItems
                        model: root.categories
                        C.Button {
                            required property var modelData
                            text: modelData.name
                            flat: true
                            selected: root.category === modelData.name
                            implicitHeight: Theme.controlHeight
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
                spacing: Theme.gapM
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.gapXs
                    Layout.bottomMargin: Theme.gapXs
                    spacing: Theme.gapXs
                    C.Label {
                        text: root.category
                        font.pixelSize: Theme.heading
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
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
                C.Group {
                    visible: (root.toggles[root.category] || []).length > 0
                    Repeater {
                        model: root.toggles[root.category] || []
                        C.Toggle {
                            required property var modelData
                            text: modelData.label
                            description: modelData.description || ""
                            flat: true
                            selected: ShellState.setting(modelData.key, modelData.defaultValue || false)
                            Layout.fillWidth: true
                            onClicked: ShellState.setSetting(modelData.key, !ShellState.setting(modelData.key, modelData.defaultValue || false))
                        }
                    }
                }
                ColumnLayout {
                    visible: root.category === "Appearance"
                    Layout.fillWidth: true
                    spacing: Theme.gapM
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.gapM
                        C.Label {
                            text: "Text size"
                            Layout.fillWidth: true
                        }
                        C.Segmented {
                            fill: false
                            Layout.preferredWidth: 220
                            model: [12, 14, 16, 18].map(size => ({key: size, text: String(size)}))
                            current: Theme.body
                            onActivated: key => ShellState.setSetting("fontSize", key)
                        }
                    }
                    ColorSettings {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.gapS
                    }
                    C.SectionHeader {
                        text: "Wallpaper"
                        Layout.topMargin: Theme.gapS
                    }
                    FolderField {
                        label: "Wallpaper folder"
                        key: "wallpaperDirectory"
                        fallback: "~/Pictures/Wallpapers"
                    }
                    C.Button {
                        text: "Choose wallpaper"
                        glyph: "palette"
                        Layout.fillWidth: true
                        onClicked: ShellState.open("wallpaper")
                    }
                    C.SectionHeader {
                        text: "Lock screen"
                        Layout.topMargin: Theme.gapS
                    }
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
                    C.ChoiceRow {
                        visible: ShellState.setting("lockScreen", "builtin") === "builtin" || !Backend.has("hyprlock", true)
                        label: "Style"
                        description: ShellState.setting("lockStyle", "particles") === "classic" ? "A large clock over your wallpaper" : "The time drawn in points of light that gather, shift and burst"
                        model: [{key: "particles", text: "Particles"}, {key: "classic", text: "Classic"}]
                        current: ShellState.setting("lockStyle", "particles")
                        onActivated: key => ShellState.setSetting("lockStyle", key)
                    }
                }
                BarSettings {
                    visible: root.category === "Bar"
                    Layout.fillWidth: true
                }
                C.ChoiceRow {
                    visible: root.category === "Notifications"
                    label: "Focus length"
                    description: "Notifications wait until a focus session ends"
                    model: [25, 50, 90].map(minutes => ({key: minutes, text: minutes + " min"}))
                    current: ShellState.setting("focusMinutes", 25)
                    onActivated: key => ShellState.setSetting("focusMinutes", key)
                }
                C.Button {
                    visible: root.category === "Audio"
                    text: "Open the equalizer"
                    glyph: "equalizer"
                    Layout.fillWidth: true
                    onClicked: {
                        ShellState.open("control");
                        ShellState.detail = "media";
                    }
                }
                BackupSettings {
                    visible: root.category === "Backup"
                    Layout.fillWidth: true
                }
                ColumnLayout {
                    visible: root.category === "Capture"
                    Layout.fillWidth: true
                    spacing: Theme.gapL
                    C.ChoiceRow {
                        label: "Recording sound"
                        model: [{key: "none", text: "None"}, {key: "system", text: "System"}, {key: "microphone", text: "Microphone"}]
                        current: ShellState.setting("recordAudio", "none")
                        onActivated: key => ShellState.setSetting("recordAudio", key)
                    }
                    C.ChoiceRow {
                        label: "Screenshot delay"
                        model: [0, 3, 5, 10].map(seconds => ({key: seconds, text: seconds ? seconds + " s" : "None"}))
                        current: ShellState.setting("captureDelay", 0)
                        onActivated: key => ShellState.setSetting("captureDelay", key)
                    }
                    FolderField {
                        label: "Screenshot folder"
                        key: "screenshotDirectory"
                        fallback: "~/Pictures/Screenshots"
                    }
                    FolderField {
                        label: "Recording folder"
                        key: "recordingDirectory"
                        fallback: "~/Videos/Recordings"
                    }
                }
                ColumnLayout {
                    visible: root.category === "Activity"
                    Layout.fillWidth: true
                    spacing: Theme.gapM
                    C.Group {
                        C.Toggle {
                            Layout.fillWidth: true
                            flat: true
                            text: "Record activity"
                            description: "How long you use each app and when you're active. It stays on this computer."
                            selected: ShellState.setting("activityTracking", "ask") === "on"
                            onClicked: ShellState.setSetting("activityTracking", selected ? "off" : "on")
                        }
                    }
                    C.Label {
                        text: "Active time ends at your last input; time with a video playing or an app keeping the screen awake counts as watching. Only app IDs and time ranges are kept, never window titles, until you clear them. Pause recording or hold Clear history in the Activity panel."
                        color: Theme.muted
                        font.pixelSize: Theme.small
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    C.Button { text: "Open activity"; glyph: "activity"; Layout.fillWidth: true; onClicked: ShellState.open("activity") }
                }
                ColumnLayout {
                    visible: root.category === "General"
                    Layout.fillWidth: true
                    spacing: Theme.gapM
                    C.ChoiceRow {
                        label: "Week starts on"
                        description: "In the calendar and Activity"
                        model: [{key: "locale", text: "Auto", hint: "As your language and region have it"}, {key: "monday", text: "Mon"}, {key: "sunday", text: "Sun"}, {key: "saturday", text: "Sat"}]
                        current: ShellState.setting("weekStart", "locale")
                        onActivated: key => ShellState.setSetting("weekStart", key)
                    }
                    C.ChoiceRow {
                        label: "Daily target"
                        description: "Orders to clear each day; 0 turns targets and streaks off"
                        model: [0, 3, 5, 8, 10].map(count => ({key: count, text: count ? String(count) : "Off"}))
                        current: ShellState.setting("dailyTarget", 5)
                        onActivated: key => ShellState.setSetting("dailyTarget", key)
                    }
                    C.ChoiceRow {
                        label: "Weekly target"
                        model: [15, 25, 40].map(count => ({key: count, text: String(count)}))
                        current: ShellState.setting("weeklyTarget", 25)
                        onActivated: key => ShellState.setSetting("weeklyTarget", key)
                    }
                    C.ChoiceRow {
                        label: "Days off"
                        description: "They pause days on target without breaking it"
                        model: [{key: "none", text: "None"}, {key: "weekend", text: "Sat, Sun"}, {key: "sunday", text: "Sun"}]
                        current: ({"": "none", "5,6": "weekend", "6": "sunday"})[ShellState.setting("daysOff", []).join(",")] || "none"
                        onActivated: key => ShellState.setSetting("daysOff", ({none: [], weekend: [5, 6], sunday: [6]})[key])
                    }
                    C.ChoiceRow {
                        label: "Shift starts at"
                        description: "The planning screens show once a day after this time"
                        model: ["04:00", "05:00", "06:00", "07:00", "08:00"].map(time => ({key: time, text: time}))
                        current: ShellState.setting("shiftStart", "05:00")
                        onActivated: key => ShellState.setSetting("shiftStart", key)
                    }
                    C.ChoiceRow {
                        label: "Weather units"
                        model: [{key: "metric", text: "°C, km/h"}, {key: "imperial", text: "°F, mph"}]
                        current: ShellState.setting("weatherUnits", "metric")
                        onActivated: key => ShellState.setSetting("weatherUnits", key)
                    }
                    C.ChoiceRow {
                        label: "Web search"
                        description: "Type ? in the launcher"
                        model: [{key: "duckduckgo", text: "DuckDuckGo"}, {key: "google", text: "Google"}, {key: "brave", text: "Brave"}]
                        current: ShellState.setting("searchEngine", "duckduckgo")
                        onActivated: key => ShellState.setSetting("searchEngine", key)
                    }
                    C.ChoiceRow {
                        readonly property string chosen: ShellState.setting("terminal", "auto")
                        readonly property var installed: Backend.capabilities.terminals || []
                        label: "Terminal"
                        description: "For commands run with > in the launcher"
                        model: [{key: "auto", text: "Auto", hint: "$TERMINAL or the first one installed"}]
                            .concat(installed.concat(chosen !== "auto" && installed.indexOf(chosen) < 0 ? [chosen] : []).map(name => ({key: name, text: name})))
                        current: chosen
                        onActivated: key => ShellState.setSetting("terminal", key)
                    }
                }
                ControlSettings {
                    visible: root.category === "Control center"
                    Layout.fillWidth: true
                }
                ShortcutSettings {
                    visible: root.category === "Shortcuts"
                    Layout.fillWidth: true
                }
                ColumnLayout {
                    visible: root.category === "Diagnostics"
                    Layout.fillWidth: true
                    spacing: Theme.gapM
                    C.StatusCard {
                        title: Backend.ready ? "Connected" : "Helper offline"
                        subtitle: Backend.ready ? "Desktop services are available" : "Desktop controls may be unavailable"
                        glyph: "info"
                        positive: Backend.ready
                        Layout.fillWidth: true
                    }
                    C.Label {
                        text: ShellState.settings.diagnostic || Backend.lastError
                        visible: text !== ""
                        color: Theme.warning
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    C.Group {
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.controlLarge
                            Layout.leftMargin: Theme.gapM
                            Layout.rightMargin: Theme.gapM
                            C.Label { text: "Version"; Layout.fillWidth: true }
                            C.Label {
                                text: root.version ? "Shale " + root.version : "Shale · version unknown"
                                font.family: Theme.mono
                                color: Theme.muted
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.controlLarge
                            Layout.leftMargin: Theme.gapM
                            Layout.rightMargin: Theme.gapM
                            C.Label { text: "D-Bus adapter"; Layout.fillWidth: true }
                            C.Label {
                                text: Backend.capabilities.dbus ? "Available" : "Install python-dbus-next for Wi-Fi and power controls"
                                color: Backend.capabilities.dbus ? Theme.success : Theme.warning
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignRight
                                Layout.maximumWidth: 300
                            }
                        }
                    }
                    C.SectionHeader {
                        text: "Commands"
                        Layout.topMargin: Theme.gapS
                    }
                    C.Group {
                        Repeater {
                            model: Object.keys(Backend.capabilities.commands || {})
                            RowLayout {
                                required property string modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.max(36, Theme.body + 20)
                                Layout.leftMargin: Theme.gapM
                                Layout.rightMargin: Theme.gapM
                                C.Label {
                                    text: parent.modelData
                                    font.family: Theme.mono
                                    wrapMode: Text.WrapAnywhere
                                    Layout.fillWidth: true
                                }
                                C.Label {
                                    text: Backend.has(parent.modelData, false) ? "Available" : "Not installed"
                                    color: Backend.has(parent.modelData, false) ? Theme.success : Theme.muted
                                    font.pixelSize: Theme.small
                                }
                            }
                        }
                    }
                    C.ChoiceRow {
                        label: "System monitor graphs"
                        model: [{key: 60, text: "1 min"}, {key: 300, text: "5 min"}]
                        current: ShellState.setting("systemWindow", 60)
                        onActivated: key => ShellState.setSetting("systemWindow", key)
                    }
                    C.Button {
                        text: "Open system monitor"
                        glyph: "gauge"
                        Layout.fillWidth: true
                        onClicked: ShellState.open("system")
                    }
                }
                C.ResetButton {
                    visible: !!root.resetKeys[root.category]
                    Layout.topMargin: Theme.gapM
                    description: "Hold to put this page back to how Shale comes"
                    onConfirmed: {
                        const page = root.category;
                        ShellState.resetSettings(root.resetKeys[page], () => ShellState.message(page + " settings reset", "success"));
                    }
                }
                Item {
                    Layout.preferredHeight: Theme.gapS
                }
            }
            }
        }
    }
}
