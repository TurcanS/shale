import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../core"
import "../components" as C

FocusScope {
    id: root
    property var entries: []
    readonly property var activeWallpapers: ShellState.activeWallpapers
    property bool localLoading: false
    property bool onlineLoading: false
    property string sourceMode: "local"
    property bool switchingSource: false
    property string localQuery: ""
    property var sourceStates: ({})
    property var onlineEntries: []
    property int onlinePage: 0
    property int onlineGeneration: 0
    property bool hasMore: false
    readonly property bool online: sourceMode !== "local"
    readonly property string sourceName: sourceMode === "wallpaperscom" ? "Wallpapers.com" : "Wallhaven"
    readonly property bool loading: online ? onlineLoading : localLoading
    readonly property bool applying: ShellState.wallpaperBusy || ShellState.wallpaperDownloading
    property string error: ""
    property string directory: ""
    // The helper lists at most 500 local wallpapers; set to that count when it stopped short.
    property int listedCount: 0
    property int selected: 0
    property int generation: 0
    readonly property var filtered: online ? onlineEntries : entries.filter(e => (e.name + " " + e.file).toLowerCase().indexOf(search.text.toLowerCase().trim()) >= 0)
    readonly property var current: selected >= 0 && selected < filtered.length ? filtered[selected] : null
    readonly property string monitor: ShellState.screenName || ShellState.targetScreen()
    readonly property string activePath: activeWallpapers[monitor] || ""
    readonly property bool isCurrent: !!current && !!current.path && current.path === activePath
    IpcHandler {
        target: "wallpaper-picker"
        function status(): string {
            return JSON.stringify({count: root.filtered.length, selected: root.selected, path: root.current ? root.current.path : "", activePath: root.activePath, monitor: root.monitor, busy: root.applying, transitionMs: Theme.enter, loading: root.loading, error: ShellState.wallpaperError || root.error});
        }
        function select(index: int): void {
            if (!root.applying) root.selected = Math.max(0, Math.min(root.filtered.length - 1, index));
        }
        function apply(): void { root.apply(); }
    }
    function switchSourceWithTab() {
        if (applying) return;
        if (sourceMode === "wallhaven") {
            chooseSource("wallpaperscom");
        } else if (sourceMode === "wallpaperscom") {
            chooseSource("local");
        } else {
            // Preserve the original shortcut to Wallhaven's popular feed.
            const states = Object.assign({}, sourceStates);
            delete states.wallhaven;
            sourceStates = states;
            chooseSource("wallhaven");
        }
        root.forceActiveFocus();
    }
    Shortcut {
        sequence: "Tab"
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.visible && ShellState.panel === "wallpaper"
        onActivated: root.switchSourceWithTab()
    }
    function chooseSource(mode) {
        if (sourceMode === mode || applying) return;
        if (online) {
            const states = Object.assign({}, sourceStates);
            states[sourceMode] = {query: search.text, entries: onlineEntries,
                page: onlinePage, hasMore: hasMore, selected: selected, error: error};
            sourceStates = states;
        }
        else localQuery = search.text;
        ++onlineGeneration;
        onlineLoading = false;
        onlineDebounce.stop();
        switchingSource = true;
        sourceMode = mode;
        const state = sourceStates[mode];
        onlineEntries = state ? state.entries : [];
        onlinePage = state ? state.page : 0;
        hasMore = state ? state.hasMore : false;
        search.text = online ? (state ? state.query : "") : localQuery;
        switchingSource = false;
        selected = state ? state.selected : 0;
        error = state ? state.error : "";
        ShellState.wallpaperError = "";
        if (online && !onlineEntries.length) searchOnline(false);
    }
    function searchOnline(append) {
        if (!online || (append && (!hasMore || onlineLoading))) return;
        if (!Backend.ready) {
            onlineLoading = false;
            error = "Wallpaper service is reconnecting…";
            return;
        }
        onlineDebounce.stop();
        const request = ++onlineGeneration;
        const page = append ? onlinePage + 1 : 1;
        onlineLoading = true;
        error = "";
        Backend.request(sourceMode + ".search", {query: search.text.trim(), page: page}, (result, failure) => {
            if (request !== onlineGeneration) return;
            onlineLoading = false;
            if (failure) { error = failure.message; return; }
            error = result.warning || "";
            const position = selected;
            onlineEntries = append ? onlineEntries.concat(result.entries.filter(item => !onlineEntries.some(old => old.id === item.id))) : result.entries;
            onlinePage = result.page;
            hasMore = result.hasMore;
            selected = append ? position : 0;
        });
    }
    function refresh() {
        if (!Backend.ready) return;
        const request = ++generation;
        localLoading = true;
        if (!online) error = "";
        Backend.request("wallpaper.list", {}, (r, e) => {
            if (request !== generation) return;
            localLoading = false;
            if (e) { if (!online) error = e.message; return; }
            const previous = root.current ? root.current.path : "";
            entries = r.entries;
            directory = r.directory;
            listedCount = r.limited === true ? r.entries.length : 0;
            ShellState.activeWallpapers = r.active || {};
            if (!online) error = r.warning || "";
            if (!online) {
                const preferred = filtered.findIndex(item => item.path === (previous || activePath));
                selected = Math.max(0, preferred);
            }
        });
    }
    function move(delta) {
        if (filtered.length && !applying)
            selected = Math.max(0, Math.min(filtered.length - 1, selected + delta));
    }
    function apply() {
        if (current && !isCurrent && !applying)
            ShellState.applyWallpaper(current, activePath);
    }
    Component.onCompleted: refresh()
    Connections {
        target: Backend
        function onReadyChanged() {
            if (Backend.ready) {
                root.refresh();
                if (root.online) root.searchOnline(false);
            }
        }
    }
    Connections {
        target: ShellState
        function onWallpaperSaved(entry) {
            const markSaved = item => (item.provider || "wallhaven") === (entry.provider || "wallhaven") && item.id === entry.id ? Object.assign({}, item, {path: entry.path}) : item;
            root.onlineEntries = root.onlineEntries.map(markSaved);
            const states = Object.assign({}, root.sourceStates);
            for (const provider of Object.keys(states))
                states[provider] = Object.assign({}, states[provider], {entries: states[provider].entries.map(markSaved)});
            root.sourceStates = states;
            if (!root.entries.some(item => item.path === entry.path))
                root.entries = root.entries.concat([Object.assign({}, entry, {remote: false})]);
        }
    }
    onFilteredChanged: selected = Math.max(0, Math.min(selected, filtered.length - 1))
    onSelectedChanged: if (!applying) ShellState.wallpaperError = ""
    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.sectionSpacing
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(root.width, 680)
            Layout.preferredHeight: 142
            color: Theme.panel
            radius: Theme.panelRadius
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    C.Icon { name: "palette"; size: 18 }
                    C.Label { text: "Wallpapers"; font.weight: Font.DemiBold; font.pixelSize: 15; Layout.fillWidth: true }
                    C.Label {
                        visible: root.loading && root.filtered.length > 0
                        text: "Updating…"
                        color: Theme.muted
                        font.pixelSize: Theme.caption
                    }
                    C.Button { glyph: "close"; flat: true; hint: "Close"; implicitHeight: 30; onClicked: ShellState.close() }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    C.Button { Layout.fillWidth: true; Layout.preferredWidth: 1; text: "My wallpapers"; selected: !root.online; enabled: !root.applying; implicitHeight: 30; onClicked: root.chooseSource("local") }
                    C.Button { Layout.fillWidth: true; Layout.preferredWidth: 1; text: "Wallhaven"; selected: root.sourceMode === "wallhaven"; enabled: !root.applying; implicitHeight: 30; onClicked: root.chooseSource("wallhaven") }
                    C.Button { Layout.fillWidth: true; Layout.preferredWidth: 1; text: "Wallpapers.com"; selected: root.sourceMode === "wallpaperscom"; enabled: !root.applying; implicitHeight: 30; onClicked: root.chooseSource("wallpaperscom") }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    C.Field {
                        id: search
                        Layout.fillWidth: true
                        implicitHeight: 40
                        enabled: !root.applying
                        placeholderText: root.online ? "Search " + root.sourceName + "…" : "Search your wallpapers…"
                        onTextChanged: {
                            if (root.switchingSource) return;
                            root.selected = 0;
                            if (root.online) {
                                ++root.onlineGeneration;
                                root.onlineEntries = [];
                                root.onlinePage = 0;
                                root.hasMore = false;
                                root.onlineLoading = true;
                                onlineDebounce.restart();
                            }
                        }
                        Keys.onDownPressed: root.move(1)
                        Keys.onUpPressed: root.move(-1)
                        onAccepted: root.online ? root.searchOnline(false) : root.apply()
                    }
                    C.Button {
                        glyph: root.online ? "search" : "refresh"
                        flat: true
                        hint: root.online ? "Search " + root.sourceName : "Refresh wallpapers"
                        enabled: !root.applying && !root.loading
                        onClicked: root.online ? root.searchOnline(false) : root.refresh()
                    }
                }
            }
        }
        Item {
            id: gallery
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            readonly property real cardWidth: Math.min(510, width * (width < 650 ? 0.72 : 0.49))
            readonly property real cardHeight: Math.max(0, Math.min(320, height - 24))
            Repeater {
                model: root.filtered
                Item {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property int distance: index - root.selected
                    width: gallery.cardWidth
                    height: gallery.cardHeight
                    x: (gallery.width - width) / 2 + distance * width * 0.94
                    y: (gallery.height - height) / 2 + (distance === 0 ? 0 : 10)
                    scale: distance === 0 ? 1 : 0.83
                    opacity: Math.abs(distance) > 2 ? 0 : distance === 0 ? 1 : 0.76
                    visible: opacity > 0.001
                    z: 10 - Math.abs(distance)
                    Behavior on x { NumberAnimation { duration: Math.min(Theme.enter, 170); easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: Math.min(Theme.enter, 170); easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: Math.min(Theme.enter, 170); easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                    transform: Matrix4x4 {
                        matrix: Qt.matrix4x4(1, -0.10, 0, tile.height * 0.05, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: Theme.surface
                        border.width: 2
                        border.color: tile.distance === 0 ? Theme.accent : Theme.border
                        Behavior on border.color { ColorAnimation { duration: Theme.fast } }
                        radius: 5
                        clip: true
                        Image {
                            id: thumbnail
                            anchors.fill: parent
                            anchors.margins: 2
                            source: Math.abs(tile.distance) <= 3 ? tile.modelData.url : ""
                            asynchronous: true
                            sourceSize.width: 760
                            cache: true
                            sourceSize.height: 480
                            fillMode: Image.PreserveAspectCrop
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.enter } }
                        }
                        C.Icon {
                            anchors.centerIn: parent
                            name: "palette"
                            size: 36
                            opacity: 0.4
                            visible: thumbnail.status !== Image.Ready
                        }
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 2
                            x: 2
                            width: parent.width - 4
                            height: tile.distance === 0 ? 2 : 0
                            color: Theme.accent
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: !root.applying
                            onClicked: { root.selected = tile.index; root.forceActiveFocus(); }
                            onDoubleClicked: { root.selected = tile.index; root.apply(); }
                        }
                    }
                }
            }
            WheelHandler {
                property double lastMove: 0
                onWheel: event => {
                    if (Date.now() - lastMove > 85 && event.angleDelta.y !== 0) {
                        root.move(event.angleDelta.y < 0 ? 1 : -1);
                        lastMove = Date.now();
                    }
                }
            }
            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width - 40, 440)
                height: 190
                radius: Theme.panelRadius
                color: Theme.panel
                visible: !root.filtered.length
                C.EmptyState {
                    anchors.centerIn: parent
                    width: parent.width - 40
                    glyph: "palette"
                    title: root.loading ? "Finding wallpapers…" : root.error && root.online ? "Could not load wallpapers" : search.text ? "No matches" : "Your collection starts here"
                    description: root.loading ? (root.online ? root.sourceName : "Local collection") : root.error && root.online ? "" : search.text ? "No wallpapers match “" + search.text + "”" : root.online ? root.sourceName : (root.directory || "~/Pictures/Wallpapers")
                }
            }
        }
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(root.width, 680)
            Layout.preferredHeight: footer.implicitHeight + 28
            color: Theme.panel
            radius: Theme.panelRadius
            ColumnLayout {
                id: footer
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 10
                RowLayout {
                    Layout.fillWidth: true
                    C.Button { glyph: "back"; hint: "Previous wallpaper"; enabled: root.selected > 0 && !root.applying; onClicked: root.move(-1) }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        C.Label { text: root.current ? root.current.name : "No wallpaper selected"; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                        C.Label {
                            text: root.current ? (root.selected + 1) + " / " + root.filtered.length + (root.current.resolution ? " · " + root.current.resolution : "") + (root.online ? (root.current.path ? " · Saved locally" : " · Online") : "") : root.online ? root.sourceName : "Local collection"
                            color: Theme.muted; font.pixelSize: Theme.small; Layout.fillWidth: true; elide: Text.ElideRight
                        }
                    }
                    C.Button { glyph: "chevron"; hint: "Next wallpaper"; enabled: root.selected < root.filtered.length - 1 && !root.applying; onClicked: root.move(1) }
                    C.Button {
                        text: ShellState.wallpaperDownloading ? "Saving…" : ShellState.wallpaperBusy ? "Applying…" : root.isCurrent ? "Applied" : root.current && root.current.remote && !root.current.path ? "Save & apply" : "Apply"
                        accent: !!root.current && !root.isCurrent
                        enabled: !!root.current && !root.isCurrent && !root.applying
                        onClicked: root.apply()
                    }
                }
                C.Label {
                    visible: (ShellState.wallpaperError || root.error) !== ""
                    text: ShellState.wallpaperError || root.error
                    color: ShellState.wallpaperError ? Theme.danger : Theme.warning; wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
                RowLayout {
                    Layout.fillWidth: true
                    C.Label {
                        text: !root.online && root.listedCount > 0 ? "Showing the first " + root.listedCount + " wallpapers" : ""
                        color: Theme.muted
                        font.pixelSize: Theme.small
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    C.Button {
                        visible: root.sourceMode === "wallpaperscom"
                        text: "Wallpapers.com ↗"
                        flat: true
                        onClicked: Qt.openUrlExternally(root.current && root.current.creditUrl ? root.current.creditUrl : "https://wallpapers.com/")
                    }
                    C.Button {
                        visible: root.online && root.error !== ""
                        text: "My wallpapers"
                        flat: true
                        enabled: !root.applying
                        onClicked: root.chooseSource("local")
                    }
                    C.Button {
                        visible: root.online && root.error !== ""
                        text: "Retry"
                        flat: true
                        enabled: !root.onlineLoading && !root.applying
                        onClicked: root.searchOnline(false)
                    }
                    C.Button {
                        visible: root.online && root.hasMore
                        text: root.onlineLoading ? "Loading…" : "Load more"
                        enabled: !root.onlineLoading && !root.applying
                        flat: true
                        onClicked: root.searchOnline(true)
                    }
                    C.Button { visible: !root.online; text: "Open folder"; glyph: "grid"; flat: true; enabled: root.directory !== ""; onClicked: Qt.openUrlExternally("file://" + root.directory.split("/").map(encodeURIComponent).join("/")) }
                }
            }
        }
    }
    Timer {
        id: onlineDebounce
        interval: 500
        onTriggered: root.searchOnline(false)
    }
    Keys.onLeftPressed: move(-1)
    Keys.onRightPressed: move(1)
    Keys.onReturnPressed: apply()
}
