import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

// Settings → Appearance → Colour: the accent from the wallpaper or a fixed swatch, any hex colour, and the tone of
// the panels.
ColumnLayout {
    id: root
    spacing: 8
    property string error: ""
    readonly property bool fromWallpaper: ShellState.setting("accentFromWallpaper", false)
    readonly property string accentColor: ShellState.setting("accentColor", Theme.defaultAccent).toLowerCase()
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
        {name: "Clay", color: "#d8ae98"}
    ]
    readonly property var tones: [
        {name: "Charcoal", key: "charcoal"},
        {name: "Midnight", key: "midnight"},
        {name: "Warm", key: "warm"}
    ]
    function validAccent(value) { return /^#[0-9a-fA-F]{6}$/.test(value) && Theme.luminance(Qt.color(value)) >= 0.28; }
    function applyCustom() {
        const value = customField.text.trim().toLowerCase();
        if (!validAccent(value)) {
            error = "Use a bright six-digit hex colour, such as " + Theme.defaultAccent + ".";
            return;
        }
        error = "";
        customField.text = value;
        setAccent(value);
    }
    // A chosen swatch or the wallpaper key wears a 2 px ring of its colour, a little away from its edge.
    component Ring: Rectangle {
        property color tint: Theme.accent
        anchors.fill: parent
        anchors.margins: -4
        radius: height / 2
        color: "transparent"
        border.width: 2
        border.color: tint
    }
    C.SectionHeader {
        text: "Colour"
        C.Button {
            text: "Reset colours"
            flat: true
            implicitHeight: 28
            labelSize: Theme.small
            foreground: enabled ? (hovered || visualFocus ? Theme.text : Theme.textDim) : Theme.textFaint
            enabled: root.fromWallpaper || root.accentColor !== Theme.defaultAccent || ShellState.setting("surfaceTone", "charcoal") !== "charcoal"
            onClicked: {
                root.setAccent(Theme.defaultAccent);
                ShellState.setSetting("surfaceTone", "charcoal");
                customField.text = Theme.defaultAccent;
                root.error = "";
            }
        }
    }
    C.Group {
        C.SettingRow {
            label: "Accent colour"
            description: root.fromWallpaper ? "Follows the wallpaper on the focused screen" : "Taken from the wallpaper, or fixed"
            C.Button {
                id: wallpaperKey
                text: "From wallpaper"
                selected: root.fromWallpaper
                implicitHeight: 28
                leftPadding: 10
                rightPadding: 10
                labelSize: 12
                cornerRadius: 14
                foreground: Theme.text
                Layout.rightMargin: 4
                Accessible.role: Accessible.RadioButton
                Accessible.checkable: true
                Accessible.checked: selected
                onClicked: root.setFromWallpaper(true)
                background: Rectangle {
                    radius: 14
                    color: wallpaperKey.hovered || wallpaperKey.visualFocus || wallpaperKey.down ? Theme.keyHover : Theme.key
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                    C.Raise {
                        resting: true
                        sunk: wallpaperKey.sunk
                    }
                    Ring {
                        visible: wallpaperKey.selected
                    }
                }
            }
            Repeater {
                model: root.accents
                C.Button {
                    id: swatch
                    required property var modelData
                    selected: !root.fromWallpaper && root.accentColor === modelData.color
                    hint: modelData.name + " · " + modelData.color
                    implicitWidth: 28
                    implicitHeight: 28
                    padding: 0
                    cornerRadius: 14
                    Layout.leftMargin: 2
                    Accessible.role: Accessible.RadioButton
                    Accessible.checkable: true
                    Accessible.checked: selected
                    onClicked: {
                        root.setAccent(modelData.color);
                        customField.text = modelData.color;
                        root.error = "";
                    }
                    background: Rectangle {
                        radius: 14
                        color: swatch.modelData.color
                        Ring {
                            visible: swatch.selected || swatch.hovered
                            tint: swatch.selected ? swatch.modelData.color : Theme.edge
                        }
                    }
                    contentItem: Item {}
                }
            }
        }
        C.SettingRow {
            label: "Custom colour"
            description: root.error || "Any bright six-digit hex colour"
            descriptionColor: root.error ? Theme.dangerText : Theme.textDim
            Rectangle {
                implicitWidth: 20
                implicitHeight: 20
                radius: 10
                color: root.validAccent(customField.text.trim()) ? customField.text.trim() : Theme.key
            }
            C.Field {
                id: customField
                Layout.preferredWidth: 120
                implicitHeight: 32
                font.family: Theme.mono
                font.pixelSize: Theme.small
                text: ShellState.setting("accentColor", Theme.defaultAccent)
                placeholderText: "#RRGGBB"
                Accessible.name: "Custom accent colour"
                maximumLength: 7
                onAccepted: root.applyCustom()
            }
            C.Button {
                text: "Apply"
                implicitHeight: 32
                onClicked: root.applyCustom()
            }
        }
        C.ChoiceRow {
            settingKey: "surfaceTone"
            label: "Surface"
            description: "The tone of every panel"
            model: root.tones.map(tone => ({key: tone.key, text: tone.name}))
            current: ShellState.setting("surfaceTone", "charcoal")
            onActivated: key => ShellState.setSetting("surfaceTone", key)
        }
    }
}
