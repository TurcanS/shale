pragma Singleton
import QtQuick
import "minerals.js" as Minerals

QtObject {
    readonly property var surfacePalettes: ({
        charcoal: {background: "#000000", panel: "#111214", surface: "#1b1d20", raised: "#25272b", hover: "#34373c", border: "#303237", text: "#f0ede7", muted: "#a9abb1", disabled: "#777b83"},
        midnight: {background: "#04070d", panel: "#101722", surface: "#1b2531", raised: "#273543", hover: "#35495a", border: "#344352", text: "#edf1f5", muted: "#a9b6c2", disabled: "#778696"},
        warm: {background: "#070605", panel: "#191613", surface: "#241f1b", raised: "#302923", hover: "#40372f", border: "#3a322b", text: "#f1ede6", muted: "#b7ada3", disabled: "#827a73"},
        basalt: {background: "#050709", panel: "#0c0f12", surface: "#16191c", raised: "#202328", hover: "#2b2f35", border: "#2f3338", text: "#f0ece5", muted: "#a7abb1", disabled: "#71757a"}
    })
    readonly property var surfaces: surfacePalettes[ShellState.setting("surfaceTone", "charcoal")] || surfacePalettes.charcoal
    readonly property color background: surfaces.background
    readonly property color panel: surfaces.panel
    readonly property color surface: surfaces.surface
    readonly property string defaultAccent: "#9ad6c6"
    // Shape: panels, then cards and large controls, then small controls (buttons up to 36 px, chips, keycaps).
    readonly property int panelRadius: 16
    readonly property int controlRadius: 12
    readonly property int radiusSmall: 8
    readonly property int panelPadding: 20
    // Spacing steps; everything between controls and sections uses one of these.
    readonly property int gapXs: 4
    readonly property int gapS: 8
    readonly property int gapM: 12
    readonly property int gapL: 16
    readonly property int gapXl: 24
    readonly property int sectionSpacing: gapL
    // Control heights: compact (inline and header buttons), standard, and large (fields, list rows).
    readonly property int controlSmall: 28
    readonly property int controlLarge: 44
    readonly property int iconSmall: 14
    readonly property int icon: 16
    readonly property int iconLarge: 20
    readonly property real disabledOpacity: 0.45
    readonly property int titleSize: 18
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
    readonly property color raised: surfaces.raised
    readonly property color hover: surfaces.hover
    readonly property color border: surfaces.border
    readonly property color text: surfaces.text
    readonly property color muted: surfaces.muted
    // The partner of the accent (the end of the Front's gradient, the hot edge of a fired reminder).
    readonly property color accent2: "#fc7b6d"
    readonly property color accentHover: Qt.hsla(accentHue, accent.hslSaturation, Math.min(1, accent.hslLightness + 0.08), 1)
    readonly property color accentText: contrast(accent, selection) >= 4.5 ? accent : text
    readonly property color disabled: surfaces.disabled
    readonly property color danger: "#db9292"
    readonly property color success: "#a2c6ac"
    readonly property color warning: "#d6ba86"
    // Adwaita when installed; otherwise fontconfig's own sans and monospace (keeps clock digits fixed-width).
    readonly property var installedFonts: Qt.fontFamilies()
    readonly property string font: installedFonts.indexOf("Adwaita Sans") >= 0 ? "Adwaita Sans" : "sans-serif"
    readonly property string mono: installedFonts.indexOf("Adwaita Mono") >= 0 ? "Adwaita Mono" : "monospace"
    // The Day hub's station faces, shipped in assets/fonts (SIL Open Font License): a dot-matrix readout and an
    // instrument label face. The shell's own faces stand in until they load, or if they are missing.
    readonly property FontLoader readoutLoader: FontLoader {
        source: Qt.resolvedUrl("../assets/fonts/Doto-Black.ttf")
    }
    readonly property FontLoader instrumentLoader: FontLoader {
        source: Qt.resolvedUrl("../assets/fonts/ChakraPetch-SemiBold.ttf")
    }
    readonly property string readout: readoutLoader.status === FontLoader.Ready ? readoutLoader.name : mono
    readonly property string instrument: instrumentLoader.status === FontLoader.Ready ? instrumentLoader.name : font
    readonly property int body: ShellState.setting("fontSize", 14)
    // Secondary sizes follow the chosen text size so large text scales everywhere.
    readonly property int label: Math.max(12, body - 1)
    readonly property int small: Math.max(11, body - 2)
    readonly property int caption: Math.max(10, body - 3)
    // In-page titles and headline numbers.
    readonly property int heading: Math.max(20, body + 6)
    // The bar keeps its own fixed sizes so its 32 px height holds at every text size.
    readonly property int barText: 12
    readonly property bool reduced: ShellState.setting("reducedMotion", false)
    // Power saver always trims effects; the setting keeps them trimmed in every mode.
    readonly property bool lowPower: ShellState.powerSaver || ShellState.setting("batterySaving", false)
    readonly property int fast: reduced ? 0 : (lowPower ? 90 : 120)
    readonly property int enter: reduced ? 0 : (lowPower ? 160 : 220)
    readonly property int leave: reduced ? 0 : (lowPower ? 100 : 160)
    function luminance(color) {
        const channel = value => value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
        return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
    }
    function contrast(first, second) {
        const a = luminance(first), b = luminance(second);
        return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
    }
    function mix(first, second, fraction) {
        return Qt.rgba(first.r * (1 - fraction) + second.r * fraction,
                       first.g * (1 - fraction) + second.g * fraction,
                       first.b * (1 - fraction) + second.b * fraction, 1);
    }
    // Slider and progress fills.
    readonly property color fill: mix(selection, accent, 0.70)
    readonly property color activityLevel1: selection
    readonly property color activityLevel2: mix(selection, accent, 0.35)
    readonly property color activityLevel3: fill
    readonly property color activityIdle: mix(raised, selection, 0.65)
    readonly property color activityWindow: mix(raised, accent, 0.45)
    // Watching (video, no input) reads warm against the cool active accent.
    readonly property color activityWatching: mix(raised, warning, 0.78)
    // Distinct, equally muted hues for telling apps apart on one timeline, kept clear of the accent and the
    // watching amber; the last is for "other".
    // The colour that follows an app everywhere (Line, Activity, cards, launcher, volume, workspaces).
    function mineral(app) { return Minerals.color(app); }
    readonly property var activityApps: [accent, mix(raised, Qt.rgba(0.56, 0.71, 0.89, 1), 0.86), mix(raised, Qt.rgba(0.78, 0.64, 0.83, 1), 0.86),
                                         mix(raised, Qt.rgba(0.88, 0.60, 0.60, 1), 0.86), mix(raised, Qt.rgba(0.74, 0.80, 0.52, 1), 0.86),
                                         mix(raised, Qt.rgba(0.70, 0.68, 0.94, 1), 0.86), mix(raised, muted, 0.55)]
}
