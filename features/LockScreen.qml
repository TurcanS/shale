import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import "../core"
import "../core/paths.js" as Paths

// The Shale lock screen: an ext-session-lock surface on every output, one shared password check.
// Only PAM success unlocks it. If the shell dies while locked, Hyprland keeps the session locked and
// scripts/session-action hands over to hyprlock (misc:allow_session_lock_restore).
Scope {
    id: root
    // Shared by every output so typing on one screen shows on all of them.
    property string password: ""
    property bool busy: false
    property string status: ""
    property bool unlocking: false
    property bool capsLock: false
    property int failures: 0
    // Informational PAM text from this attempt, such as pam_faillock's lockout notice or a
    // fingerprint reader's "place your finger"; shown while the check runs.
    property string attemptMessage: ""
    // The typed password answers PAM's first question. A further one, such as a one-time code,
    // is asked in the field: `prompt` holds it until it is answered.
    property bool answered: false
    property string prompt: ""
    property bool promptVisible: false
    property string pamConfig: "login"
    // Tests point this at a directory of stand-in PAM services.
    property string pamDirectory: "/etc/pam.d"
    signal failed()
    signal powerFailed()

    // Shutting down from the lock screen, as other desktops allow. logind refuses when, for
    // example, another user is logged in; the button then resets and says why.
    function shutdown() {
        if (!powerOff.running)
            powerOff.running = true;
    }
    Process {
        id: powerOff
        command: [Paths.localPath(Qt.resolvedUrl("../scripts/session-action")), "shutdown"]
        onExited: code => {
            if (code !== 0) {
                root.status = "Could not shut down. Another user or app may be preventing it.";
                root.powerFailed();
            }
        }
    }

    function submit() {
        if (prompt !== "" && pam.active && !busy) {
            prompt = "";
            busy = true;
            pam.respond(password);
            return;
        }
        if (busy || unlocking || password === "")
            return;
        busy = true;
        status = "";
        attemptMessage = "";
        answered = false;
        if (!pam.start()) {
            busy = false;
            status = "Could not start the password check. Try again.";
        }
    }
    // Escape clears the field, or gives up on PAM's follow-up question to start over.
    function cancel() {
        password = "";
        if (prompt === "")
            return;
        prompt = "";
        if (pam.active)
            pam.abort();
    }
    function finish(success) {
        busy = false;
        prompt = "";
        if (success) {
            // Let the screen fade before the compositor removes it.
            unlocking = true;
            password = "";
            status = "";
            failures = 0;
            unlockDelay.restart();
            return;
        }
        password = "";
        failures++;
        status = attemptMessage || "Wrong password";
        failed();
    }
    // Long enough for the style's unlock animation: the particles burst apart, the classic screen fades.
    Timer {
        id: unlockDelay
        interval: Theme.reduced ? 0 : ShellState.setting("lockStyle", "particles") === "classic" ? 180 : Theme.lowPower ? 600 : 1000
        onTriggered: {
            ShellState.unlockShell();
            root.unlocking = false;
        }
    }
    // hyprlock's PAM service matches what the user already relies on; login is the fallback.
    Process {
        command: ["test", "-f", "/etc/pam.d/hyprlock"]
        running: true
        onExited: code => root.pamConfig = code === 0 ? "hyprlock" : "login"
    }
    PamContext {
        id: pam
        config: root.pamConfig
        configDirectory: root.pamDirectory
        onPamMessage: {
            if (responseRequired && !root.answered) {
                root.answered = true;
                respond(root.password);
            } else if (responseRequired) {
                root.password = "";
                root.promptVisible = responseVisible;
                root.prompt = message.trim() || "Answer";
                root.busy = false;
            } else if (message.trim() !== "") {
                root.attemptMessage = message.trim();
            }
        }
        onCompleted: result => root.finish(result === PamResult.Success)
        onError: error => {
            root.busy = false;
            root.prompt = "";
            root.password = "";
            root.status = "Could not check the password (" + PamError.toString(error) + ").";
        }
    }
    // Caps Lock is the most common reason for a wrong password. Each screen's password field asks
    // for a check while someone is typing into it.
    function checkCapsLock() {
        if (!capsCheck.running)
            capsCheck.running = true;
    }
    Process {
        id: capsCheck
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const keyboards = JSON.parse(text).keyboards || [];
                    const main = keyboards.find(k => k.main) || keyboards[0];
                    root.capsLock = !!main && !!main.capsLock;
                } catch (error) {
                    root.capsLock = false;
                }
            }
        }
    }
    Connections {
        target: ShellState
        function onLockedChanged() {
            if (!ShellState.locked) {
                root.password = "";
                root.status = "";
                root.prompt = "";
                root.failures = 0;
                if (pam.active)
                    pam.abort();
            }
        }
    }
    // The desktop comes back from the clock outward instead of appearing all at once.
    Variants {
        model: Quickshell.screens
        delegate: UnlockReveal {
            id: reveal
            required property var modelData
            screen: reveal.modelData
            context: root
        }
    }
    WlSessionLock {
        id: lock
        locked: ShellState.locked && ShellState.lockOwner === "shell"
        onSecureChanged: ShellState.lockSecure = secure
        WlSessionLockSurface {
            id: surface
            color: "#000000"
            LockContent {
                anchors.fill: parent
                context: root
                screenName: surface.screen ? surface.screen.name : ""
            }
        }
    }
}
