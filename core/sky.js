.pragma library
// The sun over a place for Clock and sky and the desktop Sky card: today's sunrise and sunset, and how far along
// its arc the sun is. Worked out from the place's position, with no request, in this computer's time.

// The sunrise equation (NOAA's simplified form, about a minute off): times in ms, or polar "day" / "night".
function sunTimes(date, latitude, longitude) {
    const rad = Math.PI / 180;
    const noon = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 12);
    const days = noon.getTime() / 86400000 + 2440587.5 - 2451545;
    const mean = Math.round(days + longitude / 360) - longitude / 360;
    const anomaly = (357.5291 + 0.98560028 * mean) % 360;
    const centre = 1.9148 * Math.sin(anomaly * rad) + 0.02 * Math.sin(2 * anomaly * rad) + 0.0003 * Math.sin(3 * anomaly * rad);
    const ecliptic = (anomaly + centre + 282.9372) % 360;
    const transit = 2451545 + mean + 0.0053 * Math.sin(anomaly * rad) - 0.0069 * Math.sin(2 * ecliptic * rad);
    const declination = Math.asin(Math.sin(ecliptic * rad) * Math.sin(23.4397 * rad));
    const hour = (Math.sin(-0.833 * rad) - Math.sin(latitude * rad) * Math.sin(declination)) / (Math.cos(latitude * rad) * Math.cos(declination));
    if (hour > 1)
        return {polar: "night"};
    if (hour < -1)
        return {polar: "day"};
    const half = Math.acos(hour) / rad / 360;
    return {rise: (transit - half - 2440587.5) * 86400000, set: (transit + half - 2440587.5) * 86400000};
}

function span(ms) {
    const minutes = Math.max(1, Math.round(ms / 60000));
    return minutes < 60 ? minutes + " min" : Math.floor(minutes / 60) + " h " + String(minutes % 60).padStart(2, "0");
}

// How far the sun is along today's arc (0 … 1), whether it is up, and the line under the arc, at `now` (ms).
function sky(now, sun, place) {
    if (!sun)
        return {done: 0, up: false, status: ""};
    if (sun.polar)
        return {done: sun.polar === "day" ? 0.5 : 0, up: sun.polar === "day", status: sun.polar === "day" ? "Sun up all day" : "No sunrise today"};
    if (now < sun.rise)
        return {done: 0, up: false, status: "Rises in " + span(sun.rise - now)};
    if (now <= sun.set)
        return {done: (now - sun.rise) / (sun.set - sun.rise), up: true, status: "Sets in " + span(sun.set - now)};
    const next = sunTimes(new Date(now + 86400000), place.latitude, place.longitude);
    return {done: 1, up: false, status: next.rise ? "Rises in " + span(next.rise - now) : ""};
}
