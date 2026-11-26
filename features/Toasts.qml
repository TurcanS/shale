import QtQuick
import Quickshell
import "../core"
import "../services"

Scope {
    id: root
    required property var screen
    readonly property bool target: ShellState.targetScreen() === screen.name
    // Microphone mute and keyboard layout changes show as OSD cards. Every screen has a copy of this scope; only the
    // target screen's reports, and a microphone that just appeared settles first so start-up stays quiet.
    property bool micSettled: false
    Timer {
        id: micSettle
        interval: 2000
        running: true
        onTriggered: root.micSettled = true
    }
    Connections {
        target: Services
        function onInputChanged() {
            root.micSettled = false;
            micSettle.restart();
        }
        function onMicMutedChanged() {
            if (root.micSettled && root.target)
                ShellState.osd((Services.micMuted ? "Muted" : "On") + " · Microphone", -1, Services.micMuted ? "mic-off" : "mic", Services.micMuted);
        }
    }
    readonly property var languages: ({us: "English", gb: "English", au: "English", ca: "Canadian", ie: "Irish", de: "German", at: "German", ch: "Swiss",
        fr: "French", be: "Belgian", es: "Spanish", latam: "Spanish", pt: "Portuguese", br: "Portuguese", it: "Italian", nl: "Dutch",
        se: "Swedish", no: "Norwegian", dk: "Danish", fi: "Finnish", is: "Icelandic", pl: "Polish", cz: "Czech", sk: "Slovak",
        hu: "Hungarian", ro: "Romanian", bg: "Bulgarian", hr: "Croatian", si: "Slovenian", rs: "Serbian", gr: "Greek", tr: "Turkish",
        ru: "Russian", ua: "Ukrainian", by: "Belarusian", lt: "Lithuanian", lv: "Latvian", ee: "Estonian", il: "Hebrew", ara: "Arabic",
        ir: "Persian", in: "Indian", jp: "Japanese", kr: "Korean", cn: "Chinese", th: "Thai", vn: "Vietnamese"})
    // The last layout seen: keyboard, its layouts and the active one. Only a switch among the same layouts shows.
    property string layoutSeen: ""
    Connections {
        target: ShellState
        function onKeyboardChanged() {
            const keyboard = ShellState.keyboard || {};
            const layouts = keyboard.layouts || [];
            const set = (keyboard.name || "") + "|" + JSON.stringify(layouts);
            const previous = root.layoutSeen;
            root.layoutSeen = set + "|" + keyboard.index;
            const current = layouts[keyboard.index];
            if (!root.target || !current || layouts.length < 2 || previous === root.layoutSeen || previous.slice(0, previous.lastIndexOf("|")) !== set)
                return;
            const code = String(current.code || "");
            ShellState.osd((root.languages[code] || code.toUpperCase()) + " · Keyboard · " + [code.toUpperCase(), current.variant || ""].filter(part => part).join(" "), -1, "keyboard");
        }
    }
    // Notification toasts: the Notifications card, stacked up from the bottom right corner, newest lowest.
    ToastPopups {
        screen: root.screen
        target: root.target
    }
    // Levels (volume, brightness) as a round pill with a slim bar and the value; everything else (microphone,
    // keyboard layout, Do not disturb, countdowns) as a small card with a title and what it is about.
    ToastOsd {
        screen: root.screen
        target: root.target
    }
    // Brief "now playing" card when the track changes in the background.
    ToastTrack {
        screen: root.screen
        target: root.target
    }
    // What came in during a focus session, grouped by app. Stays until dismissed.
    ToastDigest {
        screen: root.screen
        target: root.target
    }
    ToastMessage {
        screen: root.screen
        target: root.target
    }
    // AirDrop requests: who sends what, Accept and Decline, then the files arriving.
    ToastAirDrop {
        screen: root.screen
        target: root.target
    }
}
