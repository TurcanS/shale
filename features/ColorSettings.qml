import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

ColumnLayout {
    id: root
    spacing: Theme.gapS + 2
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
            ShellState.setSetting("accentManual", ShellState.setting("accentColor", Theme.defaultAccent));
            ShellState.setSetting("accentFromWallpaper", true);
        } else {
            ShellState.setSetting("accentFromWallpaper", false);
            ShellState.setSetting("accentColor", ShellState.setting("accentManual", Theme.defaultAccent));
        }
        error = "";
    }
    readonly property var accents: [
        {name: "Mineral", color: Theme.defaultAccent},
        {name: "Frost", color: "#a5c8ef"},
        {name: "Lilac", color: "#c8b4e9"},
        {name: "Orchid", color: "#e1acd1"},
        {name: "Ochre", color: "#e0c283"},
        {name: "Clay", color: "#d8ae98"},
        {name: "Ember", color: "#fda856"}
    ]
    readonly property var tones: [
        {name: "Charcoal", key: "charcoal"},
        {name: "Midnight", key: "midnight"},
        {name: "Warm", key: "warm"},
        {name: "Basalt", key: "basalt"}
    ]
    function validAccent(value) { return /^#[0-9a-fA-F]{6}$/.test(value) && Theme.luminance(Qt.color(value)) >= 0.28; }
    function applyCustom() {
        const value = customField.text.trim().toLowerCase();
        if (!validAccent(value)) {
            error = "Use a bright six-digit hex color, such as " + Theme.defaultAccent + ".";
            return;
        }
        error = "";
        customField.text = value;
        setAccent(value);
    }
    C.SectionHeader { text: "Accent color" }
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
        rowSpacing: Theme.gapS
        columnSpacing: Theme.gapS
        Repeater {
            model: root.accents
            C.Button {
                id: accentButton
                required property var modelData
                text: modelData.name
                selected: !root.fromWallpaper && ShellState.setting("accentColor", Theme.defaultAccent).toLowerCase() === modelData.color
                implicitHeight: Theme.controlLarge
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                onClicked: {
                    root.setAccent(modelData.color);
                    customField.text = modelData.color;
                    root.error = "";
                }
                contentItem: RowLayout {
                    spacing: Theme.gapS
                    Rectangle {
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        radius: 6
                        color: accentButton.modelData.color
                        C.Icon { anchors.centerIn: parent; visible: accentButton.selected; name: "check"; color: Theme.background; size: 12 }
                    }
                    C.Label { text: accentButton.text; color: accentButton.selected ? Theme.accentText : Theme.text; font.pixelSize: Theme.small; Layout.fillWidth: true }
                }
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.gapS
        C.Field {
            id: customField
            Layout.fillWidth: true
            text: ShellState.setting("accentColor", Theme.defaultAccent)
            placeholderText: "#RRGGBB"
            Accessible.name: "Custom accent color"
            maximumLength: 7
            onAccepted: root.applyCustom()
        }
        Rectangle {
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
            radius: 6
            color: root.validAccent(customField.text.trim()) ? customField.text.trim() : Theme.raised
        }
        C.Button { text: "Apply"; onClicked: root.applyCustom() }
    }
    C.Label { visible: root.error !== ""; text: root.error; color: Theme.danger; wrapMode: Text.WordWrap; Layout.fillWidth: true }
    C.SectionHeader { text: "Surface"; Layout.topMargin: Theme.gapS }
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.gapS
        Repeater {
            model: root.tones
            C.Button {
                id: toneButton
                required property var modelData
                text: modelData.name
                selected: ShellState.setting("surfaceTone", "charcoal") === modelData.key
                implicitHeight: Theme.controlLarge
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                onClicked: ShellState.setSetting("surfaceTone", modelData.key)
                contentItem: RowLayout {
                    spacing: Theme.gapS
                    Rectangle {
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 18
                        radius: 6
                        color: Theme.surfacePalettes[toneButton.modelData.key].panel
                        border.width: 1
                        border.color: Theme.border
                        C.Icon { anchors.centerIn: parent; visible: toneButton.selected; name: "check"; size: 11; color: Theme.accentText }
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
        enabled: root.fromWallpaper || ShellState.setting("accentColor", Theme.defaultAccent) !== Theme.defaultAccent || ShellState.setting("surfaceTone", "charcoal") !== "charcoal"
        onClicked: {
            root.setAccent(Theme.defaultAccent);
            ShellState.setSetting("surfaceTone", "charcoal");
            customField.text = Theme.defaultAccent;
            root.error = "";
        }
    }
}
