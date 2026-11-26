pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import "../core"
import "../core/format.js" as Format
import "../components" as C

// Choosing files to send, inside the panel: places along the top, the folder's contents (folders first), and an
// Add key for what is ticked. Enter opens a folder or ticks a file, Space ticks either, Backspace goes up a level.
FocusScope {
    id: root
    signal picked(var paths)
    signal cancelled()
    readonly property string home: Quickshell.env("HOME") || "/"
    function expand(path) {
        return String(path).replace(/^~(?=\/|$)/, home);
    }
    readonly property var places: [
        {text: "Home", path: home},
        {text: "Downloads", path: home + "/Downloads"},
        {text: "Pictures", path: home + "/Pictures"},
        {text: "Screenshots", path: expand(ShellState.setting("screenshotDirectory", "~/Pictures/Screenshots"))},
        {text: "Documents", path: home + "/Documents"},
        {text: "Videos", path: home + "/Videos"},
        {text: "Desktop", path: home + "/Desktop"}
    ]
    property string folder: home + "/Pictures"
    property var ticked: []
    function url(path) {
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    }
    function open(path) {
        folder = path.replace(/\/+$/, "") || "/";
        list.currentIndex = 0;
    }
    function up() {
        if (folder !== "/")
            open(folder.slice(0, folder.lastIndexOf("/")) || "/");
    }
    function toggle(path) {
        ticked = ticked.indexOf(path) >= 0 ? ticked.filter(p => p !== path) : ticked.concat([path]);
    }
    function activate(index) {
        if (index < 0 || index >= files.count)
            return;
        if (files.get(index, "fileIsDir"))
            open(files.get(index, "filePath"));
        else
            toggle(files.get(index, "filePath"));
    }
    function add() {
        if (ticked.length)
            picked(ticked);
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Backspace) {
            up();
            event.accepted = true;
        } else if (event.key === Qt.Key_Space) {
            if (list.currentIndex >= 0)
                toggle(files.get(list.currentIndex, "filePath"));
            event.accepted = true;
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && event.modifiers & Qt.ControlModifier) {
            add();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            cancelled();
            event.accepted = true;
        }
    }
    FolderListModel {
        id: files
        folder: root.url(root.folder)
        showDirsFirst: true
        showHidden: false
        showDotAndDotDot: false
        sortField: FolderListModel.Name
        caseSensitive: false
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 10
        // Where to look.
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: root.places
                C.Chip {
                    required property var modelData
                    text: modelData.text
                    selected: root.folder === modelData.path
                    onClicked: root.open(modelData.path)
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            // "Up", not an arrow: the panel's header already has Back (out of choosing).
            C.Button {
                text: "Up"
                flat: true
                hint: "The folder above · Backspace"
                implicitHeight: 32
                enabled: root.folder !== "/"
                onClicked: root.up()
            }
            C.Label {
                text: root.folder.startsWith(root.home) ? "~" + root.folder.slice(root.home.length) : root.folder
                color: Theme.textSecondary
                font.pixelSize: 13
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusModule
            color: Theme.module
            clip: true
            ListView {
                id: list
                anchors.fill: parent
                anchors.margins: 4
                model: files
                focus: true
                keyNavigationEnabled: true
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                ScrollBar.vertical: C.ScrollBar {}
                Keys.onReturnPressed: root.activate(currentIndex)
                Keys.onEnterPressed: root.activate(currentIndex)
                delegate: AbstractButton {
                    id: row
                    required property int index
                    required property string fileName
                    required property string filePath
                    required property bool fileIsDir
                    required property real fileSize
                    required property var fileModified
                    readonly property bool tickedRow: root.ticked.indexOf(filePath) >= 0
                    readonly property string kind: {
                        if (fileIsDir)
                            return "folder";
                        const ext = fileName.split(".").pop().toLowerCase();
                        if (["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif", "svg"].indexOf(ext) >= 0)
                            return "image";
                        if (["mp4", "mov", "m4v", "mkv", "webm"].indexOf(ext) >= 0)
                            return "film";
                        if (["mp3", "m4a", "flac", "wav", "ogg", "opus"].indexOf(ext) >= 0)
                            return "music";
                        return "file";
                    }
                    width: ListView.view.width - 8
                    height: 40
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    onClicked: {
                        list.currentIndex = index;
                        root.activate(index);
                    }
                    onDoubleClicked: if (!fileIsDir) {
                        if (!tickedRow)
                            root.toggle(filePath);
                        root.add();
                    }
                    background: Rectangle {
                        radius: Theme.radiusKey
                        color: row.tickedRow ? Theme.raised : row.ListView.isCurrentItem && list.activeFocus || row.hovered ? Theme.rowWash(row.down) : "transparent"
                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.fast
                            }
                        }
                        C.Raise {
                            shown: row.tickedRow
                        }
                    }
                    contentItem: RowLayout {
                        spacing: 10
                        C.GlyphTile {
                            glyph: row.tickedRow ? "check" : row.kind
                            size: 28
                            selected: row.tickedRow
                            color: row.tickedRow ? Theme.accent : Theme.keyTile
                            Layout.leftMargin: 6
                        }
                        C.Label {
                            text: row.fileName
                            font.pixelSize: 13
                            color: Theme.text
                            Layout.fillWidth: true
                        }
                        C.Label {
                            text: row.fileIsDir ? "" : Format.bytes(row.fileSize)
                            color: Theme.textDim
                            font.pixelSize: 12
                            font.features: ({"tnum": 1})
                        }
                        // Folders open with a click; this ticks one to send whole.
                        C.Button {
                            visible: row.fileIsDir
                            glyph: row.tickedRow ? "check" : "plus"
                            flat: true
                            hint: row.tickedRow ? "Untick folder" : "Send this folder"
                            implicitWidth: 28
                            implicitHeight: 28
                            focusPolicy: Qt.NoFocus
                            onClicked: root.toggle(row.filePath)
                            Layout.rightMargin: 4
                        }
                        Item {
                            visible: !row.fileIsDir
                            implicitWidth: 4
                        }
                    }
                }
            }
            C.EmptyState {
                anchors.centerIn: parent
                width: parent.width - 48
                visible: files.status === FolderListModel.Ready && files.count === 0
                glyph: "folder"
                title: "This folder is empty"
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            C.Label {
                text: root.ticked.length ? root.ticked.length + (root.ticked.length === 1 ? " item ticked" : " items ticked") : "Tick files with a click or Space"
                color: Theme.textDim
                font.pixelSize: 12
                Layout.fillWidth: true
            }
            C.Button {
                text: "Cancel"
                implicitHeight: 32
                onClicked: root.cancelled()
            }
            C.Button {
                text: root.ticked.length > 1 ? "Add " + root.ticked.length : "Add"
                accent: true
                implicitHeight: 32
                enabled: root.ticked.length > 0
                onClicked: root.add()
            }
        }
    }
}
