pragma Singleton
import QtQuick
import Quickshell.Io
import "../core"
import "../core/day.js" as Capture
import "../core/logbook.js" as Book

// To-dos and reminders, kept by the helper (helpers/day.py). One timer aims at the next due reminder; whatever falls
// due is handed out once through `fired` and delivered as a signal from "Reminders", which stays in the signal log
// until it is handled. Quiet holds it like any other signal, so the digest lists it.
QtObject {
    id: root
    // The local day `items` describes, as YYYY-MM-DD.
    property string date: ""
    // Items due, snoozed to or done on that day.
    property var items: []
    // Every open to-do, in its manual order.
    property var todos: []
    // The item the bar shows next, or null.
    property var nextItem: null
    // When the next reminder is due (epoch ms); 0 when none is.
    property real fireAt: 0
    property bool loaded: false
    // The Logbook's data: every open order and those cleared in the last two weeks, the sites with their sections, the
    // tags and the saved filters. Loaded only while the Logbook is open.
    property bool logbook: false
    property var orders: []
    property var sites: []
    property var tags: []
    property var filters: []
    // Targets and streaks as of today (helpers/shift.py), or null before the first answer; `enabled` is false when the
    // daily target is 0, and then nothing of the shift or the meter is shown.
    property var momentum: null
    readonly property bool targets: momentum !== null && momentum.enabled
    // The shift start is due: once a day, after the shift start time, until it was done or skipped.
    property bool shiftDue: false
    // Routines with what is due today, their streaks and heat maps (helpers/day.py routine_list).
    property var routines: []
    readonly property var routinesDue: routines.filter(routine => routine.dueToday)
    // The daily target was just reached: the island stamps ON TARGET.
    signal targetReached()
    // Nothing is fired until the settings are in: a reminder that breaks through Quiet needs to know Quiet is on.
    readonly property bool deliver: Object.keys(ShellState.settings).length > 0
    // Fired reminders not yet snoozed, cleared or dismissed, oldest first, as {id, text, at, away, signal, arrivedAt}.
    // Kept for this session only: a restart leaves them in the signal log, without their keys.
    property var arrived: []
    // Something arrived just now: the capsule shakes once and the island grows.
    signal arrival(var item)
    // Each fired item once. `away` is true when it was missed while the shell was off, asleep or locked, and `at`
    // is the time it was due.
    signal fired(var items)
    // A to-do was checked off from the shell: the island stamps it.
    signal cleared()

    function today() {
        const now = new Date();
        return now.getFullYear() + "-" + String(now.getMonth() + 1).padStart(2, "0") + "-" + String(now.getDate()).padStart(2, "0");
    }
    function refresh() {
        const day = today();
        Backend.request("day.list", {date: day}, (result, error) => {
            if (error)
                return;
            root.date = day;
            root.items = result.items;
            root.todos = result.todos;
            root.loaded = true;
        });
        root.loadMomentum();
        root.loadRoutines();
        if (root.logbook)
            root.loadLogbook();
        Backend.request("day.next", {}, (result, error) => {
            if (error)
                return;
            root.nextItem = result.item;
            root.fireAt = result.fireAt || 0;
            root.aim();
        });
    }
    function settings() {
        return {date: today(), daily: ShellState.setting("dailyTarget", 5), weekly: ShellState.setting("weeklyTarget", 25),
                daysOff: ShellState.setting("daysOff", []), weekStart: (ShellState.firstDayOfWeek + 6) % 7};
    }
    function loadMomentum() {
        Backend.request("day.momentum", settings(), (result, error) => root.momentumLoaded(result, error));
    }
    function momentumLoaded(result, error) {
        if (error)
            return;
        const was = momentum;
        momentum = result;
        if (was && was.date === result.date && result.onTarget && !was.onTarget)
            targetReached();
    }
    // The reminder at the shift end time (off by default): a signal from "Shift", given once a day, held by Quiet like any
    // other. Nothing is given when targets are off.
    function checkShiftEnd() {
        if (!deliver || ShellState.locked || !targets || !ShellState.setting("shiftReminder", false))
            return;
        Backend.request("day.shift.reminder", {date: today(), end: ShellState.setting("shiftEnd", "18:00")}, (result, error) => {
            if (!error && result.due)
                Services.post({appName: "Shift", summary: "Shift end", body: "File the shift report in the Logbook (Super+Shift+L, then G S).", event: false});
        });
    }
    function loadRoutines() {
        Backend.request("day.routines.list", {date: today(), daysOff: ShellState.setting("daysOff", []), weekStart: (ShellState.firstDayOfWeek + 6) % 7},
                        (result, error) => root.routinesLoaded(result, error));
    }
    function routinesLoaded(result, error) {
        if (!error)
            routines = result;
    }
    function routineChange(method, params, callback) {
        Backend.request(method, params, (result, error) => {
            if (!error)
                root.loadRoutines();
            if (callback)
                callback(result, error);
        });
    }
    function checkRoutine(id, checked, callback) {
        routineChange("day.routines.check", {id: id, date: today(), checked: checked}, callback);
    }
    // `fields` is {name, rule | TIMES=n, minute, alert}.
    function addRoutine(fields, callback) {
        routineChange("day.routines.add", fields, callback);
    }
    function removeRoutine(id, callback) {
        routineChange("day.routines.delete", {id: id}, callback);
    }
    // A routine with an alert whose time has come and that is not checked in yet is given once, as a signal.
    function checkRoutineAlerts() {
        if (!deliver || ShellState.locked)
            return;
        Backend.request("day.routines.alerts", {date: today()}, (result, error) => {
            if (error)
                return;
            result.forEach(routine => Services.post({appName: "Checks", summary: routine.name, body: "Routine check due"}));
        });
    }
    function loadShift() {
        Backend.request("day.shift.state", {date: today(), start: ShellState.setting("shiftStart", "05:00")}, (result, error) => {
            root.shiftDue = !error && Book.shiftShows(result.due, root.targets);
        });
    }
    // Done or skipped: it shows once a day, so both end it. A target chosen on the last screen is kept for the day.
    function startShift(target, callback) {
        const params = target === undefined || target === null ? {date: today()} : {date: today(), target: target};
        Backend.request("day.shift.start", params, (result, error) => {
            if (!error)
                root.shiftDue = false;
            root.loadMomentum();
            if (callback)
                callback(result, error);
        });
    }
    function carryList(callback) {
        Backend.request("day.carry.list", {date: today()}, callback);
    }
    // `choices` is [{id, action: keep|move|intake|drop, days}]; `date` is the day the orders carry over to.
    function carryApply(choices, date, callback) {
        change("day.carry.apply", {date: date || today(), choices: choices}, callback);
    }
    // With the autoCarry setting on, yesterday's orders with no time move to today by themselves at the shift start.
    function autoCarry(callback) {
        if (!ShellState.setting("autoCarry", false))
            return;
        change("day.carry.auto", {date: today()}, callback);
    }
    function setDay(fields, date, callback) {
        Backend.request("day.days.get", Object.assign({date: date || today()}, fields), callback);
    }
    function report(callback) {
        Backend.request("day.report", {date: today()}, callback);
    }
    function loadLogbook() {
        const since = new Date();
        since.setHours(0, 0, 0, 0);
        since.setDate(since.getDate() - 14);
        Backend.request("day.orders", {since: since.getTime()}, (result, error) => {
            if (!error)
                root.orders = result;
        });
        Backend.request("day.sites.list", {}, (result, error) => {
            if (!error)
                root.sites = result;
        });
        Backend.request("day.tags.list", {}, (result, error) => {
            if (!error)
                root.tags = result;
        });
        Backend.request("day.filters.list", {}, (result, error) => {
            if (!error)
                root.filters = result;
        });
    }
    onLogbookChanged: {
        if (logbook)
            loadLogbook();
    }
    // Clearing an order that has open sub-orders answers {ask}: the Logbook then asks and calls this again.
    function complete(id, subOrders, callback) {
        const params = subOrders === undefined ? {id: id} : {id: id, subOrders: subOrders};
        change("day.complete", params, (result, error) => {
            if (!error && result.ask === 0)
                root.cleared();
            if (callback)
                callback(result, error);
        });
    }
    function undo(callback) {
        change("day.history.undo", {}, callback);
    }
    function redo(callback) {
        change("day.history.redo", {}, callback);
    }
    function search(text, callback) {
        Backend.request("day.search", {text: text}, callback);
    }
    function change(method, params, callback) {
        Backend.request(method, params, (result, error) => {
            if (!error)
                root.refresh();
            if (callback)
                callback(result, error);
        });
    }
    // `parsed` is what core/day.js parse() returned for the capture text.
    function add(parsed, callback) {
        change("day.add", {kind: parsed.kind, text: parsed.text, dueAt: parsed.dueAt || null, repeat: parsed.repeat || null}, callback);
    }
    // A work order with every field of the Logbook's capture (core/day.js capture()).
    function addOrder(fields, callback) {
        change("day.add", fields, callback);
    }
    function update(id, fields, callback) {
        change("day.update", Object.assign({id: id}, fields), callback);
    }
    function done(id, callback) {
        change("day.done", {id: id}, (result, error) => {
            if (!error)
                root.cleared();
            if (callback)
                callback(result, error);
        });
    }
    function undone(id, callback) {
        change("day.undone", {id: id}, callback);
    }
    // The callback receives the removed item, so it can be added back for Undo.
    function remove(id, callback) {
        change("day.delete", {id: id}, callback);
    }
    function snooze(id, until, callback) {
        change("day.snooze", {id: id, until: until}, callback);
    }
    function reorder(ids, callback) {
        change("day.reorder", {ids: ids}, callback);
    }
    function fire() {
        Backend.request("day.fire", {}, (result, error) => {
            if (!error && result.length) {
                root.fired(result);
                result.forEach(item => root.announce(item));
            }
            root.refresh();
        });
    }
    function announce(item) {
        const now = Date.now();
        const said = Capture.arrival(item, now);
        const keys = Capture.choices(item, now);
        // A reminder that fires again (a snooze, a repeat) replaces its older signal.
        const older = arrived.find(event => event.id === item.id);
        if (older)
            Services.dismissNotification(older.signal);
        const id = Services.post({appName: "Reminders", summary: said.summary, body: said.body, header: said.header,
                                  event: true, breaksQuiet: !!item.breaksFocus, actions: keys.map(key => ({identifier: key.identifier, text: key.text}))});
        const entry = {id: item.id, text: item.text, at: item.at, away: !!item.away, repeat: item.repeat || null, breaksQuiet: !!item.breaksFocus,
                       signal: id, arrivedAt: now, choices: keys};
        arrived = arrived.filter(event => event.id !== item.id).concat([entry]);
        arrival(entry);
    }
    // Snooze, Tomorrow or Clear on an arrived event, from its signal or the island. Snooze counts from the click, not
    // from the arrival: a key pressed half an hour later must not land in the past.
    function handle(id, identifier) {
        const event = arrived.find(item => item.id === id);
        if (!event)
            return;
        arrived = arrived.filter(item => item.id !== id);
        Services.dismissNotification(event.signal);
        const key = Capture.choices(event, Date.now()).find(choice => choice.identifier === identifier);
        if (key && key.until > 0) {
            snooze(id, key.until);
        } else if (identifier === "clear") {
            // A repeating reminder moved on to its next time when it fired; only a one-off is checked off.
            if (!event.repeat)
                change("day.done", {id: id});
        }
    }
    property Connections signalLog: Connections {
        target: Services
        function onLocalInvoked(id, identifier) {
            const event = root.arrived.find(item => item.signal === id);
            if (event)
                root.handle(event.id, identifier);
        }
        function onLocalDismissed(id) {
            root.arrived = root.arrived.filter(item => item.signal !== id);
        }
    }

    // Never more than a minute ahead: the timer stands still during suspend, so a reminder that fell due while
    // asleep is noticed soon after resume (and comes out `away`). The same tick notices a new day.
    property Timer timer: Timer {
        onTriggered: {
            if (root.date !== root.today())
                root.refresh();
            root.checkShiftEnd();
            root.checkRoutineAlerts();
            if (root.deliver && root.fireAt > 0 && Date.now() >= root.fireAt && !ShellState.locked)
                root.fire();
            else
                root.aim();
        }
    }
    function aim() {
        timer.interval = root.fireAt > 0 ? Math.min(60000, Math.max(1000, root.fireAt - Date.now())) : 60000;
        timer.restart();
    }
    // Starting up (or the helper restarting) reports what came due while the shell was off. While locked nothing is
    // fired; unlocking reports what fell due meanwhile.
    function start() {
        if (!Backend.ready)
            return;
        if (deliver)
            fire();
        else
            refresh();
    }
    onDeliverChanged: start()
    Component.onCompleted: start()
    property IpcHandler ipc: IpcHandler {
        target: "day"
        function status(): string {
            return JSON.stringify({fireAt: root.fireAt, arrived: root.arrived.map(item => ({id: item.id, text: item.text, at: item.at, away: item.away})),
                                   signals: Services.notifications.filter(n => n.appName === "Reminders").length,
                                   popups: Services.popupIds.filter(id => root.arrived.some(item => item.signal === id)).length});
        }
    }
    property Connections backendState: Connections {
        target: Backend
        function onReadyChanged() {
            root.start();
        }
    }
    // A new target, days off or week start changes every figure.
    property Connections settingsState: Connections {
        target: ShellState
        function onSettingsChanged() {
            if (root.loaded)
                root.loadMomentum();
        }
    }
    property Connections lockState: Connections {
        target: ShellState
        function onLockedChanged() {
            if (!ShellState.locked)
                root.start();
        }
    }
}
