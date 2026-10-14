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
                {label: "24-hour clock", key: "clock24h", defaultValue: true}
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
                {label: "Allow volume amplification up to 150%", key: "amplification"}
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
        pageEntrance.restart();
        Qt.callLater(() => root.revealCategory());
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
                }
                ColumnLayout {
                    visible: root.category === "Bar"
                    Layout.fillWidth: true
                    spacing: Theme.gapS
                    C.SectionHeader {
                        text: "Show the bar on"
                        Layout.topMargin: Theme.gapS
                    }
                    C.Group {
                        Repeater {
                            model: Quickshell.screens
                            C.Toggle {
                                required property var modelData
                                Layout.fillWidth: true
                                flat: true
                                text: modelData.name
                                description: modelData.model || ""
                                selected: ShellState.setting("hiddenOutputs", []).indexOf(modelData.name) < 0
                                onClicked: {
                                    const hidden = ShellState.setting("hiddenOutputs", []);
                                    ShellState.setSetting("hiddenOutputs", hidden.indexOf(modelData.name) < 0 ? hidden.concat([modelData.name]) : hidden.filter(n => n !== modelData.name));
                                }
                            }
                        }
                    }
                }
                ColumnLayout {
                    visible: root.category === "Capture"
                    Layout.fillWidth: true
                    spacing: Theme.gapL
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
                    visible: root.category === "Shortcuts"
                    Layout.fillWidth: true
                    spacing: Theme.gapM
                    C.Label {
                        text: "Keys come from the installed Hyprland fragment. Copy a command to bind it elsewhere."
                        color: Theme.muted
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    C.Group {
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
                                spacing: Theme.gapXs + 2
                                C.Label {
                                    text: shortcut.modelData.title
                                    Layout.fillWidth: true
                                    Layout.leftMargin: Theme.gapM - 2
                                }
                                Repeater {
                                    model: shortcut.modelData.keys
                                    Rectangle {
                                        required property string modelData
                                        implicitWidth: Math.max(26, keyLabel.implicitWidth + 14)
                                        implicitHeight: Math.max(24, Theme.caption + 12)
                                        radius: Theme.radiusSmall - 2
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
                    C.Button {
                        text: "Open system monitor"
                        glyph: "gauge"
                        Layout.fillWidth: true
                        onClicked: ShellState.open("system")
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
