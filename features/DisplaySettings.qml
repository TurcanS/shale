import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

// Settings → Displays: resolution, refresh rate and scale for each screen. A change applies at once and goes back
// after a few seconds unless it is kept, so a mode the screen can't show never sticks.
ColumnLayout {
    id: root
    spacing: 8
    // display.list: {displays: [{name, title, width, height, rate, scale, modes, scales, saved, pending (seconds left)}],
    // revertSeconds, startup}
    property var listing: ({displays: [], revertSeconds: 15, startup: true})
    property bool loaded: false
    property string error: ""
    property bool busy: false
    function load() {
        Backend.request("display.list", {}, (r, e) => {
            root.loaded = true;
            root.error = e ? e.message : "";
            if (!e)
                root.listing = r;
        }, {owner: root});
    }
    function call(method, params, done) {
        busy = true;
        Backend.request(method, params, (r, e) => {
            busy = false;
            error = e ? e.message : "";
            if (done && !e)
                done(r);
            load();
        }, {owner: root});
    }
    function rateText(rate, rates) {
        // Whole hertz unless two rates would read the same.
        const whole = Math.round(rate);
        return (rates.filter(other => Math.round(other) === whole).length > 1 ? rate.toFixed(2) : String(whole)) + " Hz";
    }
    function scaleText(scale) {
        return Math.round(scale * 100) + "%";
    }
    onVisibleChanged: if (visible)
        load()
    Component.onCompleted: if (visible)
        load()
    Connections {
        target: Backend
        function onEventReceived(name, data) {
            if (name === "display.reverted") {
                root.load();
                ShellState.message("Display settings went back", "info");
            }
        }
    }
    C.Label {
        text: "Changes apply right away. If you don't keep them within " + root.listing.revertSeconds + " seconds, the screen goes back to how it was."
        color: Theme.textSecondary
        font.pixelSize: Theme.label
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    C.Label {
        visible: root.loaded && !root.listing.startup
        text: "Kept settings last until Hyprland restarts. Update Shale to have them applied every time Hyprland starts."
        color: Theme.warning
        font.pixelSize: Theme.small
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    C.Label {
        visible: root.error !== ""
        text: root.error
        color: Theme.dangerText
        font.pixelSize: Theme.small
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    C.Group {
        visible: root.loaded && root.listing.displays.length === 0 && root.error === ""
        C.Label {
            text: "No displays found."
            color: Theme.textDim
            font.pixelSize: Theme.small
            Layout.preferredHeight: 48
            Layout.leftMargin: Theme.gapL
        }
    }
    Repeater {
        model: root.listing.displays
        ColumnLayout {
            id: screen
            required property var modelData
            readonly property var display: modelData
            // The choice being made; it matches the screen until something is picked.
            property int chosenWidth: display.width
            property int chosenHeight: display.height
            property real chosenRate: display.rate
            property real chosenScale: display.scale
            property bool picking: false
            readonly property string sizeKey: chosenWidth + "x" + chosenHeight
            readonly property var mode: display.modes.find(m => m.width === chosenWidth && m.height === chosenHeight) || {width: chosenWidth, height: chosenHeight, rates: [chosenRate]}
            readonly property var scales: display.scales[sizeKey] || [chosenScale]
            readonly property bool changed: chosenWidth !== display.width || chosenHeight !== display.height || Math.abs(chosenRate - display.rate) > 0.005 || Math.abs(chosenScale - display.scale) > 0.001
            readonly property bool locked: root.busy || display.pending > 0
            // Counts down while the change waits to be kept; the backend says how long is left.
            property int secondsLeft: display.pending
            function reset() {
                chosenWidth = display.width;
                chosenHeight = display.height;
                chosenRate = display.rate;
                chosenScale = display.scale;
            }
            function pickSize(w, h) {
                chosenWidth = w;
                chosenHeight = h;
                picking = false;
                const rates = mode.rates;
                if (!rates.some(r => Math.abs(r - chosenRate) < 0.005))
                    chosenRate = rates[0];
                // Keep the scale when it suits the new size, otherwise the nearest one that does.
                if (!scales.some(s => Math.abs(s - chosenScale) < 0.001))
                    chosenScale = scales.reduce((best, s) => Math.abs(s - chosenScale) < Math.abs(best - chosenScale) ? s : best, scales[0]);
            }
            Layout.fillWidth: true
            spacing: 8
            Timer {
                interval: 1000
                repeat: true
                running: screen.secondsLeft > 0
                onTriggered: screen.secondsLeft = Math.max(0, screen.secondsLeft - 1)
            }
            // The screen's name, then what it shows now.
            C.SectionHeader {
                text: screen.display.title
                Layout.topMargin: 2
                C.Label {
                    text: screen.display.name + " · " + screen.display.width + " × " + screen.display.height + " · " + root.rateText(screen.display.rate, (screen.display.modes.find(m => m.width === screen.display.width && m.height === screen.display.height) || {rates: []}).rates) + " · " + root.scaleText(screen.display.scale)
                        + (screen.display.saved ? " · kept by Shale" : "")
                    color: Theme.textDim
                    font.pixelSize: Theme.small
                    font.features: ({"tnum": 1})
                    horizontalAlignment: Text.AlignRight
                    Layout.maximumWidth: 420
                }
            }
            C.Group {
                // Resolution: the chosen one, opening the full list below it.
                C.SettingRow {
                    label: "Resolution"
                    description: screen.picking ? "Pick a size; its refresh rates are listed beside it" : "The size of the picture in pixels"
                    enabled: !screen.locked
                    C.Button {
                        text: screen.chosenWidth + " × " + screen.chosenHeight
                        implicitHeight: 32
                        selected: screen.picking
                        hint: screen.picking ? "Close the list" : "Show every resolution"
                        onClicked: screen.picking = !screen.picking
                    }
                }
                ColumnLayout {
                    visible: screen.picking
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    Layout.bottomMargin: 6
                    spacing: 2
                    Repeater {
                        model: screen.picking ? screen.display.modes : []
                        C.Button {
                            id: modeRow
                            required property var modelData
                            readonly property string rates: modelData.rates.map(r => root.rateText(r, modelData.rates)).join(" · ")
                            text: modelData.width + " × " + modelData.height
                            flat: true
                            selected: modelData.width === screen.chosenWidth && modelData.height === screen.chosenHeight
                            Layout.fillWidth: true
                            Layout.leftMargin: 6
                            Layout.rightMargin: 6
                            implicitHeight: Math.max(38, Theme.body + 22)
                            leftPadding: 10
                            rightPadding: 10
                            Accessible.description: rates
                            onClicked: screen.pickSize(modelData.width, modelData.height)
                            contentItem: RowLayout {
                                spacing: Theme.gapM
                                C.Label {
                                    text: modeRow.text
                                    color: Theme.text
                                    font.weight: modeRow.selected ? Font.DemiBold : Font.Normal
                                    font.features: ({"tnum": 1})
                                    Layout.preferredWidth: Math.max(110, Theme.body * 8)
                                }
                                C.Label {
                                    text: modeRow.rates
                                    color: Theme.textDim
                                    font.pixelSize: Theme.small
                                    Layout.fillWidth: true
                                }
                                C.Icon {
                                    visible: modeRow.selected
                                    name: "check"
                                    color: Theme.accentText
                                }
                            }
                        }
                    }
                }
                C.ChoiceRow {
                    visible: screen.mode.rates.length > 1
                    label: "Refresh rate"
                    description: "How often the picture is drawn each second"
                    stacked: screen.mode.rates.length > 4
                    model: screen.mode.rates.map(r => ({key: r, text: root.rateText(r, screen.mode.rates)}))
                    current: screen.mode.rates.find(r => Math.abs(r - screen.chosenRate) < 0.005)
                    enabled: !screen.locked
                    onActivated: key => screen.chosenRate = key
                }
                C.ChoiceRow {
                    label: "Scale"
                    description: "Desktop " + Math.round(screen.chosenWidth / screen.chosenScale) + " × " + Math.round(screen.chosenHeight / screen.chosenScale)
                    stacked: screen.scales.length > 5
                    model: screen.scales.map(s => ({key: s, text: root.scaleText(s)}))
                    current: screen.scales.find(s => Math.abs(s - screen.chosenScale) < 0.001)
                    enabled: !screen.locked
                    onActivated: key => screen.chosenScale = key
                }
            }
            // Apply, then keep or go back while the countdown runs.
            Rectangle {
                visible: screen.display.pending > 0 || screen.changed || screen.display.saved
                Layout.fillWidth: true
                implicitHeight: actions.implicitHeight + 16
                radius: Theme.radiusCard + 2
                color: screen.display.pending > 0 ? Theme.accentSoft : "transparent"
                border.width: screen.display.pending > 0 ? 1 : 0
                border.color: Theme.accentLine
                RowLayout {
                    id: actions
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: screen.display.pending > 0 ? Theme.gapL : 0
                    anchors.rightMargin: screen.display.pending > 0 ? 8 : 0
                    spacing: Theme.gapS
                    C.Label {
                        visible: screen.display.pending > 0
                        text: "Keep these display settings? Going back in " + screen.secondsLeft + " s"
                        color: Theme.accentText
                        font.pixelSize: Theme.label
                        font.weight: Font.DemiBold
                        font.features: ({"tnum": 1})
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Item {
                        visible: screen.display.pending === 0
                        Layout.fillWidth: true
                    }
                    C.Button {
                        visible: screen.display.pending > 0
                        text: "Go back"
                        enabled: !root.busy
                        onClicked: root.call("display.revert", {output: screen.display.name})
                    }
                    C.Button {
                        visible: screen.display.pending > 0
                        text: "Keep"
                        accent: true
                        enabled: !root.busy
                        onClicked: root.call("display.keep", {output: screen.display.name}, () => ShellState.message(screen.display.title + " settings kept", "success"))
                    }
                    C.Button {
                        visible: screen.display.pending === 0 && screen.display.saved && !screen.changed
                        text: "Use Hyprland's setting"
                        hint: "Forget what Shale kept for this display and reload the Hyprland config"
                        enabled: !root.busy
                        onClicked: root.call("display.reset", {output: screen.display.name})
                    }
                    C.Button {
                        visible: screen.display.pending === 0 && screen.changed
                        text: "Cancel"
                        flat: true
                        onClicked: screen.reset()
                    }
                    C.Button {
                        visible: screen.display.pending === 0 && screen.changed
                        text: "Apply"
                        accent: true
                        enabled: !root.busy
                        onClicked: root.call("display.set", {output: screen.display.name, width: screen.chosenWidth, height: screen.chosenHeight, rate: screen.chosenRate, scale: screen.chosenScale},
                                             null)
                    }
                }
            }
        }
    }
}
