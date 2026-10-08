import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../components" as C

FocusScope {
    id: root
    property alias query: search.text
    property var entries: []
    property var staleEntries: []
    property string error: ""
    property bool busy: false
    property int requestGeneration: 0
    property bool confirmClear: false
    property bool mutating: false
    property bool hasHistory: false
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
        const previousEntry = (entries.length ? entries : staleEntries)[previousIndex];
        Backend.request("clipboard.list", {
            query: query,
            limit: 500
        }, (r, e) => {
            if (generation !== requestGeneration || query !== search.text)
                return;
            busy = false;
            error = e ? e.message : "";
            entries = e ? [] : r.entries;
            staleEntries = [];
            if (!e && query === "") hasHistory = entries.length > 0;
            else if (!e && entries.length > 0) hasHistory = true;
            const retainedIndex = previousEntry ? entries.findIndex(entry => entry.raw === previousEntry.raw) : -1;
            list.currentIndex = entries.length ? (retainedIndex >= 0 ? retainedIndex : Math.max(0, Math.min(previousIndex, entries.length - 1))) : -1;
        });
    }
    function copy(entry) {
        if (!entry || busy || mutating)
            return;
        mutating = true;
        Backend.request("clipboard.copy", {entry: entry.raw}, (result, failure) => {
            mutating = false;
            if (failure) {
                error = failure.message;
                ShellState.message(failure.message, "error");
                return;
            }
            ShellState.close();
            ShellState.message("Copied to clipboard", "success");
        });
    }
    Component.onCompleted: refresh()
    Connections {
        target: Backend
        function onReadyChanged() {
            if (Backend.ready) root.refresh();
        }
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 16
        RowLayout {
            C.Field {
                id: search
                Layout.fillWidth: true
                focus: true
                placeholderText: "Search clipboard history…"
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
                    } else if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ShiftModifier)) {
                        // Shift+Delete removes the selected entry; plain Delete keeps editing the search.
                        const entry = root.entries[list.currentIndex];
                        if (entry)
                            root.mutate("clipboard.delete", {entry: entry.raw});
                        event.accepted = true;
                    }
                }
                onAccepted: root.copy(root.entries[list.currentIndex])
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: root.confirmClear
            C.Label {
                text: "Delete all clipboard history?"
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
            C.Button {
                text: "Cancel"
                enabled: !root.mutating
                onClicked: { root.confirmClear = false; search.forceActiveFocus(); }
            }
            C.Button {
                text: "Clear"
                danger: true
                enabled: !root.mutating && !root.busy
                onClicked: root.mutate("clipboard.clear", {})
            }
        }
        C.Label {
            visible: root.error !== "" && root.entries.length > 0
            text: root.error
            color: Theme.danger
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
        ListView {
            id: list
            model: root.busy && root.staleEntries.length ? root.staleEntries : root.entries
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: Theme.fast
            highlight: Rectangle {
                color: Theme.raised
                width: list.width - 8
                radius: Theme.controlRadius
            }
            ScrollBar.vertical: C.ScrollBar {}
            delegate: Item {
                id: row
                required property var modelData
                required property int index
                property string thumbnail: ""
                Component.onCompleted: if (modelData.label) {
                    const requestedEntry = modelData.raw;
                    Backend.request("clipboard.thumbnail", {
                        entry: requestedEntry
                    }, (r, e) => {
                        if (!e && r.path && row.modelData.raw === requestedEntry)
                            thumbnail = "file://" + r.path;
                    })
                }
                width: list.width - 8
                height: Math.max(68, Theme.body * 2 + 32)
                MouseArea {
                    anchors.fill: parent
                    enabled: !root.busy && !root.mutating
                    hoverEnabled: true
                    onPositionChanged: mouse => {
                        if (root.pointerMoved(mapToItem(null, mouse.x, mouse.y)))
                            list.currentIndex = row.index;
                    }
                    onClicked: root.copy(row.modelData)
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 16
                    C.Icon {
                        visible: row.thumbnail === ""
                        name: "clipboard"
                        opacity: 0.6
                    }
                    Image {
                        visible: row.thumbnail !== ""
                        source: row.thumbnail
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        sourceSize.width: 88
                        sourceSize.height: 88
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                    C.Label {
                        text: row.modelData.label || row.modelData.text
                        color: row.modelData.label ? Theme.muted : Theme.text
                        Layout.fillWidth: true
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                    }
                    C.Button {
                        glyph: "trash"
                        flat: true
                        hint: "Delete entry"
                        implicitWidth: 32
                        implicitHeight: 32
                        enabled: !root.mutating && !root.busy
                        onClicked: root.mutate("clipboard.delete", {entry: row.modelData.raw})
                    }
                }
            }
            C.EmptyState {
                anchors.centerIn: parent
                width: parent.width - 30
                visible: list.count === 0 && !root.busy
                glyph: "clipboard"
                title: root.error ? "History unavailable" : search.text ? "No matches" : "Clipboard is empty"
                description: root.error || (search.text ? "No saved items match this search." : "Copied text and images will appear here.")
            }
            C.EmptyState {
                anchors.centerIn: parent
                width: parent.width - 30
                visible: list.count === 0 && root.busy
                glyph: "clipboard"
                title: search.text ? "Searching history…" : "Loading history…"
                description: ""
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            C.Label {
                text: root.mutating ? "Updating history…" : root.busy ? (search.text ? "Searching history…" : "Loading history…") : root.entries.length + (search.text ? root.entries.length === 1 ? " match" : " matches" : root.entries.length === 1 ? " item" : " items")
                color: Theme.muted
                font.pixelSize: Theme.small
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
            C.Button {
                visible: root.error !== "" && !root.busy
                text: "Retry"
                glyph: "refresh"
                enabled: !root.mutating
                onClicked: root.refresh()
            }
            C.Button {
                text: "Clear all"
                glyph: "trash"
                danger: true
                enabled: !root.busy && !root.mutating && root.hasHistory
                onClicked: root.confirmClear = !root.confirmClear
            }
        }
    }
    Timer {
        id: debounce
        interval: 160
        onTriggered: root.refresh()
    }
}
