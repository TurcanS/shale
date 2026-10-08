import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

// Weather for one chosen city, shown in the calendar. Nothing is requested until a city is chosen.
Rectangle {
    id: root
    readonly property var location: ShellState.setting("weatherLocation", {})
    readonly property bool hasLocation: !!preview || (!!location && !!location.name)
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
    radius: Theme.controlRadius
    color: Theme.surface
    implicitHeight: body.implicitHeight + 24

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
            if (!e)
                weather = r;
        });
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
        });
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
        anchors.margins: 12
        spacing: 10

        // No city yet: a quiet invitation instead of an empty card.
        RowLayout {
            visible: !root.hasLocation && !root.searching
            Layout.fillWidth: true
            spacing: 12
            C.Icon {
                name: "cloud-sun"
                size: 22
                opacity: 0.8
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                C.Label {
                    text: "Weather"
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }
                C.Label {
                    text: "See the forecast here"
                    color: Theme.muted
                    font.pixelSize: Theme.small
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
            spacing: 6
            C.Field {
                id: searchField
                Layout.fillWidth: true
                implicitHeight: 38
                placeholderText: "Search for a city"
                Accessible.name: "Search for a city"
                background: Rectangle {
                    radius: 10
                    color: Theme.raised
                    border.width: searchField.activeFocus ? 1 : 0
                    border.color: Theme.accent
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
                implicitWidth: 34
                implicitHeight: 34
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
                color: Theme.muted
                font.pixelSize: Theme.small
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
                            font.pixelSize: Theme.small
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        C.Label {
                            visible: text !== ""
                            text: resultButton.modelData.region
                            color: Theme.muted
                            font.pixelSize: Theme.caption
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }

        // Current conditions.
        RowLayout {
            visible: root.hasLocation && !root.searching
            Layout.fillWidth: true
            spacing: 12
            C.Icon {
                name: root.weather ? root.weather.current.icon : "cloud"
                size: 32
                opacity: root.weather ? 1 : 0.5
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    C.Label {
                        visible: !!root.weather
                        text: root.weather ? root.degrees(root.weather.current.temperature) : ""
                        font.pixelSize: 24
                        font.weight: Font.DemiBold
                    }
                    C.Label {
                        text: root.weather ? root.weather.current.label : root.loading ? "Loading weather…" : root.error || "Weather unavailable"
                        color: root.weather ? Theme.text : Theme.muted
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
                C.Label {
                    text: {
                        const place = root.hasLocation ? (root.preview ? root.preview.location.name : root.location.name) : "";
                        if (!root.weather)
                            return place;
                        const current = root.weather.current;
                        return "Feels like " + root.degrees(current.feelsLike) + " · " + place;
                    }
                    color: Theme.muted
                    font.pixelSize: Theme.small
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
            C.Button {
                visible: !root.weather && !root.loading
                glyph: "refresh"
                flat: true
                implicitWidth: 32
                implicitHeight: 32
                hint: "Try again"
                onClicked: root.refresh(true)
            }
            C.Button {
                glyph: "more"
                flat: true
                implicitWidth: 32
                implicitHeight: 32
                selected: root.menuOpen
                hint: "Weather options"
                onClicked: root.menuOpen = !root.menuOpen
            }
        }

        // Options replace the forecast row while open.
        RowLayout {
            visible: root.hasLocation && !root.searching && root.menuOpen
            Layout.fillWidth: true
            spacing: 6
            C.Button {
                text: "Change city"
                glyph: "search"
                implicitHeight: 34
                Layout.fillWidth: true
                onClicked: root.startSearch()
            }
            C.Button {
                text: root.units === "metric" ? "Use °F" : "Use °C"
                implicitHeight: 34
                Accessible.name: root.units === "metric" ? "Show temperatures in Fahrenheit" : "Show temperatures in Celsius"
                onClicked: {
                    root.menuOpen = false;
                    ShellState.setSetting("weatherUnits", root.units === "metric" ? "imperial" : "metric");
                }
            }
            C.Button {
                glyph: "trash"
                implicitWidth: 34
                implicitHeight: 34
                hint: "Remove weather"
                onClicked: root.remove()
            }
        }

        // Next three days.
        RowLayout {
            visible: root.hasLocation && !root.searching && !root.menuOpen && !!root.weather && root.weather.days.length > 0
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: root.weather ? root.weather.days : []
                Rectangle {
                    id: dayCell
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: dayColumn.implicitHeight + 12
                    radius: 10
                    color: Theme.raised
                    Accessible.role: Accessible.StaticText
                    Accessible.name: root.dayName(modelData.date) + ", " + modelData.label + ", high " + root.degrees(modelData.high) + ", low " + root.degrees(modelData.low)
                    ColumnLayout {
                        id: dayColumn
                        anchors.centerIn: parent
                        spacing: 3
                        C.Label {
                            text: root.dayName(dayCell.modelData.date)
                            color: Theme.muted
                            font.pixelSize: Theme.caption
                            Layout.alignment: Qt.AlignHCenter
                        }
                        C.Icon {
                            name: dayCell.modelData.icon
                            size: 18
                            Layout.alignment: Qt.AlignHCenter
                        }
                        Row {
                            spacing: 5
                            Layout.alignment: Qt.AlignHCenter
                            C.Label {
                                text: root.degrees(dayCell.modelData.high)
                                font.pixelSize: Theme.caption
                                font.family: Theme.mono
                            }
                            C.Label {
                                text: root.degrees(dayCell.modelData.low)
                                color: Theme.muted
                                font.pixelSize: Theme.caption
                                font.family: Theme.mono
                            }
                        }
                    }
                }
            }
        }

        C.Label {
            visible: root.hasLocation && !root.searching && !!root.weather && !!root.weather.stale
            text: "Offline · updated " + (root.weather ? root.age(root.weather.fetched) : "")
            color: Theme.disabled
            font.pixelSize: Theme.caption
            Layout.fillWidth: true
        }
    }
}
