pragma Singleton
import QtQuick
import "../core"

// To-dos and reminders, kept by the helper (helpers/day.py). One timer aims at the next due reminder; whatever falls
// due is handed out once through `fired`, for the reminder delivery to show.
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
    // Each fired item once. `away` is true when it was missed while the shell was off, asleep or locked, and `at`
    // is the time it was due.
    signal fired(var items)

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
        Backend.request("day.next", {}, (result, error) => {
            if (error)
                return;
            root.nextItem = result.item;
            root.fireAt = result.fireAt || 0;
            root.aim();
        });
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
    function update(id, fields, callback) {
        change("day.update", Object.assign({id: id}, fields), callback);
    }
    function done(id, callback) {
        change("day.done", {id: id}, callback);
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
            if (!error && result.length)
                root.fired(result);
            root.refresh();
        });
    }

    // Never more than a minute ahead: the timer stands still during suspend, so a reminder that fell due while
    // asleep is noticed soon after resume (and comes out `away`). The same tick notices a new day.
    property Timer timer: Timer {
        onTriggered: {
            if (root.date !== root.today())
                root.refresh();
            if (root.fireAt > 0 && Date.now() >= root.fireAt && !ShellState.locked)
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
        if (Backend.ready)
            fire();
    }
    Component.onCompleted: start()
    property Connections backendState: Connections {
        target: Backend
        function onReadyChanged() {
            root.start();
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
