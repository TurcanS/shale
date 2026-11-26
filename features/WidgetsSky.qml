import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../core"
import "../services"
import "../core/sky.js" as Sky
import "../components" as C

// The Sky card: the weather Clock and sky shows for its city (the helper keeps the forecast for 30 minutes; this asks
// as often as the bar does) and the sun's path from sunrise to sunset. Opens Clock and sky.
WidgetsCard {
    id: root
    property date now: new Date()
    // False while the card is hidden; nothing is requested then.
    property bool live: false
    readonly property var location: ShellState.setting("weatherLocation", {})
    readonly property bool hasLocation: !!location && !!location.name
    readonly property var weather: Weather.forecast
    readonly property var current: weather && weather.current ? weather.current : null
    readonly property var sun: hasLocation ? Sky.sunTimes(now, location.latitude, location.longitude) : null
    readonly property var sky: Sky.sky(now.getTime(), sun, location)
    panel: "calendar"
    padding: 18
    function degrees(value) {
        return value === null || value === undefined ? "–" : value + "°";
    }
    Accessible.role: Accessible.StaticText
    Accessible.name: root.current ? root.degrees(root.current.temperature) + ", " + root.current.label + ". " + root.sky.status : "Weather"
    ColumnLayout {
        anchors.fill: parent
        spacing: 6
        // Now: icon, temperature, condition and how it feels.
        RowLayout {
            visible: root.hasLocation
            Layout.fillWidth: true
            spacing: 10
            C.Icon {
                name: root.current ? root.current.icon : "cloud"
                size: 26
                color: Theme.textSecondary
                opacity: root.current ? 1 : 0.5
            }
            C.Label {
                visible: !!root.current
                text: root.current ? root.degrees(root.current.temperature) : ""
                font.pixelSize: 30
                font.weight: Font.DemiBold
                font.features: ({"tnum": 1})
                elide: Text.ElideNone
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0
                C.Label {
                    text: root.current ? root.current.label : "Loading weather…"
                    color: root.current ? Theme.text : Theme.textDim
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }
                C.Label {
                    text: root.current ? "Feels " + root.degrees(root.current.feelsLike) : root.location.name || ""
                    color: Theme.textDim
                    font.pixelSize: 12
                    Layout.fillWidth: true
                }
            }
        }
        // No city yet: the sky needs one, chosen in Clock and sky.
        ColumnLayout {
            visible: !root.hasLocation
            Layout.fillWidth: true
            spacing: 2
            RowLayout {
                spacing: 10
                C.Icon {
                    name: "cloud-sun"
                    size: 26
                    color: Theme.textDim
                }
                C.Label {
                    text: "Sky"
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
            }
            C.Label {
                text: "Add a city in Clock and sky to see its weather and the sun's path here."
                color: Theme.textDim
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.topMargin: 4
            }
            C.Button {
                text: "Add city"
                implicitHeight: 32
                Layout.topMargin: 8
                onClicked: ShellState.open("calendar", root.outputName)
            }
        }
        Item {
            Layout.fillHeight: true
        }
        // The sun's path on a 266 × 92 drawing: a dotted arc from sunrise to sunset over the horizon, solid up to the
        // sun, which is filled while it is up.
        Item {
            id: arc
            visible: root.hasLocation
            Layout.fillWidth: true
            Layout.preferredHeight: 88
            readonly property real unitX: width / 266
            readonly property real unitY: height / 92
            readonly property real centreX: width / 2
            readonly property real horizon: 84 * unitY
            readonly property real radiusX: 110 * unitX
            readonly property real radiusY: 72 * unitY
            readonly property real angle: Math.PI * root.sky.done
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: Theme.key
                    strokeWidth: 1.5
                    fillColor: "transparent"
                    startX: 4 * arc.unitX
                    startY: arc.horizon
                    PathLine { x: 262 * arc.unitX; y: arc.horizon }
                }
                ShapePath {
                    strokeColor: Theme.key
                    strokeWidth: 2
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [1, 2.5]
                    fillColor: "transparent"
                    PathAngleArc { centerX: arc.centreX; centerY: arc.horizon; radiusX: arc.radiusX; radiusY: arc.radiusY; startAngle: 180; sweepAngle: 180 }
                }
                ShapePath {
                    strokeColor: root.sky.done > 0.01 ? Theme.accent : "transparent"
                    strokeWidth: 3
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    PathAngleArc { centerX: arc.centreX; centerY: arc.horizon; radiusX: arc.radiusX; radiusY: arc.radiusY; startAngle: 180; sweepAngle: 180 * root.sky.done }
                }
            }
            Rectangle {
                x: arc.centreX - arc.radiusX * Math.cos(arc.angle) - width / 2
                y: arc.horizon - arc.radiusY * Math.sin(arc.angle) - height / 2
                width: 14
                height: 14
                radius: 7
                color: root.sky.up ? Theme.accent : Theme.module
                border.width: 2.5
                border.color: Theme.accent
            }
        }
        RowLayout {
            visible: root.hasLocation
            Layout.fillWidth: true
            spacing: Theme.gapS
            C.Label {
                text: root.sun && root.sun.rise ? Qt.formatDateTime(new Date(root.sun.rise), ShellState.timeFormat) : ""
                color: Theme.textDim
                font.pixelSize: 11
                font.features: ({"tnum": 1})
                Layout.fillWidth: true
                Layout.preferredWidth: 1
            }
            C.Label {
                text: root.sky.status
                font.pixelSize: 11
                font.features: ({"tnum": 1})
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
                Layout.preferredWidth: 2
            }
            C.Label {
                text: root.sun && root.sun.set ? Qt.formatDateTime(new Date(root.sun.set), ShellState.timeFormat) : ""
                color: Theme.textDim
                font.pixelSize: 11
                font.features: ({"tnum": 1})
                horizontalAlignment: Text.AlignRight
                Layout.fillWidth: true
                Layout.preferredWidth: 1
            }
        }
    }
}
