pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"
import "../core/airdrop.js" as Words

// AirDrop with iPhones, iPads and Macs through the optional `airdrop` command (AirDrop for Linux), driven over its
// --json interface: it reports what happens as JSON lines and takes picks and answers on stdin. One process sends
// (`airdrop send`), one receives (`receive` while Visible, `listen` in Background); the radio takes one session at a
// time, so receiving pauses while a send runs and comes back after it. Everything here is hidden while the command
// is missing or too old to speak --json.
Singleton {
    id: root

    // ---- the command ----------------------------------------------------------------------------------------------
    readonly property string command: Backend.capabilities.airdrop || ""
    // The installed command answers `--json config show`.
    property bool supported: false
    readonly property bool available: command !== "" && supported
    // {name, dir, known, mode, channel, iface}: the command's own settings (its device name and known senders).
    property var config: ({})
    readonly property string deviceName: config.name || ""
    readonly property var knownSenders: config.known || []
    // `airdrop doctor`: {ok, checks: [{label, detail, level: ok | error | info}]}, after checkComputer().
    property var doctor: null
    property bool checking: false
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string folder: ShellState.setting("airdropFolder", "~/Downloads/AirDrop")
    readonly property string folderPath: folder.startsWith("~/") ? home + folder.slice(1) : folder
    // A hidden way to try the panel without a radio: SHALE_AIRDROP_PEER=[::1]:PORT sends to that receiver, and
    // SHALE_AIRDROP_BIND=::1 receives there (the command's own loopback test mode).
    readonly property string devPeer: Quickshell.env("SHALE_AIRDROP_PEER") || ""
    readonly property string devBind: Quickshell.env("SHALE_AIRDROP_BIND") || ""
    onCommandChanged: probe()

    // ---- receiving ------------------------------------------------------------------------------------------------
    // off | visible (for ten minutes, `receive`) | background (`listen`: Wi-Fi stays up until an iPhone opens AirDrop)
    property string mode: "off"
    readonly property int visibleMinutes: 10
    property real visibleUntil: 0
    property int visibleLeft: 0
    // While receiving: starting | ready (visible) | listening (background, idle) | waking (an iPhone opened AirDrop)
    property string receiverState: ""
    property bool receiverWifi: false
    property bool senderWifi: false
    readonly property bool wifiPaused: receiverWifi || senderWifi
    // Requests from other devices, newest last; a card per row. Arrays are JSON text (a ListModel can't hold them).
    // key: "<generation>:<id>", the id being the command's own (it starts again at 1 in each receiver process).
    property ListModel incoming: ListModel {}
    property int generation: 0
    // Questions waiting for an answer.
    property int countPending: 0
    // The request whose files are arriving now: {key, sender, done, total} or null.
    property var incomingNow: null
    // Sent and received this session, newest first: {dir: in | out, who, title, bytes, paths, url, phase, time}.
    property var recent: []

    // ---- sending --------------------------------------------------------------------------------------------------
    // "" | starting (the radio comes up) | searching | ended (nothing picked for a while; search again)
    property string sendState: ""
    // Devices nearby: peerId, name, model, kind, available, lost, phase ("" | asking | sending | done | declined |
    // failed | cancelled), transferId, done, total, message.
    property ListModel peers: ListModel {}
    // What is chosen to send: [{path, name, size, dir, kind}], or one link.
    property var staged: []
    property string stagedUrl: ""
    readonly property bool hasStaged: staged.length > 0 || stagedUrl !== ""
    readonly property real stagedBytes: staged.reduce((sum, item) => sum + (item.size || 0), 0)
    // The send that is running, for the bar: {peerId, name, phase, done, total} or null.
    property var sending: null
    property string searchHint: ""

    // ---- what went wrong ------------------------------------------------------------------------------------------
    // {code, message, hint, from}; code is the command's (auth, helper, busy, link, bluetooth, config, start) or exit
    // (it stopped by itself) or wifi (a session ended with Wi-Fi still paused); from is rx (receiving), tx (sending)
    // or "", for Try again.
    property var error: null
    readonly property var hints: ({
        auth: "Shale wasn't given permission to use the Wi-Fi card. To stop being asked, install the polkit rule from the airdrop source folder: packaging/50-airdrop-background.rules.example.",
        helper: "The airdrop helper is missing or older than the airdrop command. Settings → AirDrop → Check this computer says how to install it.",
        busy: "Another AirDrop session is running, perhaps in a terminal. Stop it and try again.",
        bluetooth: "Bluetooth is off or missing. Background needs it to hear an iPhone open AirDrop.",
        link: "The Wi-Fi card couldn't start AirDrop. Settings → AirDrop → Check this computer may say why.",
        config: "The airdrop command's settings file (~/.config/airdrop/config.toml) can't be read. Fix or remove it, then check again.",
        start: "AirDrop couldn't start. Check this computer may say why.",
        wifi: "Give Wi-Fi back reconnects the network AirDrop paused (airdrop recover).",
        exit: ""
    })
    function fail(code, message, from) {
        const text = String(message || "AirDrop stopped");
        error = {code: code, message: text.charAt(0).toUpperCase() + text.slice(1), hint: hints[code] || "", from: from || ""};
    }
    // Try again what failed: the way of receiving that stopped, or the search.
    property string failedMode: ""
    function retry() {
        const from = error ? error.from : "";
        error = null;
        if (from === "rx" && failedMode)
            setMode(failedMode, false);
        else if (from === "tx")
            search();
    }
    readonly property bool canRetry: !!error && (error.from === "rx" && failedMode !== "" || error.from === "tx")
                                     && ["config", "helper", "wifi"].indexOf(error.code) < 0

    // ---- what the bar and the panel read ---------------------------------------------------------------------------
    readonly property bool receiving: receiver.running
    readonly property bool looking: sender.running
    // 0–1 of whatever moves now, or -1.
    readonly property real progress: {
        if (sending && sending.phase === "sending" && sending.total > 0)
            return Math.min(1, sending.done / sending.total);
        return incomingNow && incomingNow.total > 0 ? Math.min(1, incomingNow.done / incomingNow.total) : -1;
    }
    readonly property bool active: mode !== "off" || looking || progress >= 0 || countPending > 0

    // ---- receiving: modes -----------------------------------------------------------------------------------------
    // Off and Background are kept as the start-up choice; Visible lasts ten minutes and is never restored.
    function setMode(next, keep) {
        if (!available || ["off", "visible", "background"].indexOf(next) < 0)
            return;
        if (next !== "visible" && keep !== false)
            ShellState.setSetting("airdropMode", next);
        if (next === "visible")
            visibleUntil = Date.now() + visibleMinutes * 60000;
        error = null;
        mode = next;
        if (sender.running) {
            resumeMode = next; // after the send
            return;
        }
        restartReceiver();
    }
    function toggleVisible() {
        setMode(mode === "visible" ? (ShellState.setting("airdropMode", "off") === "background" ? "background" : "off") : "visible");
    }
    function extend() {
        if (mode === "visible")
            visibleUntil = Math.max(visibleUntil, Date.now()) + visibleMinutes * 60000;
    }
    property string resumeMode: ""
    property string startMode: ""
    // Asking, the time to answer and the folder are given when the receiver starts; a change starts it again.
    readonly property string receiverSettings: [ShellState.setting("airdropAsk", "ask"), ShellState.setting("airdropTimeout", 60), folderPath].join("|")
    onReceiverSettingsChanged: if (receiver.running && !receiver.stopping && countPending === 0 && !incomingNow)
        restartReceiver()
    function restartReceiver() {
        if (receiver.running) {
            stopProcess(receiver);
            return; // onExited starts the mode that is chosen then
        }
        startReceiver();
    }
    function receiverCommand(kind) {
        const args = [command, "--json", kind];
        if (kind === "receive" && devBind)
            args.push("--no-link", "--bind", devBind, "--port", Quickshell.env("SHALE_AIRDROP_PORT") || "0");
        if (ShellState.setting("airdropAsk", "ask") === "ask")
            args.push("--ask", "--ask-timeout", String(ShellState.setting("airdropTimeout", 60)));
        args.push("--download-dir", folderPath);
        return args;
    }
    function startReceiver() {
        if (mode === "off" || receiver.running || sender.running || recovering)
            return;
        generation++;
        startMode = mode;
        receiverState = "starting";
        receiver.begin(receiverCommand(mode === "visible" ? "receive" : "listen"));
    }
    property Timer visibleClock: Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.mode === "visible"
        onTriggered: {
            root.visibleLeft = Math.max(0, Math.round((root.visibleUntil - Date.now()) / 1000));
            // Not in the middle of a question or a transfer: it ends right after.
            if (root.visibleLeft === 0 && root.countPending === 0 && !root.incomingNow)
                root.setMode(ShellState.setting("airdropMode", "off") === "background" ? "background" : "off", false);
        }
    }

    // ---- receiving: answers ---------------------------------------------------------------------------------------
    function answer(key, decision) {
        const i = indexOf(incoming, "key", key);
        if (i < 0)
            return;
        const row = incoming.get(i);
        if (row.phase !== "asking")
            return;
        // The lock screen never says Always: a sender named there is not someone the owner looked at.
        const choice = decision === "always" && ShellState.locked ? "accept" : decision;
        // The process that asked is gone: nobody can take the answer, so the card mustn't wait for files.
        if (!receiver.running || receiver.stopping || row.generation !== generation) {
            incoming.setProperty(i, "phase", "cancelled");
            incoming.setProperty(i, "message", "AirDrop stopped receiving before the answer");
            incoming.setProperty(i, "finished", Date.now());
            countAsking();
            return;
        }
        receiver.write(JSON.stringify({answer: choice, id: row.rid}) + "\n");
        incoming.setProperty(i, "phase", choice === "decline" ? "declined" : "accepted");
        incoming.setProperty(i, "decision", choice);
        countAsking();
    }
    // The oldest open question (`shale airdrop accept|decline`, bindable keys).
    function answerOldest(decision) {
        for (let i = 0; i < incoming.count; i++)
            if (incoming.get(i).phase === "asking")
                return answer(incoming.get(i).key, decision);
    }
    function dismiss(key) {
        const i = indexOf(incoming, "key", key);
        if (i < 0)
            return;
        if (incoming.get(i).phase === "asking")
            answer(key, "decline");
        incoming.remove(i);
        countAsking();
    }
    function countAsking() {
        let n = 0;
        for (let i = 0; i < incoming.count; i++)
            if (incoming.get(i).phase === "asking")
                n++;
        countPending = n;
    }
    // Only web links open, and only from a request someone accepted.
    function openLink(url) {
        if (/^https?:\/\//i.test(url) && !ShellState.locked)
            ShellState.openUrl(url);
    }
    // Undo a session that ended badly (Wi-Fi still paused): the command's own recovery, with a password if asked. A
    // receiver that runs is stopped first and comes back after; a send has to finish.
    property bool recovering: false
    function recover() {
        if (sender.running || recovering || !command)
            return;
        recovering = true;
        error = null;
        if (receiver.running)
            stopProcess(receiver); // its end goes on with runRecover()
        else
            runRecover();
    }
    function runRecover() {
        run(["recover"], null, code => {
            root.recovering = false;
            if (code === 0)
                ShellState.message("Wi-Fi is back", "success");
            else
                root.fail("wifi", "Couldn't give Wi-Fi back. Run airdrop recover in a terminal to see why.");
            root.startReceiver();
        });
    }
    function forget(sender) {
        run(["config", "known", "rm", sender], null, () => refreshConfig());
    }
    function rename(name) {
        const clean = String(name || "").trim();
        if (clean && clean !== deviceName)
            run(["config", "set", "name", clean], null, code => {
                if (code !== 0)
                    ShellState.message("Couldn't rename this computer for AirDrop", "error");
                refreshConfig();
                // The receiver reads the name when it starts: an idle one starts again to show the new one.
                if (code === 0 && receiver.running && !receiver.stopping && countPending === 0 && !incomingNow)
                    restartReceiver();
            });
    }

    // ---- sending --------------------------------------------------------------------------------------------------
    // Staging asks the helper which paths exist and how big they are, so the card can show sizes.
    function stage(paths) {
        const wanted = (paths || []).map(path => String(path).replace(/^file:\/\//, "")).map(path => {
            try {
                return decodeURIComponent(path);
            } catch (e) {
                return path;
            }
        }).filter(path => path.startsWith("/") && !staged.some(item => item.path === path));
        if (!wanted.length)
            return;
        stagedUrl = "";
        Backend.request("airdrop.stat", {paths: wanted.slice(0, 200)}, (result, error) => {
            if (error)
                return;
            const added = result.items.filter(item => !root.staged.some(old => old.path === item.path));
            root.staged = root.staged.concat(added);
            if (added.length < wanted.length)
                ShellState.message(wanted.length - added.length === 1 ? "One item can't be found" : (wanted.length - added.length) + " items can't be found", "error");
        });
    }
    function stageUrl(url) {
        const text = String(url || "").trim();
        if (!/^[a-z][a-z0-9+.-]*:\S+$/i.test(text))
            return false;
        staged = [];
        stagedUrl = text;
        return true;
    }
    function unstage(index) {
        if (index < 0)
            stagedUrl = "";
        else
            staged = staged.filter((item, i) => i !== index);
    }
    function clearStaged() {
        staged = [];
        stagedUrl = "";
    }
    // Look for devices: the radio comes up (in borrow mode Wi-Fi pauses for the search), so only when asked.
    function search() {
        if (!available || sender.running || recovering)
            return;
        error = null;
        searchHint = "";
        if (receiver.running) {
            resumeMode = mode;
            pendingSearch = true;
            stopProcess(receiver);
            return;
        }
        startSender();
    }
    property bool pendingSearch: false
    function startSender() {
        pendingSearch = false;
        for (let i = peers.count - 1; i >= 0; i--)
            if (peers.get(i).lost || ["", "done", "declined", "failed", "cancelled"].indexOf(peers.get(i).phase) >= 0)
                peers.remove(i);
        sendState = "starting";
        lastFound = 0;
        const args = [command, "--json", "send", "-t", "90"];
        if (devPeer)
            args.push("--peer", devPeer);
        sender.begin(args);
    }
    // Devices the last search found; the list itself empties when the search ends.
    property int lastFound: 0
    // The panel opens again: what an earlier search left (its outcomes) goes.
    function clearPeers() {
        if (sender.running)
            return;
        peers.clear();
        if (sendState === "ended")
            sendState = "";
        searchHint = "";
    }
    // The panel closed: stop looking unless something is on its way.
    function endSearch() {
        if (sender.running && !(sending && ["asking", "sending"].indexOf(sending.phase) >= 0))
            stopProcess(sender);
    }
    function sendTo(peerId) {
        const i = indexOf(peers, "peerId", peerId);
        if (i < 0 || !hasStaged || !sender.running || sending && ["asking", "sending"].indexOf(sending.phase) >= 0)
            return;
        const row = peers.get(i);
        if (!row.available || row.lost)
            return;
        const pick = stagedUrl ? {pick: peerId, url: stagedUrl} : {pick: peerId, paths: staged.map(item => item.path)};
        sender.write(JSON.stringify(pick) + "\n");
        // Shown at once; the command confirms with its transfer id.
        peers.setProperty(i, "phase", "asking");
        peers.setProperty(i, "transferId", -1);
        peers.setProperty(i, "done", 0);
        peers.setProperty(i, "total", stagedBytes);
        peers.setProperty(i, "message", "");
        sending = {peerId: peerId, name: row.name, phase: "asking", done: 0, total: stagedBytes, rate: 0, title: stagedTitle()};
    }
    function cancel(peerId) {
        const i = indexOf(peers, "peerId", peerId);
        if (i >= 0 && peers.get(i).transferId > 0 && sender.running)
            sender.write(JSON.stringify({cancel: peers.get(i).transferId}) + "\n");
    }
    function stagedTitle() {
        if (stagedUrl)
            return stagedUrl.replace(/^https?:\/\//, "");
        if (staged.length === 1)
            return staged[0].name;
        return staged.length + " items";
    }

    // ---- events ---------------------------------------------------------------------------------------------------
    function handle(from, line) {
        let ev;
        try {
            ev = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (ev.event === "error") {
            // A pick the command couldn't take: the device row says so.
            if (from === "tx" && (ev.code === "input" || ev.code === "busy")) {
                if (sending) {
                    const text = String(ev.message || "");
                    setPeer(sending.peerId, {phase: "failed", message: text.charAt(0).toUpperCase() + text.slice(1)});
                    sending = null;
                }
                return;
            }
            // A line the receiver couldn't read is Shale's mistake, not something to show.
            if (ev.code === "input") {
                console.warn("AirDrop: " + ev.message);
                return;
            }
            fail(ev.code, ev.message, from);
        } else if (ev.event === "session") {
            const wasPaused = from === "rx" ? receiverWifi : senderWifi;
            const paused = ev.phase === "up" && !!ev.wifi_paused;
            if (from === "rx")
                receiverWifi = paused;
            else
                senderWifi = paused;
            if (ev.phase === "down" && wasPaused && ev.wifi_restored === false)
                fail("wifi", "Wi-Fi didn't reconnect after AirDrop", from);
            if (ev.phase === "starting" && from === "rx" && startMode === "background")
                receiverState = "waking";
        } else if (ev.event === "visible" && from === "rx") {
            receiverState = "ready";
            // Receiving works now: an earlier failure to start it is over (a Wi-Fi warning stays until dismissed).
            if (error && error.from === "rx" && error.code !== "wifi")
                error = null;
        } else if (ev.event === "listen") {
            // An iPhone that woke it and couldn't be served leaves its error up: idle follows the error at once.
            receiverState = ev.state === "triggered" ? "waking" : "listening";
        } else if (ev.event === "searching") {
            sendState = "searching";
            if (error && error.from === "tx" && error.code !== "wifi")
                error = null;
        } else if (ev.event === "search_end") {
            sendState = "ended";
            lastFound = ev.found || 0;
            searchHint = ev.found ? "" : String(ev.hint || "").trim();
        } else if (ev.event === "peer") {
            const fields = {name: ev.name || ev.model || "Unknown device", model: ev.model || "", kind: ev.kind || "other",
                            available: !!ev.available, lost: false};
            if (indexOf(peers, "peerId", ev.id) < 0)
                peers.append(Object.assign({peerId: ev.id, phase: "", transferId: 0, done: 0, total: 0, message: ""}, fields));
            else
                setPeer(ev.id, fields);
        } else if (ev.event === "peer_lost") {
            setPeer(ev.id, {lost: true});
        } else if (ev.event === "ask") {
            incoming.append({
                key: generation + ":" + ev.id, rid: ev.id, generation: generation,
                sender: ev.sender || "", model: ev.model || "", kind: ev.kind || "other",
                known: !!ev.known, asking: !!ev.asking, timeout: ev.timeout || 0,
                deadline: Date.now() + (ev.timeout || 0) * 1000, created: Date.now(),
                filesJson: JSON.stringify(ev.files || []), urlsJson: JSON.stringify(ev.urls || []),
                total: ev.total || 0, icon: ev.icon ? "file://" + ev.icon : "",
                phase: ev.asking ? "asking" : "accepted", decision: ev.asking ? "" : "accept",
                done: 0, rate: 0, savedJson: "[]", message: "", finished: 0
            });
            countAsking();
        } else if (ev.event === "answered") {
            updateIncoming(ev.id, row => row.phase === "asking" || row.phase === "accepted" ? {
                phase: ev.decision === "decline" ? (ev.by === "timeout" ? "missed" : "declined") : "accepted",
                decision: ev.decision, finished: ev.decision === "decline" ? Date.now() : 0
            } : {});
            countAsking();
        } else if (ev.event === "link") {
            updateIncoming(ev.id, row => ({phase: "link", savedJson: JSON.stringify([ev.url]), finished: Date.now()}));
            remember({dir: "in", who: ev.sender || "", title: ev.url, url: ev.url, phase: "done"});
        } else if (ev.event === "progress") {
            if (from === "rx") {
                updateIncoming(ev.id, row => ({done: ev.done, total: ev.total || row.total, rate: ev.rate || 0}));
                if (incomingNow && incomingNow.key === generation + ":" + ev.id)
                    incomingNow = Object.assign({}, incomingNow, {done: ev.done, total: ev.total || incomingNow.total, rate: ev.rate || 0});
            } else {
                setTransfer(ev.id, {done: ev.done, total: ev.total || 0});
                if (sending)
                    sending = Object.assign({}, sending, {rate: ev.rate || 0});
            }
        } else if (ev.event === "transfer") {
            if (ev.dir === "in")
                incomingTransfer(ev);
            else
                outgoingTransfer(ev);
        }
    }
    function incomingTransfer(ev) {
        const i = indexOf(incoming, "key", generation + ":" + ev.id);
        const row = i >= 0 ? incoming.get(i) : null;
        if (ev.phase === "receiving") {
            updateIncoming(ev.id, row => ({phase: "receiving", total: ev.total || row.total}));
            incomingNow = {key: generation + ":" + ev.id, sender: ev.sender || (row ? row.sender : ""), done: 0, total: ev.total || (row ? row.total : 0), rate: 0};
            return;
        }
        if (incomingNow && incomingNow.key === generation + ":" + ev.id)
            incomingNow = null;
        const what = row ? Words.summary(JSON.parse(row.filesJson), JSON.parse(row.urlsJson)) : "";
        const who = ev.sender || (row ? row.sender : "");
        if (ev.phase === "done") {
            const saved = ev.saved || [];
            updateIncoming(ev.id, () => ({phase: "done", savedJson: JSON.stringify(saved), done: ev.bytes || 0, finished: Date.now()}));
            remember({dir: "in", who: who, paths: saved, bytes: ev.bytes || 0, phase: "done",
                      title: saved.length === 1 ? ShellState.fileName(saved[0]) : Words.capital(what || saved.length + " items")});
        } else if (ev.phase === "failed" || ev.phase === "cancelled") {
            // Only files that started to arrive belong in Recent; a request the sender dropped before that doesn't.
            const started = row && (row.phase === "receiving" || row.done > 0);
            updateIncoming(ev.id, () => ({phase: ev.phase, message: ev.message || "", finished: Date.now()}));
            countAsking();
            if (started || ev.phase === "failed")
                remember({dir: "in", who: who, title: Words.capital(what || "a transfer"), phase: ev.phase, message: ev.message || ""});
        }
    }
    function outgoingTransfer(ev) {
        const i = indexOf(peers, "peerId", ev.peer);
        const name = i >= 0 ? peers.get(i).name : "";
        if (ev.phase === "asking" || ev.phase === "sending") {
            setPeer(ev.peer, {phase: ev.phase, transferId: ev.id, total: ev.total || 0});
            sending = {peerId: ev.peer, name: name, phase: ev.phase, done: 0, total: ev.total || 0, rate: 0, title: sending ? sending.title : stagedTitle()};
            return;
        }
        setPeer(ev.peer, {phase: ev.phase, message: ev.message || "", done: ev.phase === "done" && i >= 0 ? peers.get(i).total : 0});
        remember({dir: "out", who: name, title: sending ? sending.title : stagedTitle(), phase: ev.phase,
                  bytes: i >= 0 ? peers.get(i).total : 0, message: ev.message || ""});
        sending = null;
        if (!ShellState.panel || ShellState.panel !== "airdrop") {
            if (ev.phase === "done")
                ShellState.message("Sent to " + name, "success");
            else if (ev.phase === "declined")
                ShellState.message(name + " declined", "error");
            else if (ev.phase === "failed")
                ShellState.message("Couldn't send to " + name + (ev.message ? ": " + ev.message : ""), "error");
        }
    }
    function setPeer(peerId, fields) {
        const i = indexOf(peers, "peerId", peerId);
        if (i < 0)
            return;
        for (const key in fields)
            peers.setProperty(i, key, fields[key]);
    }
    function setTransfer(transferId, fields) {
        for (let i = 0; i < peers.count; i++)
            if (peers.get(i).transferId === transferId) {
                for (const key in fields)
                    peers.setProperty(i, key, fields[key]);
                if (sending && sending.peerId === peers.get(i).peerId)
                    sending = Object.assign({}, sending, fields);
            }
    }
    function updateIncoming(id, change) {
        const i = indexOf(incoming, "key", generation + ":" + id);
        if (i < 0)
            return;
        const fields = change(incoming.get(i));
        for (const key in fields)
            incoming.setProperty(i, key, fields[key]);
    }
    function remember(entry) {
        recent = [Object.assign({time: Date.now(), paths: [], bytes: 0, url: "", message: ""}, entry)].concat(recent).slice(0, 30);
    }
    function indexOf(model, field, value) {
        for (let i = 0; i < model.count; i++)
            if (model.get(i)[field] === value)
                return i;
        return -1;
    }

    // ---- processes ------------------------------------------------------------------------------------------------
    // `done` ends a session cleanly (the command gives Wi-Fi back first). One that doesn't end gets a terminate
    // signal, then a kill: its root helper undoes the radio by itself once the command is gone.
    function stopProcess(proc) {
        if (!proc.running)
            return;
        proc.write(JSON.stringify({done: true}) + "\n");
        proc.stopping = true;
        proc.escalate.restart();
    }
    // Requests still open when a receiver ends: nobody can answer them or finish them any more.
    function closeOpenRequests(gen, message) {
        for (let i = 0; i < incoming.count; i++) {
            const row = incoming.get(i);
            if (row.generation === gen && ["asking", "accepted", "receiving"].indexOf(row.phase) >= 0) {
                incoming.setProperty(i, "phase", "cancelled");
                incoming.setProperty(i, "message", message);
                incoming.setProperty(i, "finished", Date.now());
            }
        }
        countAsking();
    }
    component Session: Process {
        id: session
        property bool stopping: false
        // The command ran (`started`): a session that ends without having started couldn't be run at all.
        property bool began: false
        // The terminate signal went; the next step is a kill.
        property bool forced: false
        // The command's last line on stderr, said when it stops without an error event.
        property string lastLine: ""
        // Quickshell reports a command that can't be run (missing, not executable) only by `running` going false.
        signal failedToStart()
        function begin(args) {
            began = false;
            stopping = false;
            forced = false;
            lastLine = "";
            command = args;
            running = true;
        }
        onStarted: began = true
        onRunningChanged: if (!running && !began)
            failedToStart()
        property Timer escalate: Timer {
            interval: 20000
            onTriggered: {
                if (!session.running)
                    return;
                session.signal(session.forced ? 9 : 15);
                if (!session.forced) {
                    session.forced = true;
                    session.escalate.restart();
                }
            }
        }
        stdinEnabled: true
        stderr: SplitParser {
            onRead: data => {
                if (data.trim())
                    session.lastLine = data.trim();
            }
        }
    }
    property Session receiver: Session {
        stdout: SplitParser {
            onRead: data => root.handle("rx", data)
        }
        onExited: code => root.receiverEnded(code)
        onFailedToStart: root.receiverEnded(-1)
    }
    function receiverEnded(code) {
        const asked = receiver.stopping;
        receiver.stopping = false;
        receiver.escalate.stop();
        // Gone without saying Wi-Fi came back (killed, crashed): it may still be paused.
        if (receiverWifi)
            fail("wifi", "AirDrop stopped while Wi-Fi was paused", "rx");
        receiverWifi = false;
        receiverState = "";
        incomingNow = null;
        closeOpenRequests(generation, "AirDrop stopped receiving");
        if (!asked && mode !== "off" && startMode === mode) {
            if (code < 0)
                fail("start", "Couldn't run " + command, "rx");
            else if (!error)
                fail("exit", receiver.lastLine || "AirDrop stopped (code " + code + ")", "rx");
            failedMode = mode;
            mode = "off";
        }
        if (recovering)
            runRecover(); // starts the receiver again once Wi-Fi is back
        else if (pendingSearch)
            startSender();
        else
            startReceiver();
    }
    property Session sender: Session {
        stdout: SplitParser {
            onRead: data => root.handle("tx", data)
        }
        onExited: code => root.senderEnded(code)
        onFailedToStart: root.senderEnded(-1)
    }
    function senderEnded(code) {
        const asked = sender.stopping;
        sender.stopping = false;
        sender.escalate.stop();
        if (senderWifi)
            fail("wifi", "AirDrop stopped while Wi-Fi was paused", "tx");
        senderWifi = false;
        if (sending) {
            setPeer(sending.peerId, {phase: "cancelled"});
            sending = null;
        }
        // Devices of a search that ended can't be sent to any more; the ones with an outcome stay to show it.
        for (let i = peers.count - 1; i >= 0; i--)
            if (peers.get(i).phase === "")
                peers.remove(i);
        if (sendState !== "ended")
            sendState = asked || code === 0 ? "" : "ended";
        if (code < 0)
            fail("start", "Couldn't run " + command, "tx");
        else if (!asked && code !== 0 && code !== 4 && !error)
            fail("exit", sender.lastLine || "AirDrop stopped (code " + code + ")", "tx");
        if (resumeMode) {
            mode = resumeMode;
            resumeMode = "";
        }
        startReceiver();
    }
    // A request the command forgot without a word: it drops an accepted one after three minutes with no files, and a
    // question is declined at its timeout. A card still open well past either closes here.
    property Timer sweep: Timer {
        interval: 5000
        repeat: true
        running: root.incoming.count > 0
        onTriggered: {
            const now = Date.now();
            for (let i = 0; i < root.incoming.count; i++) {
                const row = root.incoming.get(i);
                const stale = row.phase === "accepted" && now - row.created > 190000
                              || row.phase === "asking" && row.timeout > 0 && now > row.deadline + 15000;
                if (!stale)
                    continue;
                root.incoming.setProperty(i, "message", row.phase === "asking" ? "" : (row.sender || "The sender") + " didn't send anything");
                root.incoming.setProperty(i, "phase", row.phase === "asking" ? "missed" : "cancelled");
                root.incoming.setProperty(i, "finished", now);
            }
            root.countAsking();
        }
    }

    // One-off commands (config, doctor, recover), one at a time. One that hangs is stopped after two minutes, so the
    // ones after it still run.
    property var queue: []
    property var current: null
    function run(args, onEvent, onDone) {
        if (!command)
            return;
        queue = queue.concat([{args: args, onEvent: onEvent, onDone: onDone}]);
        next();
    }
    function next() {
        if (current || !queue.length)
            return;
        current = queue[0];
        queue = queue.slice(1);
        tool.began = false;
        tool.command = [command].concat(current.args);
        tool.running = true;
        toolLimit.restart();
    }
    function toolEnded(code) {
        toolLimit.stop();
        const done = current;
        current = null;
        if (done && done.onDone)
            done.onDone(code);
        next();
    }
    property Timer toolLimit: Timer {
        interval: 120000
        onTriggered: if (root.tool.running)
            root.tool.signal(15)
    }
    property Process tool: Process {
        property bool began: false
        onStarted: began = true
        onRunningChanged: if (!running && !began && root.current)
            root.toolEnded(-1)
        stdout: SplitParser {
            onRead: data => {
                try {
                    const ev = JSON.parse(data);
                    if (root.current && root.current.onEvent)
                        root.current.onEvent(ev);
                } catch (e) {}
            }
        }
        onExited: code => root.toolEnded(code)
    }
    function probe() {
        supported = false;
        if (!command)
            return;
        refreshConfig();
    }
    // A command that answers with JSON speaks --json, even when what it says is that its settings file is broken.
    function refreshConfig() {
        run(["--json", "config", "show"], ev => {
            if (ev.event === "config") {
                root.config = ev;
                root.supported = true;
                if (root.error && root.error.code === "config")
                    root.error = null;
            } else if (ev.event === "error") {
                root.supported = true;
                root.fail(ev.code, ev.message);
            }
        }, () => root.startup());
    }
    function checkComputer() {
        checking = true;
        run(["--json", "doctor"], ev => {
            if (ev.event === "doctor")
                root.doctor = ev;
        }, () => root.checking = false);
    }
    // Background comes back with the shell (it never takes Wi-Fi until an iPhone opens AirDrop).
    property bool started: false
    function startup() {
        if (started || !available || !ShellState.settings.version)
            return;
        started = true;
        if (ShellState.setting("airdropMode", "off") === "background")
            setMode("background", false);
    }
    property Connections settingsLoaded: Connections {
        target: ShellState
        function onSettingsChanged() {
            root.startup();
        }
    }
    Component.onCompleted: probe()

    property IpcHandler ipc: IpcHandler {
        target: "airdrop"
        function status(): string {
            return JSON.stringify({available: root.available, command: root.command, supported: root.supported, mode: root.mode, visibleLeft: root.visibleLeft,
                                   receiving: root.receiverState, searching: root.sendState, peers: root.peers.count, pending: root.countPending,
                                   sending: root.sending ? root.sending.phase : "", wifiPaused: root.wifiPaused, recovering: root.recovering,
                                   error: root.error ? root.error.message : ""});
        }
        function mode(name: string): void {
            if (name === "toggle")
                root.toggleVisible();
            else
                root.setMode(name);
        }
        // Paths one per line: they are staged and the panel opens, ready to pick a device.
        function send(paths: string): void {
            if (!root.available) {
                ShellState.message(root.command ? "This airdrop command is too old for Shale" : "AirDrop needs the airdrop command", "error");
                return;
            }
            root.stage(paths.split("\n").filter(path => path));
            ShellState.open("airdrop");
        }
        function accept(): void {
            root.answerOldest("accept");
        }
        function decline(): void {
            root.answerOldest("decline");
        }
    }
}
