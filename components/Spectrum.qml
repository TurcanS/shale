import QtQuick
import "../core"
import "../services"

// Live output spectrum. Levels come from the shared cava process in NowPlaying, which runs only
// while some visualizer is active; with fewer bars each bar shows the peak of its cava bands.
Item {
    id: root
    property bool active: false
    property int bars: 32
    property color color: Theme.accent
    // Base of each bar; defaults to a faded top colour.
    property color secondary: Qt.rgba(color.r, color.g, color.b, 0.15)
    Behavior on color {
        ColorAnimation {
            duration: Theme.reduced ? 0 : 600
        }
    }
    Behavior on secondary {
        ColorAnimation {
            duration: Theme.reduced ? 0 : 600
        }
    }
    property real spacing: 3
    // Shortest bar while active, so a quiet passage still reads as live.
    property real floor: 2
    property real maxRadius: 3
    // Exponent applied to levels; below 1 lifts quiet passages so small visualizers stay lively.
    property real curve: 1
    // False when cava is not installed, so callers can hide related controls.
    readonly property bool available: NowPlaying.available
    readonly property var levels: {
        const source = NowPlaying.levels;
        if (!active || !source.length || bars === source.length)
            return active ? source : [];
        const result = [];
        for (let i = 0; i < bars; i++) {
            const from = Math.floor(i * source.length / bars), to = Math.max(from + 1, Math.floor((i + 1) * source.length / bars));
            let peak = 0;
            for (let j = from; j < to; j++)
                peak = Math.max(peak, source[j] || 0);
            result.push(peak);
        }
        return result;
    }
    property bool registered: false
    function sync() {
        const want = active && available;
        if (want === registered)
            return;
        registered = want;
        if (want)
            NowPlaying.acquire();
        else
            NowPlaying.release();
    }
    onActiveChanged: sync()
    onAvailableChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: if (registered)
        NowPlaying.release()
    Row {
        anchors.fill: parent
        spacing: root.spacing
        Repeater {
            model: root.bars
            Rectangle {
                required property int index
                readonly property real level: Math.pow(Math.min(1, (root.levels[index] || 0) / 1000), root.curve)
                anchors.bottom: parent.bottom
                width: (root.width - root.spacing * (root.bars - 1)) / root.bars
                // A small floor keeps a resting baseline visible while audio fades in.
                height: root.active ? Math.max(root.floor, level * root.height) : 0
                topLeftRadius: Math.min(width / 2, root.maxRadius)
                topRightRadius: topLeftRadius
                gradient: Gradient {
                    GradientStop { position: 0; color: root.color }
                    GradientStop { position: 1; color: Qt.rgba(root.secondary.r, root.secondary.g, root.secondary.b, 0.45) }
                }
                Behavior on height {
                    NumberAnimation {
                        duration: Theme.reduced ? 0 : 80
                        easing.type: Easing.OutQuad
                    }
                }
            }
        }
    }
}
