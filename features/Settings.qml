import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import "../core"
import "../core/paths.js" as Paths
import "../components" as C

// Settings: the sections with their icons and Find a setting on the left; the chosen page on the right, its settings
// in grouped cards of rows. Typing in Find a setting lists matching rows from every page; picking one opens its page
// and lights the row up.
FocusScope {
    id: root
    readonly property string title: "Settings"
    readonly property int panelWidth: 1060
    readonly property int panelHeight: 680
    // The sidebar carries the title; Escape or a click outside closes.
    readonly property bool showHeader: false
    property string category: "Appearance"
    property string query: ""
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
        duration: Theme.panelEnter
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.easeOut
    }
    // Aliases keep older names working: `shale settings control-center`, Find's "settings:Control center", and the
    // Motion and Audio pages, now part of Appearance and Sound.
    readonly property var categories: [
        {name: "Appearance", icon: "palette", aliases: ["motion"], description: "Colour, size, motion, wallpaper and the lock screen."},
        {name: "Displays", icon: "monitor", description: "Resolution, refresh rate and scale for each screen."},
        {name: "Bar", icon: "bar", description: "Put bar items in order, and choose how the bar looks."},
        {name: "Control", icon: "sliders", aliases: ["control center"], description: "What the Control panel shows, and in which order."},
        {name: "Desktop", icon: "widgets", aliases: ["widgets"], description: "Widgets on the desktop: which cards, their order and their corner."},
        {name: "Shortcuts", icon: "keyboard", description: "Keyboard shortcuts and what they open."},
        {name: "General", icon: "settings", description: "Time, units, search, the terminal and updates."},
        {name: "Notifications", icon: "bell", description: "History, quiet hours and focus sessions."},
        {name: "Sound", icon: "volume", aliases: ["audio"], description: "Volume limits and the player."},
        {name: "Power", icon: "power", aliases: ["battery", "lid"], description: "Power modes, the lid and refresh rate."},
        {name: "Capture", icon: "camera", description: "Screenshots and recordings, and where they go."},
        {name: "AirDrop", icon: "airdrop", description: "Receiving from iPhones and Macs, and where files go."},
        {name: "Activity", icon: "pulse", description: "Your private desktop history."},
        {name: "Backup", icon: "folder", description: "Keep a copy of your settings or move them."},
        {name: "Diagnostics", icon: "info", description: "The services behind your desktop."}
    ]
    // The settings each page owns, for its reset button.
    readonly property var resetKeys: ({
            Appearance: ["fontSize", "panelSize", "accentColor", "accentManual", "accentFromWallpaper", "surfaceTone", "visualizer", "wallpaperDirectory", "wallpaperFit", "lockScreen", "lockStyle",
                         "motion", "reducedMotion", "batterySaving", "windowPreviews"],
            Bar: ["hideFullscreen", "barMedia", "trackChangeCard", "hiddenOutputs", "barLayout", "barStyle", "clockFormat", "clockSeconds",
                  "workspaceStyle", "workspaceSlots", "trayIcons", "batteryPercent"],
            Control: ["controlLayout"],
            Desktop: ["widgets", "widgetCards", "widgetCorner"],
            General: ["clock24h", "weekStart", "weatherUnits", "searchEngine", "terminal", "updateCheck"],
            Notifications: ["persistNotifications", "focusMinutes", "quietHours"],
            Sound: ["amplification", "mediaRemaining"],
            Power: ["saverRefresh"],
            Capture: ["screenshotDirectory", "recordingDirectory", "recordAudio", "captureDelay"],
            AirDrop: ["airdropMode", "airdropAsk", "airdropTimeout", "airdropFolder"],
            Activity: ["activityKeep"],
            Diagnostics: ["systemWindow"]
        })
    readonly property var currentCategory: categories.find(item => item.name === category) || categories[0]
    // The first control on the page shown, for the sidebar's Right and Enter.
    function firstControl(item) {
        if (!item || item.visible === false || item.enabled === false)
            return null;
        if (item.activeFocusOnTab)
            return item;
        for (let i = 0; i < item.children.length; i++) {
            const found = firstControl(item.children[i]);
            if (found)
                return found;
        }
        return null;
    }
    function enterPage() {
        for (let i = 0; i < pages.children.length; i++) {
            const page = pages.children[i];
            if (page.objectName === category) {
                const control = firstControl(page);
                if (control)
                    control.forceActiveFocus(Qt.TabFocusReason);
                return;
            }
        }
    }
    // Opens a page by its name or as typed after `shale settings` ("control-center").
    function showPage(name) {
        const wanted = String(name || "").toLowerCase().replace(/[-_]/g, " ").trim();
        const found = categories.find(item => item.name.toLowerCase() === wanted || (item.aliases || []).indexOf(wanted) >= 0);
        if (found)
            category = found.name;
        else if (wanted !== "")
            ShellState.message("Settings has no page called " + name, "error");
    }
    Component.onCompleted: showPage(ShellState.detail)
    Connections {
        target: ShellState
        function onDetailChanged() {
            if (ShellState.panel === "settings")
                root.showPage(ShellState.detail);
        }
    }
    onCategoryChanged: {
        settingsScroll.contentItem.contentY = 0;
        pageEntrance.restart();
    }
    // For previews of long pages.
    function scrollTo(y) {
        settingsScroll.contentItem.contentY = Math.max(0, Math.min(y, settingsScroll.contentItem.contentHeight - settingsScroll.height));
    }

    // Find a setting. Rows are read from the pages themselves (every row with a name and a description line: toggles,
    // choices and the rest), so whatever a page shows can be found, its own words included.
    readonly property var results: query.trim() === "" ? [] : search(query)
    function collect(item, out) {
        const children = item.children;
        for (let i = 0; i < children.length; i++) {
            const child = children[i];
            // Rows are found on hidden pages too: every page but the open one is hidden, and an item's `visible` can't
            // tell a row hidden on its own (the lock style while hyprlock locks) from one on a hidden page.
            // Hold-to-reset buttons have a description too; they aren't settings.
            if (child.description !== undefined && child.triggered === undefined) {
                const label = child.label !== undefined ? child.label : child.text;
                // A choice is found by its options too: "midnight", "brave".
                const options = Array.isArray(child.model) ? child.model.map(option => option && option.text ? option.text : "").join(" ") : "";
                if (typeof label === "string" && label !== "")
                    out.push({label: label, description: String(child.description || ""), options: options, item: child});
            }
            collect(child, out);
        }
    }
    function search(text) {
        // Either spelling finds a row: the pages say colour and grey.
        const plain = value => value.toLowerCase().replace(/color/g, "colour").replace(/gray/g, "grey");
        const words = plain(text).split(/\s+/).filter(word => word !== "");
        const fits = haystack => words.every(word => plain(haystack).indexOf(word) >= 0);
        // Names that start with what was typed first, then names that hold it, then the rest.
        const rank = label => label.toLowerCase().startsWith(words[0]) ? 0 : label.toLowerCase().indexOf(words[0]) >= 0 ? 1 : 2;
        const found = [];
        const seen = {};
        function add(page, label, description, item) {
            const key = page + "\n" + label.toLowerCase();
            if (seen[key])
                return;
            seen[key] = true;
            found.push({page: page, label: label, description: description, item: item, rank: rank(label) * 1000 + found.length});
        }
        for (const entry of categories) {
            if (fits([entry.name].concat(entry.aliases || [], [entry.description]).join(" ").toLowerCase()))
                add(entry.name, entry.name, entry.description, null);
        }
        for (let i = 0; i < pages.children.length; i++) {
            const page = pages.children[i];
            if (!page.objectName)
                continue;
            const rows = [];
            collect(page, rows);
            for (const row of rows) {
                if (fits(row.label + " " + row.description + " " + row.options + " " + page.objectName))
                    add(page.objectName, row.label, row.description, row.item);
            }
        }
        found.sort((a, b) => a.rank - b.rank);
        return found.slice(0, 40);
    }
    // Opens a result's page and lights its row up once the page has laid out.
    function openResult(result) {
        if (!result)
            return;
        category = result.page;
        flash.opacity = 0;
        revealTimer.target = result.item;
        revealTimer.restart();
    }
    Timer {
        id: revealTimer
        property Item target: null
        interval: 40
        onTriggered: {
            const item = target;
            if (!item || !item.visible || item.height <= 0)
                return;
            const at = item.mapToItem(scrollContent, 0, 0);
            root.scrollTo(at.y - 48);
            flash.x = at.x;
            flash.y = at.y;
            flash.width = item.width;
            flash.height = item.height;
            flashAnimation.restart();
        }
    }
    function focusSearch() {
        searchField.forceActiveFocus();
        searchField.selectAll();
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
            root.focusSearch();
            event.accepted = true;
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: Theme.casePadding

        // Sidebar: title, Find a setting, then the sections (or what Find a setting found).
        ColumnLayout {
            Layout.preferredWidth: root.width < 860 ? 196 : 230
            Layout.fillWidth: false
            Layout.fillHeight: true
            spacing: 2
            C.Label {
                text: "Settings"
                font.pixelSize: 17
                font.weight: 650
                elide: Text.ElideNone
                Layout.leftMargin: 10
                Layout.topMargin: 6
                Layout.bottomMargin: 10
                Accessible.role: Accessible.Heading
            }
            C.Field {
                id: searchField
                focus: true
                Layout.fillWidth: true
                Layout.bottomMargin: 8
                implicitHeight: 34
                leftPadding: 32
                rightPadding: clearSearch.visible ? 34 : 10
                font.pixelSize: Theme.label
                placeholderText: "Find a setting"
                Accessible.name: "Find a setting"
                text: root.query
                onTextEdited: root.query = text
                onAccepted: root.openResult(root.results[0])
                Keys.onEscapePressed: event => {
                    if (text !== "") {
                        root.query = "";
                        event.accepted = true;
                    } else {
                        event.accepted = false;
                    }
                }
                Keys.onDownPressed: {
                    const first = root.query.trim() !== "" ? resultItems.itemAt(0) : navigationItems.itemAt(Math.max(0, root.categories.indexOf(root.currentCategory)));
                    if (first)
                        first.forceActiveFocus(Qt.TabFocusReason);
                }
                C.Icon {
                    anchors.left: parent.left
                    anchors.leftMargin: 11
                    anchors.verticalCenter: parent.verticalCenter
                    name: "search"
                    size: 14
                    color: Theme.textDim
                }
                C.Button {
                    id: clearSearch
                    visible: searchField.text !== ""
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "close"
                    flat: true
                    hint: "Clear"
                    focusPolicy: Qt.NoFocus
                    implicitWidth: 26
                    implicitHeight: 26
                    onClicked: {
                        root.query = "";
                        searchField.forceActiveFocus();
                    }
                }
            }
            Flickable {
                id: navigation
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: root.query.trim() === "" ? sections.implicitHeight : resultList.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                ScrollBar.vertical: C.ScrollBar {}
                ColumnLayout {
                    id: sections
                    visible: root.query.trim() === ""
                    width: navigation.width
                    spacing: 2
                    Repeater {
                        id: navigationItems
                        model: root.categories
                        C.Button {
                            id: section
                            required property var modelData
                            required property int index
                            text: modelData.name
                            selected: root.category === modelData.name
                            Layout.fillWidth: true
                            implicitHeight: Math.max(38, Theme.body + 24)
                            leftPadding: 10
                            rightPadding: 10
                            cornerRadius: Theme.radiusKey
                            Accessible.role: Accessible.PageTab
                            Accessible.selected: selected
                            // One Tab stop for the list: Tab goes from the chosen page's name into the page, and the
                            // arrows, Home and End move between pages.
                            activeFocusOnTab: selected
                            onClicked: root.category = modelData.name
                            Keys.onRightPressed: root.enterPage()
                            Keys.onReturnPressed: root.enterPage()
                            Keys.onEnterPressed: root.enterPage()
                            Keys.onPressed: event => {
                                if (event.key !== Qt.Key_Home && event.key !== Qt.Key_End)
                                    return;
                                const target = navigationItems.itemAt(event.key === Qt.Key_Home ? 0 : root.categories.length - 1);
                                target.forceActiveFocus(Qt.TabFocusReason);
                                root.category = target.modelData.name;
                                event.accepted = true;
                            }
                            Keys.onDownPressed: {
                                const next = navigationItems.itemAt(Math.min(index + 1, root.categories.length - 1));
                                next.forceActiveFocus(Qt.TabFocusReason);
                                root.category = next.modelData.name;
                            }
                            Keys.onUpPressed: {
                                if (index === 0) {
                                    searchField.forceActiveFocus();
                                    return;
                                }
                                const previous = navigationItems.itemAt(index - 1);
                                previous.forceActiveFocus(Qt.TabFocusReason);
                                root.category = previous.modelData.name;
                            }
                            // The chosen section is a raised key with an accent icon; the others light up under the pointer.
                            background: Rectangle {
                                radius: Theme.radiusKey
                                color: section.selected ? Theme.raised : section.hovered || section.visualFocus || section.down ? section.wash : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.fast } }
                                C.Raise {
                                    shown: section.selected
                                }
                            }
                            contentItem: RowLayout {
                                spacing: 10
                                C.Icon {
                                    name: section.modelData.icon
                                    size: 17
                                    color: section.selected ? Theme.accentText : Theme.textSecondary
                                }
                                C.Label {
                                    text: section.text
                                    color: section.selected ? Theme.text : Theme.textSecondary
                                    font.weight: section.selected ? Font.DemiBold : Font.Medium
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }
                ColumnLayout {
                    id: resultList
                    visible: root.query.trim() !== ""
                    width: navigation.width
                    spacing: 2
                    C.Label {
                        visible: root.results.length === 0
                        text: "No setting matches “" + root.query.trim() + "”"
                        color: Theme.textDim
                        font.pixelSize: Theme.label
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        Layout.topMargin: 6
                    }
                    Repeater {
                        id: resultItems
                        model: root.results
                        C.Button {
                            id: result
                            required property var modelData
                            required property int index
                            readonly property string where: modelData.label === modelData.page ? modelData.description : modelData.page
                            text: modelData.label
                            Layout.fillWidth: true
                            implicitHeight: resultText.implicitHeight + 16
                            leftPadding: 10
                            rightPadding: 10
                            cornerRadius: Theme.radiusKey
                            Accessible.description: where
                            onClicked: root.openResult(modelData)
                            Keys.onReturnPressed: root.openResult(modelData)
                            Keys.onEnterPressed: root.openResult(modelData)
                            Keys.onDownPressed: {
                                const next = resultItems.itemAt(index + 1);
                                if (next)
                                    next.forceActiveFocus(Qt.TabFocusReason);
                            }
                            Keys.onUpPressed: {
                                const previous = resultItems.itemAt(index - 1);
                                if (previous)
                                    previous.forceActiveFocus(Qt.TabFocusReason);
                                else
                                    searchField.forceActiveFocus();
                            }
                            onActiveFocusChanged: if (activeFocus) {
                                if (y < navigation.contentY)
                                    navigation.contentY = y;
                                else if (y + height > navigation.contentY + navigation.height)
                                    navigation.contentY = y + height - navigation.height;
                            }
                            background: Rectangle {
                                radius: Theme.radiusKey
                                color: result.hovered || result.visualFocus || result.down ? result.wash : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.fast } }
                            }
                            contentItem: ColumnLayout {
                                id: resultText
                                spacing: 1
                                C.Label {
                                    text: result.text
                                    font.weight: Font.Medium
                                    Layout.fillWidth: true
                                }
                                C.Label {
                                    visible: text !== ""
                                    text: result.where
                                    color: Theme.textDim
                                    font.pixelSize: Theme.small
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }
            }
        }

        // The page: its title and a line about it, then its groups, scrolling under the title.
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusModule
            color: Theme.moduleAlt
            clip: true
            ColumnLayout {
                id: pageHeader
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                anchors.topMargin: 22
                spacing: 4
                C.Label {
                    text: root.category
                    font.pixelSize: Math.max(22, Theme.body + 8)
                    font.weight: 650
                    Layout.fillWidth: true
                    Accessible.role: Accessible.Heading
                }
                C.Label {
                    text: root.currentCategory.description
                    color: Theme.textDim
                    font.pixelSize: Theme.label
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
            ScrollView {
                id: settingsScroll
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: pageHeader.bottom
                anchors.bottom: parent.bottom
                anchors.leftMargin: 24
                anchors.topMargin: 12
                contentWidth: availableWidth
                clip: true
                opacity: root.pageProgress
                ScrollBar.vertical: C.ScrollBar {
                    parent: settingsScroll
                    x: settingsScroll.width - width - 8
                    y: settingsScroll.topPadding
                    height: settingsScroll.availableHeight - 8
                }
                Item {
                    id: scrollContent
                    width: settingsScroll.availableWidth - 24
                    implicitHeight: pages.implicitHeight + 22
                    transform: Translate { y: (1 - root.pageProgress) * Theme.panelRise * 0.75 }
                    C.FocusScroller {
                        flickable: settingsScroll.contentItem
                        content: scrollContent
                    }
                    ColumnLayout {
                        id: pages
                        width: parent.width
                        spacing: Theme.gapM

                        // Appearance: colour, size, behaviour, wallpaper and lock screen.
                        AppearanceSettings {
                            objectName: "Appearance"
                            visible: root.category === objectName
                            Layout.fillWidth: true
                        }

                        DisplaySettings {
                            objectName: "Displays"
                            visible: root.category === objectName
                            Layout.fillWidth: true
                        }
                        BarSettings {
                            objectName: "Bar"
                            visible: root.category === objectName
                            Layout.fillWidth: true
                        }
                        ControlSettings {
                            objectName: "Control"
                            visible: root.category === objectName
                            Layout.fillWidth: true
                        }
                        DesktopSettings {
                            objectName: "Desktop"
                            visible: root.category === objectName
                            Layout.fillWidth: true
                        }
                        ShortcutSettings {
                            objectName: "Shortcuts"
                            visible: root.category === objectName
                            Layout.fillWidth: true
                        }

                        // General: time and units, search and the terminal, updates.
                        GeneralSettings {
                            objectName: "General"
                            visible: root.category === objectName
                            Layout.fillWidth: true
                        }

                        // Notifications: history and focus sessions.
                        NotificationSettings {
                            objectName: "Notifications"
                            visible: root.category === objectName
                            Layout.fillWidth: true
                        }

                        // Sound: volume limits, the player's time and the equalizer.
                        SoundSettings {
                            objectName: "Sound"
                            visible: root.category === objectName
                            Layout.fillWidth: true
                        }

                        // Power: the power mode, the lid and the refresh rate in power saver. Control → Power has the battery.
                        PowerSettings {
                            objectName: "Power"
                            visible: root.category === objectName
                            Layout.fillWidth: true
                        }

                        // Capture: recording sound, delay and folders.
                        CaptureSettings {
                            objectName: "Capture"
                            visible: root.category === objectName
                            Layout.fillWidth: true
                        }

                        // AirDrop: how it receives, this computer's name and the senders let in, and a check.
                        AirDropSettings {
                            objectName: "AirDrop"
                            visible: root.category === objectName
                            Layout.fillWidth: true
                        }

                        // Activity: recording on or off, and the panel.
                        ActivitySettings {
                            objectName: "Activity"
                            visible: root.category === objectName
                            Layout.fillWidth: true
                        }

                        BackupSettings {
                            objectName: "Backup"
                            visible: root.category === objectName
                            Layout.fillWidth: true
                        }

                        // Diagnostics: the helper, the version, the commands Shale uses and the system monitor.
                        DiagnosticsSettings {
                            objectName: "Diagnostics"
                            visible: root.category === objectName
                            Layout.fillWidth: true
                            version: root.version
                        }

                        C.ResetButton {
                            visible: !!root.resetKeys[root.category]
                            Layout.topMargin: Theme.gapS
                            description: "Hold to put this page back to how Shale comes"
                            onConfirmed: {
                                const page = root.category;
                                ShellState.resetSettings(root.resetKeys[page], () => ShellState.message(page + " settings reset", "success", {label: "Undo", run: () => ShellState.restoreSettings()}));
                            }
                        }
                    }
                    // Lights up the row a search result opened, then fades.
                    Rectangle {
                        id: flash
                        opacity: 0
                        radius: Theme.radiusCard + 2
                        color: Theme.accentSoft
                        border.width: 1
                        border.color: Theme.accentLine
                        SequentialAnimation {
                            id: flashAnimation
                            NumberAnimation { target: flash; property: "opacity"; to: 1; duration: Theme.fast }
                            PauseAnimation { duration: 900 }
                            NumberAnimation { target: flash; property: "opacity"; to: 0; duration: Theme.reduced ? 0 : Theme.lowPower ? 200 : 500 }
                        }
                    }
                }
            }
            C.EdgeFade {
                anchors.left: settingsScroll.left
                anchors.right: settingsScroll.right
                anchors.bottom: settingsScroll.bottom
                flickable: settingsScroll.contentItem
                tone: Theme.moduleAlt
            }
        }
    }
}
