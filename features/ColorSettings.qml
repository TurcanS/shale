import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

ColumnLayout {
    id: root
    spacing: 10
    property string error: ""
    readonly property bool fromWallpaper: ShellState.setting("accentFromWallpaper", false)
    // Picking an accent by hand ends wallpaper matching.
    function setAccent(value) {
        if (fromWallpaper)
            ShellState.setSetting("accentFromWallpaper", false);
        ShellState.setSetting("accentColor", value);
        ShellState.setSetting("accentManual", value);
    }
    function setFromWallpaper(enabled) {
        if (enabled === fromWallpaper)
            return;
        if (enabled) {
            // Remember the hand-picked accent so turning matching off restores it.
            ShellState.setSetting("accentManual", ShellState.setting("accentColor", "#9ad6c6"));
            ShellState.setSetting("accentFromWallpaper", true);
        } else {
            ShellState.setSetting("accentFromWallpaper", false);
            ShellState.setSetting("accentColor", ShellState.setting("accentManual", "#9ad6c6"));
        }
        error = "";
    }
    readonly property var accents: [
        {name: "Mineral", color: "#9ad6c6"},
        {name: "Frost", color: "#a5c8ef"},
        {name: "Lilac", color: "#c8b4e9"},
        {name: "Orchid", color: "#e1acd1"},
        {name: "Ochre", color: "#e0c283"},
        {name: "Clay", color: "#d8ae98"}
    ]
    readonly property var tones: [
        {name: "Charcoal", key: "charcoal", color: "#111214"},
        {name: "Midnight", key: "midnight", color: "#101722"},
        {name: "Warm", key: "warm", color: "#191613"}
    ]
    function luminance(value) {
        const channels = [1, 3, 5].map(index => parseInt(value.slice(index, index + 2), 16) / 255);
        const linear = channels.map(channel => channel <= 0.04045 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4));
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
    }
    function validAccent(value) { return /^#[0-9a-fA-F]{6}$/.test(value) && luminance(value) >= 0.28; }
    function applyCustom() {
        const value = customField.text.trim().toLowerCase();
        if (!validAccent(value)) {
            error = "Use a bright six-digit hex color, such as #9ad6c6.";
            return;
        }
        error = "";
        customField.text = value;
        setAccent(value);
    }
    C.Label { text: "Colors"; font.weight: Font.DemiBold; Layout.fillWidth: true }
    C.Label { text: "Accent"; color: Theme.muted; font.pixelSize: Theme.small; Layout.fillWidth: true }
    C.Toggle {
        Layout.fillWidth: true
        text: "Match wallpaper"
        description: root.fromWallpaper ? "Follows the wallpaper on the focused screen" : "Take the accent from your wallpaper"
        selected: root.fromWallpaper
        onClicked: root.setFromWallpaper(!root.fromWallpaper)
    }
    GridLayout {
        Layout.fillWidth: true
        columns: 3
        rowSpacing: 7
        columnSpacing: 7
        Repeater {
            model: root.accents
            C.Button {
                id: accentButton
                required property var modelData
                text: modelData.name
                selected: !root.fromWallpaper && ShellState.setting("accentColor", "#9ad6c6").toLowerCase() === modelData.color
                implicitHeight: 44
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                onClicked: {
                    root.setAccent(modelData.color);
                    customField.text = modelData.color;
                    root.error = "";
                }
                contentItem: RowLayout {
                    spacing: 7
                    Rectangle {
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        radius: 7
                        color: accentButton.modelData.color
                        C.Icon { anchors.centerIn: parent; visible: accentButton.selected; name: "check"; invert: true; size: 12 }
                    }
                    C.Label { text: accentButton.text; color: accentButton.selected ? Theme.accentText : Theme.text; font.pixelSize: Theme.small; Layout.fillWidth: true }
                }
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 7
        C.Field {
            id: customField
            Layout.fillWidth: true
            text: ShellState.setting("accentColor", "#9ad6c6")
            placeholderText: "#RRGGBB"
            Accessible.name: "Custom accent color"
            maximumLength: 7
            onAccepted: root.applyCustom()
        }
        Rectangle {
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
            radius: 8
            color: root.validAccent(customField.text.trim()) ? customField.text.trim() : Theme.raised
        }
        C.Button { text: "Apply"; onClicked: root.applyCustom() }
    }
    C.Label { visible: root.error !== ""; text: root.error; color: Theme.danger; wrapMode: Text.WordWrap; Layout.fillWidth: true }
    C.Label { text: "Surface"; color: Theme.muted; font.pixelSize: Theme.small; Layout.fillWidth: true; Layout.topMargin: 4 }
    RowLayout {
        Layout.fillWidth: true
        spacing: 7
        Repeater {
            model: root.tones
            C.Button {
                id: toneButton
                required property var modelData
                text: modelData.name
                selected: ShellState.setting("surfaceTone", "charcoal") === modelData.key
                implicitHeight: 42
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                onClicked: ShellState.setSetting("surfaceTone", modelData.key)
                contentItem: RowLayout {
                    spacing: 7
                    Rectangle {
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 18
                        radius: 5
                        color: toneButton.modelData.color
                        C.Icon { anchors.centerIn: parent; visible: toneButton.selected; name: "check"; size: 11 }
                    }
                    C.Label { text: toneButton.text; color: toneButton.selected ? Theme.accentText : Theme.text; font.pixelSize: Theme.small; Layout.fillWidth: true }
                }
            }
        }
    }
    C.Button {
        text: "Reset colors"
        flat: true
        Layout.alignment: Qt.AlignRight
        enabled: root.fromWallpaper || ShellState.setting("accentColor", "#9ad6c6") !== "#9ad6c6" || ShellState.setting("surfaceTone", "charcoal") !== "charcoal"
        onClicked: {
            root.setAccent("#9ad6c6");
            ShellState.setSetting("surfaceTone", "charcoal");
            customField.text = "#9ad6c6";
            root.error = "";
        }
    }
}
