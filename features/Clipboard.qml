import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../components" as C

// Search across the top, filter chips, the history on the left (pins first) and the selected entry on the right.
// Removing hides the entry at once and only deletes it when the undo bar goes, or the panel closes.
FocusScope {
    id: root
    readonly property string title: "Clipboard"
    readonly property bool showHeader: false
    readonly property int panelWidth: 560
    readonly property int panelHeight: 600
    property alias query: search.text
    // Pins (with `pin` and `pinned`) and then cliphist's history (with `raw`), newest first.
    property var entries: []
    property var staleEntries: []
    property string error: ""
    property bool busy: false
    property int requestGeneration: 0
    property bool confirmClear: false
    property bool mutating: false
    property bool hasHistory: false
    property string filter: "all"
    readonly property var filters: [{key: "all", text: "All"}, {key: "text", text: "Text"}, {key: "image", text: "Images"},
                                    {key: "link", text: "Links"}, {key: "color", text: "Colours"}, {key: "pinned", text: "Pinned"}]
    // The entry hidden here and waiting for the undo bar to go.
    property var pending: null
    readonly property var shown: (busy && staleEntries.length ? staleEntries : entries)
        .filter(entry => (!pending || keyOf(entry) !== keyOf(pending)) && matches(entry, filter))
    readonly property var current: list.currentIndex >= 0 && list.currentIndex < shown.length ? shown[list.currentIndex] : null
    readonly property bool openable: !!current && (current.kind === "link" || current.kind === "path")
    Component.onDestruction: commit()
    function keyOf(entry) {
        return entry ? (entry.pin ? "pin:" + entry.pin : entry.raw) : "";
    }
    function typeOf(entry) {
        if (!entry)
            return "text";
        if (entry.label)
            return entry.label.startsWith("Image") ? "image" : "data";
        return entry.kind === "color" ? "color" : entry.kind === "link" ? "link" : entry.kind === "path" ? (entry.folder ? "folder" : "file") : "text";
    }
    function matches(entry, key) {
        const type = typeOf(entry);
        return key === "all" || (key === "pinned" ? !!entry.pinned : key === "text" ? ["text", "file", "folder"].indexOf(type) >= 0 : key === type);
    }
    readonly property var typeNames: ({image: "Image", data: "Data", color: "Colour", link: "Link", folder: "Folder", file: "File", text: "Text"})
    readonly property var typeGlyphs: ({image: "image", data: "clipboard", color: "drop", link: "link", folder: "folder", file: "folder", text: "text"})
    function stepFilter(delta) {
        const index = filters.findIndex(f => f.key === filter);
        filter = filters[(index + delta + filters.length) % filters.length].key;
    }
    property point lastPointer: Qt.point(-1, -1)
    function pointerMoved(position) {
        const moved = lastPointer.x >= 0 && (Math.abs(position.x - lastPointer.x) > 1 || Math.abs(position.y - lastPointer.y) > 1);
        lastPointer = position;
        return moved;
    }
    function moveSelection(amount) {
        if (!list.count)
            return;
        list.currentIndex = Math.max(0, Math.min(list.count - 1, list.currentIndex + amount));
        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
    }
    function mutate(method, params) {
        if (mutating || busy)
            return;
        mutating = true;
        error = "";
        Backend.request(method, params, (result, failure) => {
            mutating = false;
            if (failure) {
                error = failure.message;
                ShellState.message(failure.message, "error");
                return;
            }
            confirmClear = false;
            if (method === "clipboard.clear") hasHistory = false;
            refresh();
            search.forceActiveFocus();
        }, {owner: root});
    }
    function togglePin(entry) {
        if (!entry)
            return;
        if (entry.pinned)
            mutate("clipboard.unpin", {pin: entry.pin});
        else
            mutate("clipboard.pin", {entry: entry.raw});
    }
    // Hides the entry now; the backend only hears of it when the undo bar goes.
    function remove(entry) {
        if (!entry || busy || mutating)
            return;
        commit();
        const index = list.currentIndex;
        pending = entry;
        list.currentIndex = Math.min(index, list.count - 1);
        confirmClear = false;
        undoBar.show(entry.pinned ? "Pin removed" : "Removed from history");
    }
    function commit() {
        const entry = pending;
        if (!entry)
            return;
        pending = null;
        Backend.request(entry.pinned ? "clipboard.unpin" : "clipboard.delete", entry.pinned ? {pin: entry.pin, forget: true} : {entry: entry.raw}, (result, failure) => {
            if (failure)
                ShellState.message(failure.message, "error");
            // Sent as the panel closes, so the answer may find it gone.
            if (root)
                root.refresh();
        });
    }
    Keys.onEscapePressed: event => {
        if (confirmClear) {
            if (!mutating) {
                confirmClear = false;
                search.forceActiveFocus();
            }
        } else
            event.accepted = false;
    }
    function refresh() {
        busy = true;
        const generation = ++requestGeneration;
        const query = search.text;
        const previousIndex = list.currentIndex;
        const previousEntry = current;
        Backend.request("clipboard.list", {
            query: query,
            limit: 500
        }, (r, e) => {
            if (generation !== requestGeneration || query !== search.text)
                return;
            busy = false;
            error = e ? e.message : "";
            entries = e ? [] : (r.pins || []).map(pin => Object.assign({pinned: true}, pin)).concat(r.entries);
            staleEntries = [];
            if (!e && query === "") hasHistory = r.entries.length > 0;
            else if (!e && r.entries.length > 0) hasHistory = true;
            // The same entry again; a pin or unpin moves it between the pins and the history, so its text decides then.
            let retainedIndex = previousEntry ? shown.findIndex(entry => keyOf(entry) === keyOf(previousEntry)) : -1;
            if (retainedIndex < 0 && previousEntry)
                retainedIndex = shown.findIndex(entry => entry.text === previousEntry.text);
            list.currentIndex = shown.length ? (retainedIndex >= 0 ? retainedIndex : Math.max(0, Math.min(previousIndex, shown.length - 1))) : -1;
        }, {owner: root});
    }
    function copy(entry) {
        if (!entry || busy || mutating)
            return;
        mutating = true;
        Backend.request("clipboard.copy", entry.pinned ? {pin: entry.pin} : {entry: entry.raw}, (result, failure) => {
            mutating = false;
            if (failure) {
                error = failure.message;
                ShellState.message(failure.message, "error");
                return;
            }
            ShellState.close();
            ShellState.message("Copied to clipboard", "success");
        }, {owner: root});
    }
    // Links open in the browser; paths in their app or the file manager.
    function open(entry) {
        if (!entry || (entry.kind !== "link" && entry.kind !== "path") || busy || mutating)
            return;
        mutating = true;
        // Closed while cliphist was decoding: the user moved on, so the owner drops the answer and nothing opens.
        Backend.request("clipboard.open", entry.pinned ? {pin: entry.pin} : {entry: entry.raw}, (result, failure) => {
            mutating = false;
            if (failure) {
                ShellState.message(failure.message, "error");
                return;
            }
            ShellState.close();
            if (result.url) ShellState.openUrl(result.url);
            else ShellState.openPath(result.path);
        }, {owner: root});
    }
    // The selected entry in full: the whole text (the list only has cliphist's first line) or the image.
    property string previewKey: ""
    property string previewText: ""
    property bool previewCut: false
    property string previewImage: ""
    property bool previewLoading: false
    onCurrentChanged: if (keyOf(current) !== previewKey) previewTimer.restart()
    function loadPreview() {
        const entry = current;
        const key = keyOf(entry);
        if (key === previewKey)
            return;
        previewKey = key;
        previewText = "";
        previewCut = false;
        previewImage = "";
        if (!entry || entry.kind === "color" || entry.label && !entry.label.startsWith("Image")) {
            previewLoading = false;
            return;
        }
        if (entry.label && entry.pinned) {
            previewLoading = false;
            previewImage = entry.image ? "file://" + entry.image.split("/").map(encodeURIComponent).join("/") : "";
            return;
        }
        previewLoading = true;
        const image = !!entry.label;
        Backend.request(image ? "clipboard.thumbnail" : "clipboard.text", entry.pinned ? {pin: entry.pin} : {entry: entry.raw}, (r, e) => {
            if (root.previewKey !== key)
                return;
            previewLoading = false;
            if (e)
                return;
            if (image) {
                previewImage = r.path ? "file://" + r.path : "";
            } else {
                previewText = r.text;
                previewCut = !!r.cut;
            }
        }, {owner: root});
    }
    Timer {
        id: previewTimer
        interval: 60
        onTriggered: root.loadPreview()
    }
    Component.onCompleted: refresh()
    Connections {
        target: Backend
        function onReadyChanged() {
            if (Backend.ready) root.refresh();
        }
    }
    readonly property var footerKeys: {
        if (!current)
            return [];
        const keys = [{key: "↵", text: "Copy"}];
        if (openable)
            keys.push({key: "Ctrl ↵", text: current.kind === "path" && !current.folder ? "Show" : "Open"});
        keys.push({key: "Ctrl P", text: current.pinned ? "Unpin" : "Pin"});
        keys.push({key: search.text === "" ? "Del" : "Shift Del", text: "Remove"});
        return keys;
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        // The 56 px search row across the top of the case, with a hairline under it from edge to edge.
        Item {
            Layout.fillWidth: true
            implicitHeight: 56 - Theme.casePadding
            C.Icon {
                id: searchIcon
                anchors.left: parent.left
                anchors.leftMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -Theme.casePadding / 2
                name: "search"
                size: 18
                color: Theme.textDim
            }
            C.Field {
                id: search
                anchors.left: searchIcon.right
                anchors.leftMargin: Theme.gapM
                anchors.right: countLabel.left
                anchors.rightMargin: Theme.gapS
                anchors.verticalCenter: searchIcon.verticalCenter
                focus: true
                leftPadding: 0
                rightPadding: 0
                font.pixelSize: 16
                placeholderText: "Search clipboard history…"
                background: Item {}
                onTextChanged: {
                    ++root.requestGeneration;
                    root.busy = true;
                    if (root.entries.length) root.staleEntries = root.entries;
                    root.entries = [];
                    root.confirmClear = false;
                    debounce.restart();
                }
                Keys.onDownPressed: root.moveSelection(1)
                Keys.onUpPressed: root.moveSelection(-1)
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) {
                        root.moveSelection(event.key === Qt.Key_PageDown ? 6 : -6);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Delete && ((event.modifiers & Qt.ShiftModifier) || search.text === "")) {
                        // Shift+Delete removes the selected entry; plain Delete does too while there is no search to edit.
                        root.remove(root.current);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier)) {
                        root.togglePin(root.current);
                        event.accepted = true;
                    } else if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && (event.modifiers & Qt.ControlModifier)) {
                        root.stepFilter(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1);
                        event.accepted = true;
                    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
                        // Entries with nothing to open fall through to onAccepted and copy.
                        if (root.openable) {
                            root.open(root.current);
                            event.accepted = true;
                        }
                    }
                }
                onAccepted: root.copy(root.current)
            }
            C.Label {
                id: countLabel
                anchors.right: parent.right
                anchors.rightMargin: 2
                anchors.verticalCenter: searchIcon.verticalCenter
                text: root.mutating ? "Updating…" : root.busy ? (search.text ? "Searching…" : "Loading…")
                    : root.shown.length + (search.text ? (root.shown.length === 1 ? " match" : " matches") : (root.shown.length === 1 ? " item" : " items"))
                color: Theme.textDim
                font.pixelSize: 12
                font.features: ({"tnum": 1})
            }
            Rectangle {
                anchors.bottom: parent.bottom
                x: -Theme.casePadding
                width: parent.width + 2 * Theme.casePadding
                height: 1
                color: Theme.hairline
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 10
            Layout.bottomMargin: 6
            Layout.leftMargin: -2
            spacing: 6
            Repeater {
                model: root.filters
                C.Chip {
                    required property var modelData
                    text: modelData.text
                    selected: root.filter === modelData.key
                    focusPolicy: Qt.NoFocus
                    Accessible.role: Accessible.RadioButton
                    Accessible.checked: selected
                    onClicked: {
                        root.filter = modelData.key;
                        search.forceActiveFocus();
                    }
                }
            }
            Item {
                Layout.fillWidth: true
            }
        }
        C.Label {
            visible: root.error !== "" && root.entries.length > 0
            text: root.error
            color: Theme.dangerText
            font.pixelSize: 12
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            wrapMode: Text.WordWrap
        }
        // The list on the left, a hairline, and the selected entry on the right.
        Item {
            id: main
            Layout.fillWidth: true
            Layout.fillHeight: true
            readonly property int listWidth: 250 - Theme.casePadding
            readonly property bool empty: list.count === 0
            ListView {
                id: list
                // Rows reach 8 px from the case edge.
                x: -(Theme.casePadding - 8)
                y: 4
                width: main.listWidth - x - 8
                height: parent.height - 8
                clip: true
                model: root.shown
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: Theme.fast
                ScrollBar.vertical: C.ScrollBar {}
                delegate: C.ListRow {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property string type: root.typeOf(modelData)
                    width: list.width
                    height: 48
                    // Opening the panel, the rows print in from the top like a receipt.
                    opacity: (enabled ? 1 : Theme.disabledOpacity) * printIn.shown
                    transform: [
                        Translate {
                            y: row.sunk
                        },
                        C.Cascade {
                            id: printIn
                            panel: "clipboard"
                            order: row.index
                            dy: -8
                            spacing: 1.7
                            limit: 12
                        }
                    ]
                    topPadding: 9
                    bottomPadding: 9
                    leftPadding: 8
                    rightPadding: 8
                    quiet: true
                    focusPolicy: Qt.NoFocus
                    glyph: root.typeGlyphs[type]
                    // Links without their scheme, like an address bar.
                    text: modelData.label || (type === "link" ? modelData.text.replace(/^https?:\/\//i, "") : modelData.text)
                    subtitle: (modelData.pinned ? "Pinned · " : "") + root.typeNames[type]
                    selected: ListView.isCurrentItem
                    checkmark: false
                    Accessible.name: (modelData.pinned ? "Pinned " : "") + root.typeNames[type] + ": " + text
                    onClicked: {
                        list.currentIndex = index;
                        search.forceActiveFocus();
                    }
                    onDoubleClicked: root.copy(modelData)
                    HoverHandler {
                        onPointChanged: if (hovered && root.pointerMoved(point.scenePosition)) list.currentIndex = row.index
                    }
                    trailing: [
                        Rectangle {
                            visible: row.type === "color"
                            implicitWidth: 12
                            implicitHeight: 12
                            radius: 6
                            color: row.modelData.color || "transparent"
                            border.width: 1
                            border.color: Theme.edge
                        },
                        C.Icon {
                            visible: !!row.modelData.pinned
                            name: "pin"
                            size: 12
                            color: Theme.accentText
                            Layout.rightMargin: 2
                        }
                    ]
                }
            }
            Rectangle {
                visible: !main.empty
                x: main.listWidth
                width: 1
                height: parent.height
                color: Theme.hairline
            }
            // The selected entry: its contents, what it is, and Copy, Pin and Remove.
            ColumnLayout {
                visible: !main.empty && !!root.current
                x: main.listWidth + Theme.casePadding
                y: 12
                width: parent.width - x
                height: parent.height - 24
                spacing: 10
                Rectangle {
                    id: previewBox
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 14
                    color: Theme.module
                    clip: true
                    readonly property string type: root.current ? root.typeOf(root.current) : ""
                    ScrollView {
                        id: textScroll
                        anchors.fill: parent
                        visible: ["text", "link", "file", "folder"].indexOf(previewBox.type) >= 0
                        contentWidth: availableWidth
                        ScrollBar.vertical: C.ScrollBar {
                            parent: textScroll
                            x: textScroll.width - width - 2
                            y: 6
                            height: textScroll.height - 12
                        }
                        C.Label {
                            width: textScroll.availableWidth
                            padding: 14
                            text: root.previewText !== "" ? root.previewText + (root.previewCut ? "…" : "") : root.current ? root.current.text : ""
                            color: root.previewLoading && root.previewText === "" ? Theme.textSecondary : Theme.text
                            font.pixelSize: 15
                            lineHeight: 1.3
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            elide: Text.ElideNone
                            verticalAlignment: Text.AlignTop
                        }
                    }
                    Image {
                        visible: previewBox.type === "image"
                        anchors.fill: parent
                        anchors.margins: 10
                        source: previewBox.type === "image" ? root.previewImage : ""
                        sourceSize.width: 520
                        sourceSize.height: 520
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        C.Icon {
                            visible: parent.status !== Image.Ready && !root.previewLoading
                            anchors.centerIn: parent
                            name: "image"
                            size: 28
                            color: Theme.textFaint
                        }
                    }
                    // A colour: the swatch, then its hex and RGB values.
                    ColumnLayout {
                        visible: previewBox.type === "color"
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Theme.radiusKey
                            color: root.current && root.current.color ? root.current.color : "transparent"
                            border.width: 1
                            border.color: Theme.edge
                        }
                        Repeater {
                            model: {
                                const value = root.current && root.current.color ? Qt.color(root.current.color) : null;
                                return value ? [{name: "Hex", value: String(root.current.color)},
                                                {name: "RGB", value: [value.r, value.g, value.b].map(c => Math.round(c * 255)).join(", ")}] : [];
                            }
                            RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.leftMargin: 4
                                Layout.rightMargin: 4
                                C.Label {
                                    text: parent.modelData.name
                                    color: Theme.textDim
                                    font.pixelSize: 12
                                    Layout.preferredWidth: 44
                                }
                                C.Label {
                                    text: parent.modelData.value
                                    font.family: Theme.mono
                                    font.pixelSize: 13
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                    C.EmptyState {
                        visible: previewBox.type === "data"
                        anchors.centerIn: parent
                        width: parent.width - 28
                        glyph: "clipboard"
                        title: "No preview"
                        description: root.current && root.current.label || ""
                    }
                }
                // What the entry is; cliphist keeps no source app or copy time, so neither is shown.
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 4
                    Repeater {
                        model: {
                            const entry = root.current;
                            if (!entry)
                                return [];
                            const type = root.typeOf(entry);
                            const rows = [{name: "Type", value: root.typeNames[type]}];
                            if (type === "image" || type === "data")
                                rows.push({name: "Size", value: entry.label.split(" · ").slice(1).join(" · ")});
                            else if (type === "link")
                                rows.push({name: "Site", value: (entry.text.match(/^https?:\/\/([^\/?#]+)/i) || ["", ""])[1]});
                            else if (type === "text" && root.previewText !== "")
                                rows.push({name: "Length", value: root.previewText.length + (root.previewCut ? "+" : "") + (root.previewText.length === 1 ? " character" : " characters")});
                            rows.push({name: "Kept", value: entry.pinned ? "Pinned, stays after Clear" : "In history"});
                            return rows.reduce((cells, row) => cells.concat([{text: row.name, dim: true}, {text: row.value, dim: false}]), []);
                        }
                        C.Label {
                            required property var modelData
                            text: modelData.text
                            color: modelData.dim ? Theme.textDim : Theme.text
                            font.pixelSize: 12
                            Layout.fillWidth: !modelData.dim
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    C.Button {
                        text: "Copy"
                        accent: true
                        labelSize: 13
                        hint: "Copy and close (Enter)"
                        Layout.fillWidth: true
                        enabled: !root.mutating && !root.busy
                        onClicked: root.copy(root.current)
                    }
                    C.Button {
                        visible: root.openable
                        text: root.current && root.current.kind === "path" && !root.current.folder ? "Show" : "Open"
                        hint: (root.current && root.current.kind === "path" && !root.current.folder ? "Show in folder" : "Open") + " (Ctrl+Enter)"
                        labelSize: 13
                        padding: 12
                        enabled: !root.mutating && !root.busy
                        onClicked: root.open(root.current)
                    }
                    C.Button {
                        text: root.current && root.current.pinned ? "Pinned" : "Pin"
                        selected: !!root.current && !!root.current.pinned
                        hint: (selected ? "Unpin" : "Pin: keep it after Clear") + " (Ctrl+P)"
                        labelSize: 13
                        padding: 12
                        enabled: !root.mutating && !root.busy
                        Accessible.role: Accessible.CheckBox
                        Accessible.checkable: true
                        Accessible.checked: selected
                        onClicked: root.togglePin(root.current)
                    }
                    C.Button {
                        glyph: "trash"
                        hint: "Remove (Delete)"
                        implicitWidth: 36
                        enabled: !root.mutating && !root.busy
                        onClicked: root.remove(root.current)
                    }
                }
            }
            C.EmptyState {
                anchors.centerIn: parent
                width: parent.width - 60
                visible: main.empty && !root.busy
                glyph: "clipboard"
                title: root.error ? "History unavailable" : search.text ? "No matches"
                    : root.filter === "pinned" ? "Nothing pinned" : root.filter !== "all" && root.entries.length ? "Nothing of this kind" : "Clipboard is empty"
                description: root.error || (search.text ? "No saved items match this search."
                    : root.filter === "pinned" ? "Pin an entry to keep it after the history is cleared."
                    : root.filter !== "all" && root.entries.length ? "Try All." : "Copied text and images will appear here.")
            }
            C.Button {
                visible: main.empty && !root.busy && root.error !== ""
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.verticalCenter
                anchors.topMargin: 64
                text: "Retry"
                glyph: "refresh"
                enabled: !root.mutating
                onClicked: root.refresh()
            }
            C.EmptyState {
                anchors.centerIn: parent
                width: parent.width - 60
                visible: main.empty && root.busy
                glyph: "clipboard"
                title: search.text ? "Searching history…" : "Loading history…"
                description: ""
            }
        }
        // Key hints, or the Clear confirmation; a hairline above it from edge to edge.
        Item {
            Layout.fillWidth: true
            implicitHeight: 38 - Theme.casePadding
            Rectangle {
                anchors.top: parent.top
                x: -Theme.casePadding
                width: parent.width + 2 * Theme.casePadding
                height: 1
                color: Theme.hairline
            }
            RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: Theme.casePadding / 2
                spacing: 16
                Repeater {
                    model: root.confirmClear ? [] : root.footerKeys
                    RowLayout {
                        required property var modelData
                        spacing: 6
                        C.KeyHint {
                            text: parent.modelData.key
                        }
                        C.Label {
                            text: parent.modelData.text
                            color: Theme.textDim
                            font.pixelSize: 12
                            elide: Text.ElideNone
                        }
                    }
                }
                C.Label {
                    visible: root.confirmClear
                    text: "Delete all clipboard history? Pins stay."
                    font.pixelSize: 12
                    Layout.fillWidth: true
                }
                Item {
                    visible: !root.confirmClear
                    Layout.fillWidth: true
                }
                C.Button {
                    visible: root.confirmClear
                    text: "Cancel"
                    flat: true
                    labelSize: 12
                    implicitHeight: 26
                    cornerRadius: 7
                    enabled: !root.mutating
                    onClicked: { root.confirmClear = false; search.forceActiveFocus(); }
                }
                C.Button {
                    visible: root.confirmClear
                    text: "Clear"
                    danger: true
                    labelSize: 12
                    implicitHeight: 26
                    cornerRadius: 7
                    enabled: !root.mutating && !root.busy
                    onClicked: {
                        root.commit();
                        root.mutate("clipboard.clear", {});
                    }
                }
                C.Button {
                    visible: !root.confirmClear
                    text: "Clear history"
                    flat: true
                    labelSize: 12
                    implicitHeight: 26
                    cornerRadius: 7
                    leftPadding: 8
                    rightPadding: 8
                    foreground: !enabled ? Theme.textFaint : hovered || visualFocus ? Theme.text : Theme.textDim
                    hint: "Delete everything but the pins"
                    enabled: !root.busy && !root.mutating && root.hasHistory
                    onClicked: root.confirmClear = true
                }
            }
        }
    }
    // Over the bottom of the list, clear of the footer and the selected entry's keys.
    C.UndoBar {
        id: undoBar
        x: -(Theme.casePadding - 8)
        width: main.listWidth - x - 8
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 38 - Theme.casePadding + 8
        onUndone: {
            const index = list.currentIndex;
            root.pending = null;
            list.currentIndex = Math.max(0, Math.min(index, list.count - 1));
        }
        onExpired: root.commit()
    }
    Timer {
        id: debounce
        interval: 160
        onTriggered: root.refresh()
    }
}
