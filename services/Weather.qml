pragma Singleton
import QtQuick
import "../core"

// Today's forecast for the city chosen in Clock and sky, kept once for the whole shell: the bar, the lock screen, the
// Sky card and Find read it here instead of each asking on its own timer. The helper keeps the forecast for 30 minutes,
// so asking every 10 minutes only reaches the network when it is due. Nothing is asked until a city is chosen.
QtObject {
    id: root
    readonly property var location: ShellState.setting("weatherLocation", {})
    readonly property string units: ShellState.setting("weatherUnits", "metric")
    // Changes with the city or the units; a forecast for the old ones is dropped.
    readonly property string key: location && location.name ? location.latitude + "," + location.longitude + "," + units : ""
    property var forecast: null
    function refresh() {
        if (key === "" || !Backend.ready)
            return;
        const asked = key;
        Backend.request("weather.get", {location: location, units: units, refresh: false}, (r, e) => {
            if (!e && asked === root.key)
                root.forecast = r;
        }, {silent: true});
    }
    // Clock and sky fetches on its own (it shows errors and can force a refresh) and hands its answer over here.
    function take(result) {
        if (result && result.location && root.key !== "" && result.units === root.units)
            forecast = result;
    }
    onKeyChanged: {
        forecast = null;
        refresh();
    }
    property Timer timer: Timer {
        interval: 600000
        repeat: true
        triggeredOnStart: true
        running: root.key !== "" && Backend.ready
        onTriggered: root.refresh()
    }
}
