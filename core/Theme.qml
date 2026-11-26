pragma Singleton
import QtQuick
import "palette.js" as Palette

QtObject {
    // Rack surfaces per tone. Charcoal is the design's own set; midnight and warm keep its steps with a tint.
    readonly property var surfaceTones: ({
        charcoal: {backdrop: "#0e0f11", caseColor: "#121316", module: "#1c1e22", moduleAlt: "#17191c", group: "#1f2125", well: "#141518",
                   key: "#2a2d33", keyTile: "#24272c", keySelected: "#2c2f35", keyHover: "#34373d",
                   text: "#efece6", textSecondary: "#c9c6bf", textMuted: "#a7a9ad", textDim: "#8e9196", textFaint: "#6b6f76"},
        midnight: {backdrop: "#0b0e13", caseColor: "#0f131a", module: "#182029", moduleAlt: "#131921", group: "#1b232e", well: "#11161d",
                   key: "#263140", keyTile: "#212b38", keySelected: "#2a3545", keyHover: "#2e3a4a",
                   text: "#edf1f5", textSecondary: "#c5cdd6", textMuted: "#a3aebb", textDim: "#8893a0", textFaint: "#66717f"},
        warm: {backdrop: "#100e0c", caseColor: "#151210", module: "#201c18", moduleAlt: "#1a1714", group: "#231f1b", well: "#171411",
               key: "#302a25", keyTile: "#2a2520", keySelected: "#342e28", keyHover: "#3b342e",
               text: "#f1ede6", textSecondary: "#ccc5bb", textMuted: "#aea69c", textDim: "#968e84", textFaint: "#716a61"}
    })
    readonly property var surfaces: surfaceTones[ShellState.setting("surfaceTone", "charcoal")] || surfaceTones.charcoal
    // Behind panels and lock dimming; the panel box ("case" is reserved in QML); cards and groups inside a panel;
    // strips, stat tiles and zebra rows; grouped settings rows; slider, graph and field backgrounds.
    readonly property color backdrop: surfaces.backdrop
    readonly property color caseColor: surfaces.caseColor
    readonly property color module: surfaces.module
    readonly property color moduleAlt: surfaces.moduleAlt
    readonly property color group: surfaces.group
    readonly property color well: surfaces.well
    // Secondary buttons, empty tracks and icon tiles at rest (list tiles a step darker); the chosen segment.
    readonly property color key: surfaces.key
    readonly property color keyTile: surfaces.keyTile
    readonly property color keySelected: surfaces.keySelected
    readonly property color keyHover: surfaces.keyHover
    // Case edge (drawn as a 1 px inset line), separators, and the edge of chips.
    readonly property color hairline: Qt.rgba(1, 1, 1, 0.06)
    readonly property color separator: Qt.rgba(1, 1, 1, 0.05)
    readonly property color edge: Qt.rgba(1, 1, 1, 0.08)
    // The edge of cards that float on their own: toasts, the OSD, popup notifications and desktop widgets.
    readonly property color cardEdge: Qt.rgba(1, 1, 1, 0.07)
    readonly property color textSecondary: surfaces.textSecondary
    readonly property color textMuted: surfaces.textMuted
    readonly property color textDim: surfaces.textDim
    readonly property color textFaint: surfaces.textFaint
    // Slider and switch thumbs; text and icons on a filled accent (onAccent in the design; QML reads "on…" as a handler).
    readonly property color knob: "#f4f2ee"
    readonly property color accentInk: "#17181a"
    readonly property string defaultAccent: "#9ad6c6"
    // Rack shape: case, module, inner card or row group, key / button / field, segment option, icon tile.
    readonly property int radiusCase: 22
    readonly property int radiusModule: 16
    readonly property int radiusCard: 12
    readonly property int radiusKey: 10
    readonly property int radiusSegment: 7
    readonly property int casePadding: 14
    readonly property int modulePadding: 12
    // The case's drop shadow under its hairline edge.
    readonly property var caseShadow: ({x: 0, y: 30, blur: 60, color: Qt.rgba(0, 0, 0, 0.35)})
    // Spacing steps; everything between controls and sections uses one of these.
    readonly property int gapXs: 4
    readonly property int gapS: 8
    readonly property int gapM: 12
    readonly property int gapL: 16
    readonly property int gapXl: 24
    // Control heights: compact (inline and header buttons), standard, and large (fields, list rows).
    readonly property int controlSmall: 28
    readonly property int controlLarge: 44
    readonly property int icon: 16
    readonly property int iconLarge: 20
    readonly property real disabledOpacity: 0.45
    // How large panels are drawn (Settings → Appearance → Panel size); PanelHost scales each panel by it.
    readonly property real panelScale: ShellState.setting("panelSize", 85) / 100
    property color accent: ShellState.setting("accentColor", defaultAccent)
    // Accent changes (for example from a new wallpaper) cross-fade instead of snapping.
    Behavior on accent {
        ColorAnimation {
            duration: Theme.reduced || Theme.lowPower ? 0 : 450
            easing.type: Easing.InOutQuad
        }
    }
    readonly property real accentHue: accent.hslHue < 0 ? 0 : accent.hslHue
    readonly property real selectionSaturation: accent.hslSaturation < 0.05 ? 0 : Math.max(0.25, Math.min(0.38, accent.hslSaturation * 0.72))
    readonly property color selection: Qt.hsla(accentHue, selectionSaturation, 0.23, 1)
    readonly property color selectionHover: Qt.hsla(accentHue, selectionSaturation, 0.29, 1)
    readonly property int controlHeight: 36
    readonly property color text: surfaces.text
    readonly property color accentHover: Qt.hsla(accentHue, accent.hslSaturation, Math.min(1, accent.hslLightness + 0.08), 1)
    readonly property color accentText: contrast(accent, selection) >= 4.5 ? accent : text
    // "On" backgrounds, the 1 px edge on "on" things, and the glow on live meters and the volume fill.
    readonly property color accentSoft: tint(accent, 0.14)
    readonly property color accentLine: tint(accent, 0.40)
    readonly property color accentGlow: tint(accent, 0.45)
    // Only ever a second chart line: a quiet partner hue across the wheel from the accent, grey for a grey accent.
    readonly property color second: accent.hslSaturation < 0.05 ? textSecondary : Palette.inGamut(0.75, 0.06, Palette.oklch(accent).h + 2.6)
    // Power off and destructive actions: the colour, its text, a muted icon's chip, a danger button's fill, its edge.
    readonly property color danger: "#ff6b5b"
    readonly property color dangerText: "#ffb4a8"
    readonly property color dangerSoft: tint(danger, 0.16)
    readonly property color dangerWash: tint(danger, 0.07)
    readonly property color dangerLine: tint(danger, 0.45)
    readonly property color success: "#a2c6ac"
    readonly property color warning: "#d6ba86"
    // Hanken Grotesk for everything, Martian Mono for rates, signal, hex values and commands. One static file per
    // weight: Qt reads weights from separate files, not from a variable font's instances. When a file is missing,
    // Adwaita when installed, otherwise fontconfig's own sans and monospace (keeps clock digits fixed-width).
    readonly property list<FontLoader> fontFiles: [
        FontLoader { id: sansFile; source: "../assets/fonts/HankenGrotesk/HankenGrotesk-Regular.ttf" },
        FontLoader { source: "../assets/fonts/HankenGrotesk/HankenGrotesk-ExtraLight.ttf" },
        FontLoader { source: "../assets/fonts/HankenGrotesk/HankenGrotesk-Light.ttf" },
        FontLoader { source: "../assets/fonts/HankenGrotesk/HankenGrotesk-Medium.ttf" },
        FontLoader { source: "../assets/fonts/HankenGrotesk/HankenGrotesk-SemiBold.ttf" },
        FontLoader { source: "../assets/fonts/HankenGrotesk/HankenGrotesk-Bold.ttf" },
        FontLoader { id: monoFile; source: "../assets/fonts/MartianMono/MartianMono-Regular.ttf" },
        FontLoader { source: "../assets/fonts/MartianMono/MartianMono-Medium.ttf" },
        FontLoader { source: "../assets/fonts/MartianMono/MartianMono-SemiBold.ttf" },
        FontLoader { source: "../assets/fonts/MartianMono/MartianMono-Bold.ttf" }
    ]
    readonly property var installedFonts: Qt.fontFamilies()
    readonly property string font: sansFile.status === FontLoader.Ready ? sansFile.name
                                   : installedFonts.indexOf("Adwaita Sans") >= 0 ? "Adwaita Sans" : "sans-serif"
    readonly property string mono: monoFile.status === FontLoader.Ready ? monoFile.name
                                   : installedFonts.indexOf("Adwaita Mono") >= 0 ? "Adwaita Mono" : "monospace"
    readonly property int body: ShellState.setting("fontSize", 14)
    // Secondary sizes follow the chosen text size so large text scales everywhere. Descriptions and subtitles never
    // go under 12 px, captions under 11, so small text sizes stay readable.
    readonly property int label: Math.max(12, body - 1)
    readonly property int small: Math.max(12, body - 2)
    readonly property int caption: Math.max(11, body - 3)
    // In-page titles and headline numbers.
    readonly property int heading: Math.max(20, body + 6)
    readonly property bool reduced: ShellState.setting("reducedMotion", false)
    // Power saver always trims effects; the setting keeps them trimmed in every mode.
    readonly property bool lowPower: ShellState.powerSaver || ShellState.setting("batterySaving", false)
    readonly property int fast: reduced ? 0 : (lowPower ? 90 : 120)
    readonly property int enter: reduced ? 0 : (lowPower ? 160 : 220)
    readonly property int leave: reduced ? 0 : (lowPower ? 100 : 160)
    // Rack motion: panels rise this far while fading in and leave quicker; switch knobs slide; presses scale down.
    readonly property int panelRise: reduced ? 0 : 8
    readonly property int panelEnter: reduced ? 0 : (lowPower ? 120 : 180)
    readonly property int panelLeave: reduced ? 0 : (lowPower ? 90 : 130)
    readonly property int slide: reduced ? 0 : (lowPower ? 100 : 160)
    readonly property int press: reduced || lowPower ? 0 : 80
    readonly property real pressScale: 0.97
    // A whole row (a setting, a list entry) gives only a little under the pointer; a key gives more.
    readonly property real rowPressScale: 0.99
    // Hover and press tints for keys and rows without a fill of their own, translucent so they work on any surface.
    // Keys take the stronger one; whole rows the lighter, so a long list doesn't flash.
    function keyWash(down) {
        return Qt.rgba(1, 1, 1, down ? 0.1 : 0.06);
    }
    function rowWash(down) {
        return Qt.rgba(1, 1, 1, down ? 0.06 : 0.035);
    }
    // cubic-bezier(.2, .8, .2, 1) for Easing.BezierSpline.
    readonly property var easeOut: [0.2, 0.8, 0.2, 1, 1, 1]
    function luminance(color) {
        const channel = value => value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
        return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
    }
    function contrast(first, second) {
        const a = luminance(first), b = luminance(second);
        return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
    }
    // A colour at the given opacity, for washes, edges and see-through surfaces drawn from a token.
    function tint(color, opacity) {
        return Qt.rgba(color.r, color.g, color.b, opacity);
    }
    function mix(first, second, fraction) {
        return Qt.rgba(first.r * (1 - fraction) + second.r * fraction,
                       first.g * (1 - fraction) + second.g * fraction,
                       first.b * (1 - fraction) + second.b * fraction, 1);
    }
}
