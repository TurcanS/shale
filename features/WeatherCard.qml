import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../core"
import "../services"
import "../core/sky.js" as Sky
import "../components" as C

// The sky module of Clock and sky: weather for one chosen city and the sun's path over it. Nothing is requested
// until a city is chosen.
Rectangle {
    id: root
    readonly property var location: ShellState.setting("weatherLocation", {})
    readonly property bool hasLocation: !!preview || (!!location && !!location.name)
    // Changes with the city, so the forecast is fetched again for the new one.
    readonly property string locationKey: hasLocation && !preview ? location.latitude + "," + location.longitude : ""
    readonly property string units: ShellState.setting("weatherUnits", "metric")
    // Fixed data for UI previews; disables all requests.
    property var preview: null
    property var previewResults: null
    property var weather: preview
    property string error: ""
    property bool loading: false
    property int generation: 0
    property bool searching: previewResults !== null
    property string query: ""
    property var results: previewResults || []
    property bool searchBusy: false
    property string searchError: ""
    property int searchGeneration: 0
    property bool menuOpen: false
    readonly property int now: Math.floor(clock.stamp / 1000)
    radius: Theme.radiusModule
    color: Theme.module
    implicitHeight: body.implicitHeight + 24
    readonly property var place: preview ? preview.location || null : hasLocation ? location : null
    // Today's sunrise and sunset worked out from the city's position (no extra request), in this computer's time.
    readonly property var sun: place ? Sky.sunTimes(new Date(clock.stamp), place.latitude, place.longitude) : null

    function refresh(force) {
        if (preview || !hasLocation || !Backend.ready)
            return;
        const request = ++generation;
        loading = true;
        Backend.request("weather.get", {location: location, units: units, refresh: !!force}, (r, e) => {
            if (request !== generation)
                return;
            loading = false;
            error = e ? e.message : (r.stale ? r.warning || "" : "");
            if (!e) {
                weather = r;
                Weather.take(r);
            }
        }, {owner: root});
    }
    function startSearch() {
        menuOpen = false;
        searching = true;
        query = "";
        results = [];
        searchError = "";
        searchField.text = "";
        searchField.forceActiveFocus();
    }
    function stopSearch() {
        searching = false;
        searchGeneration++;
        searchBusy = false;
    }
    function search() {
        const text = query.trim();
        const request = ++searchGeneration;
        if (text.length < 2) {
            results = [];
            searchBusy = false;
            searchError = "";
            return;
        }
        searchBusy = true;
        Backend.request("weather.search", {query: text}, (r, e) => {
            if (request !== searchGeneration)
                return;
            searchBusy = false;
            searchError = e ? e.message : r.results.length ? "" : "No cities match “" + text + "”";
            results = e ? [] : r.results;
        }, {owner: root});
    }
    function choose(place) {
        weather = null;
        error = "";
        ShellState.setSetting("weatherLocation", {name: place.name, region: place.region || "", latitude: place.latitude, longitude: place.longitude});
        stopSearch();
    }
    function remove() {
        menuOpen = false;
        generation++;
        weather = null;
        error = "";
        loading = false;
        ShellState.setSetting("weatherLocation", {});
    }
    function degrees(value) {
        return value === null || value === undefined ? "–" : value + "°";
    }
    function age(seconds) {
        const minutes = Math.max(0, Math.round((now - seconds) / 60));
        return minutes < 1 ? "just now" : minutes < 60 ? minutes + " min ago" : Math.round(minutes / 60) + " h ago";
    }
    // How far the sun is along today's arc (0 … 1), whether it is up, and the line under the arc.
    readonly property var sky: Sky.sky(clock.stamp, sun, place)
    function dayName(date) {
        const parts = String(date).split("-").map(Number);
        return Qt.locale().dayName(new Date(parts[0], parts[1] - 1, parts[2]).getDay(), Locale.ShortFormat);
    }
    onLocationKeyChanged: {
        weather = null;
        error = "";
        refresh(false);
    }
    onUnitsChanged: refresh(false)
    Component.onCompleted: refresh(false)
    Connections {
        target: Backend
        function onReadyChanged() {
            if (Backend.ready)
                root.refresh(false);
        }
    }
    Timer {
        id: clock
        property double stamp: Date.now()
        interval: 60000
        repeat: true
        running: true
        // The backend keeps forecasts for 30 minutes, so this refetches at most that often.
        onTriggered: {
            stamp = Date.now();
            root.refresh(false);
        }
    }
    Timer {
        id: searchDelay
        interval: 350
        onTriggered: root.search()
    }

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 12
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 6

        // No city yet: a quiet invitation instead of an empty module.
        RowLayout {
            visible: !root.hasLocation && !root.searching
            Layout.fillWidth: true
            spacing: Theme.gapM
            C.Icon {
                name: "cloud-sun"
                size: 30
                color: Theme.textDim
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                C.Label {
                    text: "Weather"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }
                C.Label {
                    text: "See the forecast and the sun's path here"
                    color: Theme.textDim
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
            C.Button {
                text: "Add city"
                implicitHeight: 32
                onClicked: root.startSearch()
            }
        }

        // City search.
        RowLayout {
            visible: root.searching
            Layout.fillWidth: true
            spacing: Theme.gapS
            C.Field {
                id: searchField
                Layout.fillWidth: true
                implicitHeight: 36
                placeholderText: "Search for a city"
                Accessible.name: "Search for a city"
                background: Rectangle {
                    radius: Theme.radiusKey
                    color: Theme.well
                    border.width: 1
                    border.color: searchField.activeFocus ? Theme.accentLine : "transparent"
                }
                onTextChanged: {
                    root.query = text;
                    searchDelay.restart();
                }
                onAccepted: {
                    searchDelay.stop();
                    if (root.results.length)
                        root.choose(root.results[0]);
                    else
                        root.search();
                }
                Keys.onEscapePressed: event => {
                    root.stopSearch();
                    event.accepted = true;
                }
            }
            C.Button {
                glyph: "close"
                flat: true
                implicitWidth: 32
                implicitHeight: 32
                hint: "Cancel search"
                onClicked: root.stopSearch()
            }
        }
        ColumnLayout {
            visible: root.searching && (root.results.length > 0 || root.searchBusy || root.searchError !== "")
            Layout.fillWidth: true
            spacing: 2
            C.Label {
                visible: root.results.length === 0
                text: root.searchBusy ? "Searching…" : root.searchError
                color: Theme.textDim
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.leftMargin: 4
            }
            Repeater {
                model: root.results.slice(0, 5)
                C.Button {
                    id: resultButton
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: 42
                    flat: true
                    // Enter picks the first match, so mark it.
                    selected: index === 0
                    Accessible.name: modelData.name + (modelData.region ? ", " + modelData.region : "")
                    onClicked: root.choose(modelData)
                    contentItem: ColumnLayout {
                        spacing: 0
                        C.Label {
                            text: resultButton.modelData.name
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        C.Label {
                            visible: text !== ""
                            text: resultButton.modelData.region
                            color: Theme.textDim
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }

        // Now: icon, temperature, condition and place, then the next three days.
        RowLayout {
            visible: root.hasLocation && !root.searching
            Layout.fillWidth: true
            spacing: Theme.gapM
            C.Icon {
                name: root.weather ? root.weather.current.icon : "cloud"
                size: 30
                color: Theme.textSecondary
                opacity: root.weather ? 1 : 0.5
            }
            C.Label {
                visible: !!root.weather
                text: root.weather ? root.degrees(root.weather.current.temperature) : ""
                font.pixelSize: 28
                font.weight: 650
                font.features: ({"tnum": 1})
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 1
                C.Label {
                    text: root.weather ? root.weather.current.label : root.loading ? "Loading weather…" : root.error || "Weather unavailable"
                    color: root.weather ? Theme.text : Theme.textDim
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }
                C.Label {
                    text: {
                        const place = root.place ? root.place.name : "";
                        if (!root.weather)
                            return place;
                        const now = root.weather.current;
                        const known = value => value !== null && value !== undefined;
                        // Wind as people say it: its speed and the side it blows from. The line is short: the place must fit.
                        const from = known(now.windFrom) ? " " + ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Math.round(now.windFrom / 45) % 8] : "";
                        const wind = known(now.wind) ? " · " + now.wind + (root.weather.units === "imperial" ? " mph" : " km/h") + from : "";
                        return "Feels " + root.degrees(now.feelsLike) + wind + " · " + place;
                    }
                    color: Theme.textDim
                    font.pixelSize: 12
                    Layout.fillWidth: true
                }
            }
            Row {
                visible: !!root.weather && root.weather.days.length > 0 && !root.menuOpen
                spacing: Theme.gapM
                Repeater {
                    model: root.weather ? root.weather.days : []
                    Column {
                        id: dayCell
                        required property var modelData
                        spacing: 1
                        Accessible.role: Accessible.StaticText
                        Accessible.name: root.dayName(modelData.date) + ", " + modelData.label + ", high " + root.degrees(modelData.high) + ", low " + root.degrees(modelData.low)
                        C.Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.dayName(dayCell.modelData.date)
                            color: Theme.textDim
                            font.pixelSize: 11
                        }
                        C.Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.degrees(dayCell.modelData.high)
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            font.features: ({"tnum": 1})
                        }
                    }
                }
            }
            C.Button {
                visible: !root.weather && !root.loading
                glyph: "refresh"
                flat: true
                implicitWidth: 28
                implicitHeight: 28
                hint: "Try again"
                onClicked: root.refresh(true)
            }
            C.Button {
                glyph: "more"
                flat: true
                implicitWidth: 28
                implicitHeight: 28
                selected: root.menuOpen
                hint: "Weather options"
                Layout.leftMargin: -4
                onClicked: root.menuOpen = !root.menuOpen
            }
        }

        // Options replace the sky while open.
        RowLayout {
            visible: root.hasLocation && !root.searching && root.menuOpen
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: Theme.gapS
            C.Button {
                text: "Change city"
                glyph: "search"
                implicitHeight: 32
                Layout.fillWidth: true
                onClicked: root.startSearch()
            }
            C.Button {
                text: root.units === "metric" ? "Use °F" : "Use °C"
                implicitHeight: 32
                Accessible.name: root.units === "metric" ? "Show temperatures in Fahrenheit" : "Show temperatures in Celsius"
                onClicked: {
                    root.menuOpen = false;
                    ShellState.setSetting("weatherUnits", root.units === "metric" ? "imperial" : "metric");
                }
            }
            C.Button {
                glyph: "trash"
                implicitWidth: 32
                implicitHeight: 32
                hint: "Remove weather"
                onClicked: root.remove()
            }
        }

        // The sun's path: a dotted arc from sunrise to sunset, drawn solid up to where the sun is now.
        Item {
            id: arc
            visible: !!root.sun && !root.searching && !root.menuOpen
            Layout.fillWidth: true
            Layout.preferredHeight: 58
            readonly property real centreX: width / 2
            readonly property real radiusX: width * 160 / 392
            readonly property real angle: Math.PI * root.sky.done
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: Theme.key
                    strokeWidth: 1.5
                    fillColor: "transparent"
                    startX: 0
                    startY: 52
                    PathLine { x: arc.width; y: 52 }
                }
                ShapePath {
                    strokeColor: Theme.key
                    strokeWidth: 2
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [1, 2.5]
                    fillColor: "transparent"
                    PathAngleArc { centerX: arc.centreX; centerY: 52; radiusX: arc.radiusX; radiusY: 46; startAngle: 180; sweepAngle: 180 }
                }
                ShapePath {
                    strokeColor: root.sky.done > 0.01 ? Theme.accent : "transparent"
                    strokeWidth: 2.5
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    PathAngleArc { centerX: arc.centreX; centerY: 52; radiusX: arc.radiusX; radiusY: 46; startAngle: 180; sweepAngle: 180 * root.sky.done }
                }
            }
            Rectangle {
                x: arc.centreX - arc.radiusX * Math.cos(arc.angle) - width / 2
                y: 52 - 46 * Math.sin(arc.angle) - height / 2
                width: 12
                height: 12
                radius: 6
                color: root.sky.up ? Theme.accent : Theme.module
                border.width: 2
                border.color: Theme.accent
            }
        }
        RowLayout {
            visible: arc.visible
            Layout.fillWidth: true
            spacing: Theme.gapS
            C.Label {
                text: root.sun && root.sun.rise ? "Sunrise " + Qt.formatDateTime(new Date(root.sun.rise), ShellState.timeFormat) : ""
                color: Theme.textDim
                font.pixelSize: 12
                font.features: ({"tnum": 1})
                Layout.fillWidth: true
                Layout.preferredWidth: 1
            }
            C.Label {
                text: root.sky.status
                font.pixelSize: 12
                font.features: ({"tnum": 1})
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
                Layout.preferredWidth: 1
            }
            C.Label {
                text: root.sun && root.sun.set ? "Sunset " + Qt.formatDateTime(new Date(root.sun.set), ShellState.timeFormat) : ""
                color: Theme.textDim
                font.pixelSize: 12
                font.features: ({"tnum": 1})
                horizontalAlignment: Text.AlignRight
                Layout.fillWidth: true
                Layout.preferredWidth: 1
            }
        }

        C.Label {
            visible: root.hasLocation && !root.searching && !!root.weather && !!root.weather.stale
            text: "Offline · updated " + (root.weather ? root.age(root.weather.fetched) : "")
            color: Theme.textDim
            font.pixelSize: 11
            Layout.fillWidth: true
        }
    }
}
