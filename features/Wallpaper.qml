import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../core"
import "../core/palette.js" as Palette
import "../components" as C

// Wallpapers, as a crate: no case, just the wallpapers as leaning slices over the desktop, the chosen one large and
// ringed in the accent it would give the shell, its neighbours narrowing away to each side. A small case above holds
// the source and search; the transport below steps, shows the name and colours, and applies. Left and Right step,
// Up and Down jump five, Home and End go to the ends, Enter uses the chosen one, the wheel flips through.
FocusScope {
    id: root
    readonly property string title: "Wallpapers"
    readonly property bool showHeader: false
    readonly property bool chromeless: true
    readonly property int panelWidth: 1440
    readonly property int panelHeight: 600
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
        }, {owner: root});
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
        }, {owner: root});
    }
    // A local copy the colour reader can open: the small cached copy, or the file itself.
    function localImage(entry) {
        if (!entry)
            return "";
        if (entry.thumb)
            return entry.thumb;
        return /^file:\/\//.test(entry.url || "") ? entry.url : "";
    }
    // The accent and second colour a wallpaper gives the shell (see Theme.second), its deepest tone, and the surface.
    function swatches(colors) {
        const accent = Palette.accentFrom(colors);
        if (accent === "")
            return [];
        const color = Qt.darker(accent, 1);
        const second = color.hslSaturation < 0.05 ? Theme.textSecondary : Palette.inGamut(0.75, 0.06, Palette.oklch(color).h + 2.6);
        let deep = colors[0];
        for (let i = 1; i < colors.length; i++)
            if (Palette.luminance(colors[i]) < Palette.luminance(deep))
                deep = colors[i];
        return [{role: "Accent", color: color}, {role: "Second", color: second}, {role: "Surface", color: Theme.module}, {role: "Deepest", color: deep}];
    }
    readonly property var currentSwatches: previewColors.item ? swatches(previewColors.item.colors) : []
    readonly property color previewAccent: currentSwatches.length ? currentSwatches[0].color : Theme.accent
    LazyLoader {
        id: previewColors
        active: root.localImage(root.current) !== ""
        ColorQuantizer {
            source: root.localImage(root.current)
            depth: 3
            rescaleSize: 64
        }
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
    onFilteredChanged: {
        selected = Math.max(0, Math.min(selected, filtered.length - 1));
        place(false);
    }
    // Where the crate is, in wallpapers: it follows `selected` smoothly, and every slice's place, size and shade is
    // worked out from it. One moving value keeps the slices packed however fast the wheel turns; giving each slice
    // its own animation left them chasing their places and the middle empty.
    property real position: 0
    property bool sliding: true
    Behavior on position {
        enabled: root.sliding && !Theme.reduced
        SmoothedAnimation {
            duration: Theme.slide
            velocity: -1
        }
    }
    // Moves the crate to `selected`, sliding or at once (a new list, or the first placing on opening).
    function place(animated) {
        sliding = animated;
        position = selected;
        sliding = true;
    }
    onSelectedChanged: {
        place(!dealing);
        if (!applying)
            ShellState.wallpaperError = "";
        // Online results load the next page as the crate nears its end.
        if (online && hasMore && !onlineLoading && selected >= filtered.length - 4)
            searchOnline(true);
    }
    // The crate's shape: the chosen card (16:10) and the slivers beside it, each a little narrower than the last.
    readonly property real lean: 0.12
    readonly property int sliceGap: 10
    readonly property real cardHeight: Math.max(120, Math.min(400, gallery.height - 48))
    readonly property real cardWidth: Math.round(cardHeight * 1.6)
    function sliver(n) {
        return Math.max(30, cardWidth * 0.2 * Math.pow(0.82, n - 1));
    }
    // A slice's width at a distance (in wallpapers, fractions included) from the crate's position.
    function sliceWidth(reach) {
        if (reach < 1)
            return cardWidth + (sliver(1) - cardWidth) * reach;
        const n = Math.floor(reach);
        return sliver(n) + (sliver(n + 1) - sliver(n)) * (reach - n);
    }
    // The same for a slice's centre: between the whole-step places.
    function slicePlace(distance) {
        const n = Math.floor(distance);
        return sliceOffset(n) + (sliceOffset(n + 1) - sliceOffset(n)) * (distance - n);
    }
    // A slice's centre, from the gallery's centre, at a signed distance from the chosen card.
    function sliceOffset(distance) {
        const n = Math.abs(distance);
        if (n === 0)
            return 0;
        let x = cardWidth / 2 + sliceGap;
        for (let i = 1; i < n; i++)
            x += sliver(i) + sliceGap;
        x += sliver(n) / 2;
        return distance < 0 ? -x : x;
    }
    // True for a moment after opening: slices made now are dealt out from the centre; later ones just appear.
    property bool dealing: true
    Timer {
        interval: 400
        running: true
        onTriggered: root.dealing = false
    }
    // A soft dark pool behind the crate, fading to nothing before the edges, so the slices read over busy windows
    // without a case around them.
    Item {
        anchors.centerIn: parent
        width: parent.width
        height: parent.width
        transform: Scale {
            origin.x: root.width / 2
            origin.y: root.width / 2
            yScale: root.height / Math.max(1, root.width)
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 0
                strokeColor: "transparent"
                fillGradient: RadialGradient {
                    centerX: root.width / 2
                    centerY: root.width / 2
                    centerRadius: root.width / 2
                    focalX: centerX
                    focalY: centerY
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.62) }
                    GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.42) }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0) }
                }
                PathRectangle {
                    width: root.width
                    height: root.width
                }
            }
        }
    }
    // Source and search, in a small case above the crate.
    Rectangle {
        id: topBar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: topRow.implicitWidth + 16
        height: 48
        radius: 18
        color: Theme.caseColor
        border.width: 1
        border.color: Theme.hairline
        RowLayout {
            id: topRow
            anchors.centerIn: parent
            spacing: Theme.gapS
            C.Segmented {
                fill: false
                segmentHeight: 32
                trackColor: Theme.module
                enabled: !root.applying
                model: [{key: "local", text: "Local", hint: "Your wallpaper folder"}, {key: "wallhaven", text: "Wallhaven"}, {key: "wallpaperscom", text: "Wallpapers.com"}]
                current: root.sourceMode
                onActivated: key => root.chooseSource(key)
            }
            C.Field {
                id: search
                Layout.preferredWidth: 220
                implicitHeight: 32
                leftPadding: 32
                font.pixelSize: 13
                enabled: !root.applying
                placeholderText: root.online ? "Search " + root.sourceName : "Search"
                Accessible.name: "Search wallpapers"
                C.Icon {
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    name: "search"
                    size: 14
                    color: Theme.textDim
                }
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
                Keys.onDownPressed: root.move(5)
                Keys.onUpPressed: root.move(-5)
                onAccepted: root.online ? root.searchOnline(false) : root.apply()
            }
            C.Button {
                glyph: root.online ? "search" : "refresh"
                flat: true
                implicitWidth: 32
                implicitHeight: 32
                hint: root.online ? "Search " + root.sourceName : "Refresh wallpapers"
                enabled: !root.applying && !root.loading
                onClicked: root.online ? root.searchOnline(false) : root.refresh()
            }
            C.Button {
                glyph: "close"
                flat: true
                implicitWidth: 32
                implicitHeight: 32
                hint: "Close · Escape"
                onClicked: ShellState.close()
            }
        }
    }
    // The crate: one slice per wallpaper, leaning like records in a box. Only the nearest few are drawn.
    Item {
        id: gallery
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topBar.bottom
        anchors.bottom: transport.top
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        property real wheel: 0
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: wheel => {
                gallery.wheel += wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : -wheel.angleDelta.x;
                if (Math.abs(gallery.wheel) >= 120) {
                    root.move(gallery.wheel > 0 ? -1 : 1);
                    gallery.wheel = 0;
                }
            }
        }
        Repeater {
            model: root.filtered
            Item {
                id: tile
                required property var modelData
                required property int index
                // Signed distance from the crate's position, fractions included while it moves.
                readonly property real distance: index - root.position
                readonly property real reach: Math.abs(distance)
                // 1 for the card in the middle, falling to 0 a step away: the ring, glow and large details follow it.
                readonly property real lead: Math.max(0, 1 - reach * 1.5)
                readonly property bool chosen: index === root.selected
                readonly property bool near: reach <= 8.5
                readonly property bool inUse: !!modelData.path && modelData.path === root.activePath
                // 0.88 → 1 while the slice opens out from the centre on opening, like a panel's 8 px rise: a short
                // spread with a fade, not a long throw.
                property real dealt: 1
                readonly property real dealFade: (dealt - 0.88) / 0.12
                visible: near
                width: root.sliceWidth(reach)
                height: root.cardHeight * (1 - 0.05 * Math.min(reach, 5))
                x: gallery.width / 2 + root.slicePlace(distance) * dealt - width / 2
                y: (gallery.height - height) / 2
                z: 100 - reach
                // Solid up close (they darken instead), fading out only at the crate's far ends.
                opacity: (reach <= 6 ? 1 : Math.max(0, 1 - (reach - 6) * 0.45)) * dealFade
                NumberAnimation {
                    id: deal
                    target: tile
                    property: "dealt"
                    from: 0.88
                    to: 1
                    duration: Theme.panelEnter
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.easeOut
                }
                Timer {
                    id: dealDelay
                    interval: tile.reach * (Theme.lowPower ? 6 : 12)
                    onTriggered: deal.start()
                }
                Component.onCompleted: if (root.dealing && tile.near && !Theme.reduced) {
                    tile.dealt = 0.88;
                    dealDelay.start();
                }
                // Leaning like "/": the top slides right, the bottom left, around the middle.
                transform: Matrix4x4 {
                    matrix: Qt.matrix4x4(1, -root.lean, 0, tile.height * root.lean / 2, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                }
                // The chosen card glows in the accent this wallpaper would give the shell.
                RectangularShadow {
                    anchors.fill: face
                    visible: tile.lead > 0 && !Theme.lowPower
                    opacity: tile.lead
                    radius: face.radius
                    blur: 56
                    offset.y: 16
                    color: Theme.tint(root.previewAccent, 0.4)
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                }
                Rectangle {
                    anchors.fill: face
                    anchors.margins: -4
                    visible: tile.lead > 0
                    opacity: tile.lead
                    radius: face.radius + 4
                    color: "transparent"
                    border.width: 2
                    border.color: root.previewAccent
                    Behavior on border.color { ColorAnimation { duration: Theme.fast } }
                }
                ClippingRectangle {
                    id: face
                    anchors.fill: parent
                    radius: 10 + 6 * tile.lead
                    color: Theme.module
                    Image {
                        id: thumbnail
                        // A local wallpaper's small copy once it exists (see wallpaper.catalog). The first time,
                        // the original is decoded and the result saved as that copy, so later opens skip the decode.
                        property bool copyBroken: false
                        property bool copySaved: false
                        readonly property string original: tile.modelData.url
                        // Slivers show a strip from the middle of the picture, at the chosen card's size.
                        anchors.centerIn: parent
                        width: root.cardWidth
                        height: parent.height
                        source: !tile.near ? "" : tile.modelData.thumb && !copyBroken ? tile.modelData.thumb : original
                        asynchronous: true
                        sourceSize.width: 760
                        sourceSize.height: 480
                        cache: true
                        fillMode: Image.PreserveAspectCrop
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                        function saveCopy() {
                            const path = tile.modelData.thumbPath;
                            if (copySaved || !path || status !== Image.Ready || source.toString() !== original || width <= 0)
                                return;
                            copySaved = grabToImage(result => result.saveToFile(path), Qt.size(760, Math.round(760 * height / width)));
                        }
                        onStatusChanged: {
                            if (status === Image.Error && tile.modelData.thumb && !copyBroken)
                                copyBroken = true;
                            else
                                saveCopy();
                        }
                    }
                    C.Icon {
                        anchors.centerIn: parent
                        visible: thumbnail.status !== Image.Ready
                        name: "palette"
                        size: tile.lead > 0.5 ? 32 : 16
                        color: Theme.textFaint
                    }
                    // Slivers sink back the further they are from the chosen card.
                    Rectangle {
                        anchors.fill: parent
                        color: "black"
                        opacity: tile.reach < 1 ? 0.24 * tile.reach : Math.min(0.6, 0.18 + 0.06 * tile.reach)
                    }
                    // Applying: the card dims under a note until the new wallpaper is up.
                    Rectangle {
                        anchors.fill: parent
                        visible: tile.chosen && root.applying
                        color: Qt.rgba(0, 0, 0, 0.45)
                        C.Label {
                            anchors.centerIn: parent
                            text: ShellState.wallpaperDownloading ? "Saving…" : "Applying…"
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }
                    }
                    Rectangle {
                        visible: tile.inUse && tile.lead > 0.5
                        x: 16
                        y: 14
                        implicitWidth: inUseLabel.implicitWidth + 16
                        implicitHeight: 22
                        radius: 11
                        color: Theme.tint(Theme.caseColor, 0.85)
                        C.Label {
                            id: inUseLabel
                            anchors.centerIn: parent
                            text: "In use"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }
                }
                // The wallpaper in use, among the slivers: a lit dot at the foot of its slice.
                Rectangle {
                    visible: tile.inUse && tile.lead <= 0.5
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 10
                    width: 8
                    height: 8
                    radius: 4
                    color: Theme.accent
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !root.applying
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.selected = tile.index; root.forceActiveFocus(); }
                    onDoubleClicked: { root.selected = tile.index; root.apply(); }
                }
                Accessible.role: Accessible.Button
                Accessible.name: tile.modelData.name + (tile.inUse ? ", in use" : "")
            }
        }
        C.EmptyState {
            visible: !root.current
            anchors.centerIn: parent
            width: Math.min(420, parent.width - 60)
            glyph: "palette"
            title: root.loading ? "Finding wallpapers…" : root.error && root.online ? "Could not load wallpapers" : search.text ? "No matches" : "Your collection starts here"
            description: root.loading ? (root.online ? root.sourceName : "Local collection") : root.error && root.online ? "" : search.text ? "No wallpapers match “" + search.text + "”" : root.online ? root.sourceName : (root.directory || "~/Pictures/Wallpapers")
        }
    }
    // The transport: step, the chosen wallpaper and its colours, use it. A line along the foot shows where you are
    // in the crate, lit in the colour the wallpaper gives.
    Rectangle {
        id: transport
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: Math.min(parent.width, 820)
        height: 64
        radius: 22
        color: Theme.caseColor
        border.width: 1
        border.color: Theme.hairline
        clip: true
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10
            C.Button {
                glyph: "back"
                implicitWidth: 44
                implicitHeight: 44
                hint: "Previous · Left"
                enabled: root.selected > 0 && !root.applying
                onClicked: root.move(-1)
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0
                C.Label {
                    text: root.current ? root.current.name : root.online ? root.sourceName : "Wallpapers"
                    font.pixelSize: 15
                    font.weight: 650
                    Layout.fillWidth: true
                }
                C.Label {
                    readonly property string problem: ShellState.wallpaperError || root.error
                    text: {
                        if (problem)
                            return problem;
                        if (!root.current)
                            return root.online ? root.sourceName : "Local collection";
                        const parts = root.online ? [root.current.resolution, root.current.path ? "Saved locally" : root.sourceName] : [root.current.file];
                        const where = (root.selected + 1) + " of " + root.filtered.length + (root.loading ? " · updating…" : "");
                        const note = !root.online && root.listedCount > 0 ? "the first " + root.listedCount + " shown" : "";
                        return parts.concat([where, note]).filter(part => !!part).join(" · ");
                    }
                    color: ShellState.wallpaperError ? Theme.dangerText : root.error ? Theme.warning : Theme.textDim
                    font.pixelSize: 12
                    font.features: ({"tnum": 1})
                    Layout.fillWidth: true
                }
            }
            Repeater {
                model: root.currentSwatches
                Rectangle {
                    required property var modelData
                    implicitWidth: 14
                    implicitHeight: 14
                    radius: 7
                    color: modelData.color
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                    Accessible.role: Accessible.StaticText
                    Accessible.name: modelData.role + " " + Palette.hex(modelData.color)
                }
            }
            C.Button {
                visible: !root.online
                glyph: "folder"
                flat: true
                implicitWidth: 36
                implicitHeight: 36
                enabled: root.directory !== ""
                hint: "Add wallpapers: open " + root.directory
                onClicked: ShellState.openPath(root.directory)
            }
            C.Button {
                visible: root.sourceMode === "wallpaperscom"
                text: "Wallpapers.com ↗"
                flat: true
                implicitHeight: 36
                onClicked: ShellState.openUrl(root.current && root.current.creditUrl ? root.current.creditUrl : "https://wallpapers.com/")
            }
            C.Button {
                visible: root.online && root.error !== ""
                text: "Retry"
                flat: true
                implicitHeight: 36
                enabled: !root.onlineLoading && !root.applying
                onClicked: root.searchOnline(false)
            }
            C.Button {
                text: ShellState.wallpaperDownloading ? "Saving…" : ShellState.wallpaperBusy ? "Applying…" : root.isCurrent ? "In use" : root.current && root.current.remote && !root.current.path ? "Save and use" : "Use"
                accent: !!root.current && !root.isCurrent
                implicitHeight: 40
                labelSize: 13
                enabled: !!root.current && !root.isCurrent && !root.applying
                hint: "Enter"
                onClicked: root.apply()
            }
            C.Button {
                glyph: "chevron"
                implicitWidth: 44
                implicitHeight: 44
                hint: "Next · Right"
                enabled: root.selected < root.filtered.length - 1 && !root.applying
                onClicked: root.move(1)
            }
        }
        Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            height: 2
            width: root.filtered.length > 1 ? parent.width * Math.max(0, Math.min(1, root.position / (root.filtered.length - 1))) : parent.width
            color: root.previewAccent
            opacity: root.current ? 0.9 : 0
            Behavior on color { ColorAnimation { duration: Theme.fast } }
        }
    }
    Timer {
        id: onlineDebounce
        interval: 500
        onTriggered: root.searchOnline(false)
    }
    Keys.onLeftPressed: move(-1)
    Keys.onRightPressed: move(1)
    Keys.onUpPressed: move(-5)
    Keys.onDownPressed: move(5)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Home)
            selected = 0;
        else if (event.key === Qt.Key_End)
            selected = Math.max(0, filtered.length - 1);
        else
            return;
        event.accepted = true;
    }
    Keys.onReturnPressed: apply()
}
