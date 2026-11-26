import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Widgets
import "../core"
import "../core/keys.js" as KeyNames
import "../components" as C

// Screenshot or Record beside the title, the mode tiles, one module of options, then the recent shots and one large
// action key at the bottom.
FocusScope {
    id: root
    readonly property string title: "Capture"
    readonly property bool showHeader: false
    readonly property int panelWidth: 600
    // As tall as its contents, so Recent and the action sit right under the options instead of at a fixed foot.
    readonly property int panelHeight: Math.ceil(body.implicitHeight) + Theme.casePadding * 2
    property string mode: "region"
    property string kind: ShellState.recording.active ? "recording" : "screenshot"
    property bool copy: true
    // wf-recorder takes one audio source, so system audio and the microphone are alternatives.
    readonly property string audio: ShellState.setting("recordAudio", "none")
    property bool pending: false
    property string error: ""
    readonly property bool recordingActive: kind === "recording" && !!ShellState.recording.active
    // The colour picker is a screenshot mode only; switching to Record falls back to a region.
    readonly property string effectiveMode: kind === "recording" && mode === "color" ? "region" : mode
    // The first tool this capture needs that isn't installed; stopping a recording needs none.
    readonly property string missingTool: {
        if (recordingActive)
            return "";
        if (effectiveMode === "color")
            return Backend.has("hyprpicker", true) ? "" : "hyprpicker";
        const needs = [kind === "screenshot" ? "grim" : "wf-recorder"].concat(effectiveMode === "region" ? ["slurp"] : []);
        return needs.find(command => !Backend.has(command, true)) || "";
    }
    readonly property var modes: [{key: "region", text: "Region", glyph: "region"}, {key: "window", text: "Window", glyph: "window"},
                                  {key: "output", text: "Screen", glyph: "monitor"}].concat(kind === "screenshot" ? [{key: "color", text: "Colour", glyph: "picker"}] : [])
    function expand(path) {
        return String(path).replace(/^~(?=\/|$)/, Quickshell.env("HOME") || "~");
    }
    function folderName(path) {
        return String(path).replace(/\/+$/, "").split("/").pop() || path;
    }
    readonly property string screenshotFolder: ShellState.setting("screenshotDirectory", "~/Pictures/Screenshots")
    readonly property string recordingFolder: ShellState.setting("recordingDirectory", "~/Videos/Recordings")
    function capture() {
        if (pending || !Backend.ready || missingTool)
            return;
        pending = true;
        error = "";
        if (kind === "screenshot" && effectiveMode === "color") {
            ShellState.action("color");
        } else if (kind === "screenshot") {
            ShellState.screenshot(effectiveMode, copy);
        } else if (!ShellState.recording.active) {
            ShellState.record(effectiveMode, audio);
        } else {
            Backend.request("capture.record.stop", {}, (r, e) => {
                if (!e) {
                    ShellState.recording = r;
                    ShellState.refreshRecording();
                    ShellState.recordingResult(r);
                }
                // Capture closed meanwhile.
                if (!root)
                    return;
                pending = false;
                if (e)
                    error = e.message || "Could not stop recording. Try again.";
            });
        }
    }
    function stepMode(delta) {
        const index = modes.findIndex(m => m.key === effectiveMode);
        const next = Math.max(0, Math.min(modes.length - 1, index + delta));
        mode = modes[next].key;
        modeTiles.itemAt(next).forceActiveFocus(Qt.TabFocusReason);
    }
    // The screenshot shortcuts as they are bound now, for the hint beside the tabs.
    property string shortcutHint: ""
    Component.onCompleted: Backend.request("shortcuts.list", {}, (r, e) => {
        if (e || !r.shortcuts)
            return;
        const keys = action => (r.shortcuts.find(item => item.action === action) || {}).keys || "";
        shortcutHint = [[keys("screenshot region"), "region"], [keys("screenshot output"), "screen"]]
            .filter(pair => pair[0]).map(pair => KeyNames.caps(pair[0]).join(" ") + " for " + pair[1]).join(" · ");
    }, {owner: root})
    Keys.onReturnPressed: capture()
    Keys.onEnterPressed: capture()
    ColumnLayout {
        id: body
        anchors.fill: parent
        spacing: 12
        // Title, the kind, the shortcuts, close.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            spacing: 12
            C.Label {
                text: root.title
                font.pixelSize: 17
                font.weight: 650
                elide: Text.ElideNone
                Layout.leftMargin: 2
            }
            C.Segmented {
                Layout.fillWidth: false
                Layout.preferredWidth: Math.max(196, implicitWidth)
                segmentHeight: 32
                enabled: !root.pending
                model: [{key: "screenshot", text: "Screenshot"}, {key: "recording", text: "Record", accessibleName: "Record the screen"}]
                current: root.kind
                onActivated: key => { root.kind = key; root.error = ""; }
            }
            C.Label {
                text: root.recordingActive ? "Recording · " + root.recordingFolder : root.shortcutHint
                color: Theme.textDim
                font.pixelSize: 12
                horizontalAlignment: Text.AlignRight
                Layout.fillWidth: true
                Layout.minimumWidth: 0
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
        // What to capture; arrow keys move between the tiles.
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                id: modeTiles
                model: root.modes
                C.Button {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property bool on: root.effectiveMode === modelData.key
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: 84
                    cornerRadius: 14
                    enabled: !root.pending && !root.recordingActive
                    Accessible.role: Accessible.RadioButton
                    Accessible.checkable: true
                    Accessible.checked: on
                    Accessible.name: modelData.text
                    Keys.onLeftPressed: root.stepMode(-1)
                    Keys.onRightPressed: root.stepMode(1)
                    onClicked: root.mode = modelData.key
                    background: Rectangle {
                        radius: tile.cornerRadius
                        color: tile.on ? Theme.accentSoft : tile.hovered || tile.visualFocus ? Theme.mix(Theme.module, Theme.text, 0.05) : Theme.module
                        border.width: 1
                        border.color: tile.on ? Theme.accentLine : "transparent"
                        opacity: tile.enabled || tile.on ? 1 : Theme.disabledOpacity
                        Behavior on color { ColorAnimation { duration: Theme.fast } }
                    }
                    contentItem: Item {
                        implicitHeight: tileContent.implicitHeight
                        ColumnLayout {
                            id: tileContent
                            anchors.centerIn: parent
                            spacing: 8
                            C.Icon {
                                name: tile.modelData.glyph
                                size: 24
                                color: tile.on ? Theme.accentText : Theme.textSecondary
                                Layout.alignment: Qt.AlignHCenter
                            }
                            C.Label {
                                text: tile.modelData.text
                                color: tile.on ? Theme.accentText : Theme.textSecondary
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }
                }
            }
        }
        // The options for this kind, one row each with a hairline between them.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: options.implicitHeight + 8
            radius: Theme.radiusModule
            color: Theme.module
            ColumnLayout {
                id: options
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 4
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 0
                component OptionRow: Item {
                    id: optionRow
                    property string text: ""
                    property string note: ""
                    property bool rule: true
                    default property alias trailing: trailingSlot.data
                    Layout.fillWidth: true
                    implicitHeight: 44
                    RowLayout {
                        anchors.fill: parent
                        spacing: 12
                        C.Label {
                            text: optionRow.text
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                        }
                        C.Label {
                            visible: optionRow.note !== ""
                            text: optionRow.note
                            color: Theme.textDim
                            font.pixelSize: 12
                            Layout.maximumWidth: 220
                        }
                        RowLayout {
                            id: trailingSlot
                            spacing: 6
                        }
                    }
                    Rectangle {
                        visible: optionRow.rule
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: Theme.separator
                    }
                }
                OptionRow {
                    visible: root.kind === "screenshot" && root.effectiveMode !== "color"
                    implicitHeight: 46
                    text: "Delay"
                    C.Segmented {
                        Layout.fillWidth: false
                        Layout.preferredWidth: Math.max(4 * 52 + 3 * 2 + 6, implicitWidth)
                        segmentHeight: 32
                        trackColor: Theme.well
                        enabled: !root.pending
                        model: [0, 3, 5, 10].map(seconds => ({key: seconds, text: seconds === 0 ? "Off" : seconds + " s",
                                                               accessibleName: seconds === 0 ? "No delay" : seconds + " seconds"}))
                        current: ShellState.setting("captureDelay", 0)
                        onActivated: key => ShellState.setSetting("captureDelay", key)
                    }
                }
                OptionRow {
                    visible: root.kind === "screenshot" && root.effectiveMode !== "color"
                    text: "Copy to clipboard"
                    C.Switch {
                        selected: root.copy
                        hint: "Copy to clipboard"
                        enabled: !root.pending
                        onClicked: root.copy = !root.copy
                    }
                }
                OptionRow {
                    visible: root.kind === "screenshot" && root.effectiveMode !== "color"
                    rule: false
                    text: "Save to " + root.folderName(root.screenshotFolder)
                    note: "PNG"
                    C.Button {
                        text: "Open"
                        flat: true
                        labelSize: 12
                        implicitHeight: 26
                        cornerRadius: 7
                        leftPadding: 8
                        rightPadding: 8
                        hint: "Open " + root.screenshotFolder
                        onClicked: {
                            ShellState.close();
                            ShellState.openPath(root.expand(root.screenshotFolder));
                        }
                    }
                }
                OptionRow {
                    visible: root.kind === "screenshot" && root.effectiveMode === "color"
                    rule: false
                    text: "Click anywhere to pick a colour"
                    note: "Its hex value is copied"
                }
                OptionRow {
                    visible: root.kind === "recording"
                    text: "Record system sound"
                    note: root.audio === "system" ? "What your speakers play" : ""
                    C.Switch {
                        selected: root.audio === "system"
                        hint: "Record system sound"
                        enabled: !root.pending && !ShellState.recording.active
                        onClicked: ShellState.setSetting("recordAudio", selected ? "none" : "system")
                    }
                }
                OptionRow {
                    visible: root.kind === "recording"
                    text: "Record microphone"
                    C.Switch {
                        selected: root.audio === "microphone"
                        hint: "Record microphone"
                        enabled: !root.pending && !ShellState.recording.active
                        onClicked: ShellState.setSetting("recordAudio", selected ? "none" : "microphone")
                    }
                }
                OptionRow {
                    visible: root.kind === "recording"
                    rule: false
                    implicitHeight: 40
                    text: "One sound source at a time"
                    note: "Save to " + root.folderName(root.recordingFolder) + " · MP4"
                }
            }
        }
        C.Label {
            visible: root.error !== ""
            text: root.error
            color: Theme.dangerText
            font.pixelSize: 12
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
        Item {
            Layout.fillHeight: true
        }
        // Recent shots (or where recordings go) and the action.
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignBottom
                spacing: 6
                C.Label {
                    text: root.kind === "screenshot" ? "Recent · " + root.screenshotFolder
                        : root.recordingActive ? "Recording to " + ShellState.fileName(ShellState.recording.path || "") : "Recordings · " + root.recordingFolder
                    color: Theme.textDim
                    font.pixelSize: 12
                    Layout.fillWidth: true
                }
                Row {
                    visible: root.kind === "screenshot" && root.shotCount > 0
                    spacing: 6
                    Repeater {
                        model: root.shotCount
                        AbstractButton {
                            id: shot
                            required property int index
                            readonly property string path: shots.get(index, "filePath")
                            width: 74
                            height: 46
                            hoverEnabled: true
                            Accessible.name: "Open shot from " + stamp.text
                            onClicked: {
                                ShellState.close();
                                ShellState.openPath(path);
                            }
                            contentItem: Item {}
                            background: ClippingRectangle {
                                radius: 9
                                color: Theme.well
                                Image {
                                    anchors.fill: parent
                                    source: shot.path ? "file://" + shot.path.split("/").map(encodeURIComponent).join("/") : ""
                                    sourceSize.width: 148
                                    sourceSize.height: 92
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    color: Theme.text
                                    opacity: shot.hovered ? 0.08 : 0
                                    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                                }
                                C.Label {
                                    id: stamp
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.rightMargin: 4
                                    anchors.bottomMargin: 2
                                    text: Qt.formatTime(shots.get(shot.index, "fileModified"), ShellState.timeFormat)
                                    font.pixelSize: 9
                                    style: Text.Raised
                                    styleColor: "#000000"
                                }
                            }
                            // The newest shot carries the accent ring; the rest a hairline.
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: shot.index === 0 ? -2 : 0
                                radius: 9 - anchors.margins
                                color: "transparent"
                                border.width: shot.index === 0 ? 2 : 1
                                border.color: shot.index === 0 ? Theme.accent : Theme.hairline
                            }
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -3
                                visible: shot.visualFocus
                                radius: 12
                                color: "transparent"
                                border.width: 2
                                border.color: Theme.text
                                opacity: 0.85
                            }
                        }
                    }
                }
                C.Label {
                    visible: root.kind === "screenshot" && root.shotCount === 0
                    text: "No screenshots yet"
                    color: Theme.textDim
                    font.pixelSize: 12
                    Layout.preferredHeight: 46
                }
                C.Button {
                    visible: root.kind === "recording"
                    text: "Open folder"
                    glyph: "folder"
                    flat: true
                    labelSize: 12
                    implicitHeight: 30
                    cornerRadius: 8
                    leftPadding: 8
                    rightPadding: 10
                    Layout.leftMargin: -8
                    Layout.preferredHeight: 46
                    onClicked: {
                        ShellState.close();
                        ShellState.openPath(root.expand(root.recordingFolder));
                    }
                }
            }
            Item {
                Layout.alignment: Qt.AlignBottom
                implicitWidth: action.implicitWidth
                implicitHeight: action.implicitHeight
                RectangularShadow {
                    anchors.fill: action
                    visible: !Theme.lowPower && action.accent && action.enabled
                    radius: action.cornerRadius
                    blur: 20
                    offset.y: 8
                    color: Theme.tint(Theme.accent, 0.22)
                }
                C.Button {
                    id: action
                    readonly property string clock: {
                        const seconds = ShellState.recordingSeconds;
                        return String(Math.floor(seconds / 60)).padStart(2, "0") + ":" + String(seconds % 60).padStart(2, "0");
                    }
                    text: root.missingTool ? "Install " + root.missingTool
                        : root.pending ? "Working…"
                        : root.kind === "screenshot" ? (root.effectiveMode === "color" ? "Pick colour" : "Take screenshot")
                        : ShellState.recording.active ? "Stop · " + clock : "Start recording"
                    hint: root.missingTool ? "Install " + root.missingTool + " to " + (root.effectiveMode === "color" ? "pick colours" : root.kind === "screenshot" ? "take screenshots" : "record") : text
                    accent: !root.recordingActive
                    focus: true
                    implicitHeight: 52
                    cornerRadius: 14
                    leftPadding: 22
                    rightPadding: 22
                    labelSize: 14
                    enabled: !root.pending && Backend.ready && !root.missingTool
                    onClicked: root.capture()
                    background: Rectangle {
                        readonly property bool lit: action.hovered || action.down || action.visualFocus
                        radius: action.cornerRadius
                        color: !action.enabled ? Theme.module : action.accent ? (lit ? Theme.accentHover : Theme.accent) : (lit ? Theme.keyHover : Theme.keySelected)
                        Behavior on color { ColorAnimation { duration: Theme.fast } }
                    }
                    // A blinking dot before "Stop" while recording; steady with reduced motion or power saving.
                    contentItem: Item {
                        implicitWidth: actionRow.implicitWidth
                        implicitHeight: actionRow.implicitHeight
                        RowLayout {
                            id: actionRow
                            anchors.centerIn: parent
                            spacing: 10
                            Rectangle {
                                id: recordingDot
                                visible: root.recordingActive && !root.pending
                                Layout.preferredWidth: 10
                                Layout.preferredHeight: 10
                                radius: 5
                                color: Theme.danger
                                SequentialAnimation on opacity {
                                    running: root.recordingActive && !Theme.reduced && !Theme.lowPower
                                    loops: Animation.Infinite
                                    onRunningChanged: if (!running) recordingDot.opacity = 1
                                    PropertyAction { value: 1 }
                                    PauseAnimation { duration: 500 }
                                    PropertyAction { value: 0.35 }
                                    PauseAnimation { duration: 500 }
                                }
                            }
                            C.Label {
                                text: action.text
                                color: action.foreground
                                font.pixelSize: action.labelSize
                                font.weight: 650
                                font.features: ({"tnum": 1})
                            }
                        }
                    }
                }
            }
        }
    }
    // A folder that doesn't exist yet leaves the model on the working directory; only files in the folder count.
    readonly property int shotCount: shots.count > 0 && String(shots.get(0, "filePath")).startsWith(expand(screenshotFolder).replace(/\/+$/, "") + "/")
                                     ? Math.min(4, shots.count) : 0
    FolderListModel {
        id: shots
        folder: "file://" + root.expand(root.screenshotFolder).split("/").map(encodeURIComponent).join("/")
        nameFilters: ["*.png", "*.jpg", "*.jpeg"]
        showDirs: false
        sortField: FolderListModel.Time
    }
}
