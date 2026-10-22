import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "../components" as C
import "../core/day.js" as DayText

// Settings → Backup: copy your settings to a file, and bring them back here or on another computer.
ColumnLayout {
    id: root
    spacing: Theme.gapM
    property bool busy: false
    property string result: ""
    property bool failed: false
    function transfer(method) {
        busy = true;
        result = "";
        Backend.request(method, {path: pathField.text.trim()}, (r, e) => {
            busy = false;
            failed = !!e;
            if (e) {
                result = e.message;
                return;
            }
            if (method === "settings.export") {
                result = r.count ? "Saved " + r.count + " setting" + (r.count === 1 ? "" : "s") + " to " + r.path : "Saved to " + r.path + ". Everything is at its default, so there was nothing to save.";
                return;
            }
            ShellState.settings = r.settings;
            ShellState.settingsSaved();
            result = (r.applied.length ? "Applied " + r.applied.length + " setting" + (r.applied.length === 1 ? "" : "s") + "." : "Nothing to apply.")
                + (r.skipped.length ? " Skipped " + r.skipped.join(", ") + (r.skipped.indexOf("shortcuts") >= 0 ? " (their keys are taken here)" : "") + "." : "")
                + (r.problem ? " " + r.problem : "");
            failed = !!r.problem;
        });
    }
    C.Label {
        text: "Save your settings to a file to keep a copy or move them to another computer. Usage history, pinned apps, your weather location and folders stay out of it."
        color: Theme.muted
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    C.Label {
        text: "File"
        Layout.fillWidth: true
        Layout.topMargin: Theme.gapS
    }
    C.Field {
        id: pathField
        Layout.fillWidth: true
        Accessible.name: "Backup file"
        text: "~/shale-settings.json"
        onTextEdited: root.result = ""
        onAccepted: root.transfer("settings.export")
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.gapS
        C.Button {
            text: "Export"
            glyph: "copy"
            accent: true
            enabled: !root.busy && Backend.ready
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            onClicked: root.transfer("settings.export")
        }
        C.Button {
            text: "Import"
            glyph: "folder"
            enabled: !root.busy && Backend.ready
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            onClicked: root.transfer("settings.import")
        }
    }
    C.Label {
        visible: root.result !== ""
        text: root.result
        color: root.failed ? Theme.danger : Theme.success
        font.pixelSize: Theme.small
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    C.Caption {
        text: "Importing replaces the settings the file has and keeps the rest. Shortcuts come along when their keys are free on this computer. The settings from before each change are kept in ~/.config/shale/config.previous.json."
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        Layout.topMargin: Theme.gapS
    }
    // Orders, routines and shifts live in their own file; this exports, imports and copies it.
    property string orderFormat: "json"
    property string orderResult: ""
    property bool orderFailed: false
    function orderPath(extension) {
        return orderPathField.text.trim().replace(/\.[A-Za-z0-9]+$/, "") + extension;
    }
    function orderDone(text, error) {
        busy = false;
        orderFailed = !!error;
        orderResult = error ? error.message : text;
    }
    function exportOrders() {
        busy = true;
        orderResult = "";
        const path = orderPath({json: ".json", csv: ".csv", md: ".md"}[orderFormat]);
        Backend.request("day.export", {format: orderFormat, path: path}, (r, e) => orderDone(e ? "" : "Saved " + r.count + " order" + (r.count === 1 ? "" : "s") + " to " + r.path, e));
    }
    // A .json file is a Shale export, a .csv a Todoist export, anything else a plain list with one order per line.
    function importOrders() {
        const path = orderPathField.text.trim();
        const source = path.endsWith(".json") ? "json" : path.endsWith(".csv") ? "todoist" : "plain";
        busy = true;
        orderResult = "";
        Backend.request("day.import", {source: source, path: path}, (r, e) => {
            if (e || !r.lines) {
                orderDone(e ? "" : "Added " + r.added + " order" + (r.added === 1 ? "" : "s") + (r.skipped.length ? ", skipped " + r.skipped.length + ": " + r.skipped.slice(0, 2).join("; ") : "") + ".", e);
                Day.refresh();
                return;
            }
            const parsed = DayText.importLines(r.lines, Date.now(), {sites: Day.sites.map(site => site.name)});
            let waiting = parsed.orders.length;
            const finish = () => {
                orderDone("Added " + parsed.orders.length + " order" + (parsed.orders.length === 1 ? "" : "s") + (parsed.skipped.length ? ", skipped " + parsed.skipped.length + ": " + parsed.skipped[0].line + " (" + parsed.skipped[0].reason + ")" : "") + ".", null);
                Day.refresh();
            };
            if (!waiting)
                finish();
            parsed.orders.forEach(fields => Day.addOrder(fields, () => { if (--waiting === 0) finish(); }));
        });
    }
    function backupDay() {
        busy = true;
        orderResult = "";
        Backend.request("day.backup", {path: orderPath(".sqlite3")}, (r, e) => orderDone(e ? "" : "Copied all Day data to " + r.path, e));
    }
    function restoreDay() {
        busy = true;
        orderResult = "";
        Backend.request("day.restore", {path: orderPath(".sqlite3")}, (r, e) => {
            orderDone(e ? "" : "Restored " + r.count + " order" + (r.count === 1 ? "" : "s") + " from " + r.path + ". What was here is kept as day.sqlite3.before-restore.", e);
            Day.refresh();
            Day.loadLogbook();
        });
    }
    C.Label {
        text: "Orders"
        font.weight: Font.DemiBold
        Layout.topMargin: Theme.gapL
        Layout.fillWidth: true
    }
    C.Label {
        text: "Export your orders, bring orders in from a Shale export, a Todoist CSV export or a plain list, or copy the whole Day database (orders, routines, shifts)."
        color: Theme.muted
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    C.Field {
        id: orderPathField
        Layout.fillWidth: true
        Accessible.name: "Orders file"
        text: "~/shale-orders.json"
        onTextEdited: root.orderResult = ""
    }
    C.ChoiceRow {
        label: "Export as"
        model: [{key: "json", text: "JSON", hint: "Everything; can be imported again"}, {key: "csv", text: "CSV", hint: "One row per order"}, {key: "md", text: "Markdown", hint: "One list per site"}]
        current: root.orderFormat
        onActivated: key => root.orderFormat = key
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.gapS
        C.Button {
            text: "Export orders"
            glyph: "copy"
            accent: true
            enabled: !root.busy && Backend.ready
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            onClicked: root.exportOrders()
        }
        C.Button {
            text: "Import orders"
            glyph: "folder"
            enabled: !root.busy && Backend.ready
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            onClicked: root.importOrders()
        }
        C.Button {
            text: "Back up all"
            glyph: "folder"
            enabled: !root.busy && Backend.ready
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            onClicked: root.backupDay()
        }
        C.Button {
            text: "Restore"
            glyph: "folder"
            enabled: !root.busy && Backend.ready
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            onClicked: root.restoreDay()
        }
    }
    C.Label {
        visible: root.orderResult !== ""
        text: root.orderResult
        color: root.orderFailed ? Theme.danger : Theme.success
        font.pixelSize: Theme.small
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    C.Caption {
        text: "Import reads .json (a Shale export), .csv (a Todoist project export; its file name becomes the site) or any other text file with one order per line in the capture grammar. Back up all writes a .sqlite3 copy and Restore reads one back (what was here is kept first)."
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
}
