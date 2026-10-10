import QtQuick
import Quickshell
import "core"
import "features"
import "services"

// Isolated UI preview. Does not install configuration or change Hyprland.
ShellRoot {
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: Number(Quickshell.env("SHALE_VIEWPORT_WIDTH") || 1280)
        implicitHeight: Number(Quickshell.env("SHALE_VIEWPORT_HEIGHT") || 850)
        color: "#000000"
        title: "Shale preview"
        // Lock screen preview with a stand-in for the PAM-backed LockScreen.
        QtObject {
            id: lockPreview
            property string password: Quickshell.env("SHALE_DETAIL") === "error" ? "" : "secret"
            property bool busy: false
            property string status: Quickshell.env("SHALE_DETAIL") === "error" ? "Wrong password" : ""
            property bool unlocking: false
            property bool capsLock: Quickshell.env("SHALE_DETAIL") === "caps"
            property string attemptMessage: ""
            property string prompt: ""
            property bool promptVisible: false
            signal failed()
            signal powerFailed()
            function submit() {}
            function cancel() {}
            function shutdown() {}
            function checkCapsLock() {}
        }
        Loader {
            id: lockLoader
            anchors.fill: parent
            active: Quickshell.env("SHALE_PREVIEW") === "lock"
            sourceComponent: LockContent {
                context: lockPreview
            }
        }
        PanelContent {
            id: content
            visible: !lockLoader.active
            anchors.centerIn: parent
            width: Math.min(parent.width - 24, preferredWidth)
            height: Math.min(parent.height - 90, preferredHeight)
            panel: Quickshell.env("SHALE_PREVIEW") === "lock" ? "launcher" : Quickshell.env("SHALE_PREVIEW") || "launcher"
            active: true
        }
        Component.onCompleted: {
            ShellState.panel = content.panel;
            // "bare" / "<page>-bare": a desktop PC with no backlight, Wi-Fi, lid or capture tools.
            ShellState.detail = (Quickshell.env("SHALE_DETAIL") || "").replace(/-?bare$/, "");
            if (content.panel === "launcher" && content.pageItem && Quickshell.env("SHALE_QUERY"))
                content.pageItem.query = Quickshell.env("SHALE_QUERY");
            if (content.panel === "settings" && content.pageItem && Quickshell.env("SHALE_CATEGORY"))
                content.pageItem.category = Quickshell.env("SHALE_CATEGORY");
            if (content.panel === "capture" && content.pageItem && Quickshell.env("SHALE_CAPTURE_KIND"))
                content.pageItem.kind = Quickshell.env("SHALE_CAPTURE_KIND");
            if (content.panel === "notifications" && Quickshell.env("SHALE_POPULATED") === "1")
                Services.notifications = [{id: 99001, appName: "Calendar", summary: "Design review", body: "A long notification with several lines of text. ".repeat(25), timestamp: Date.now(), urgency: 1, actions: [{text: "Open event"}, {text: "Snooze until tomorrow"}], original: null}, {id: 99002, appName: "Downloads", summary: "Wallpaper saved", body: "Ready in your local collection.", timestamp: Date.now(), urgency: 1, actions: [], original: null}];
            if (content.panel === "calendar" && content.pageItem && Quickshell.env("SHALE_WEATHER") === "forecast")
                content.pageItem.weatherCard.preview = {location: {name: "Chișinău"}, stale: false, current: {temperature: 18, feelsLike: 15, label: "Clear", icon: "sun"},
                    days: [{date: "2026-10-01", label: "Mostly clear", icon: "cloud-sun", high: 20, low: 8}, {date: "2026-10-02", label: "Rain", icon: "rain", high: 16, low: 9}, {date: "2026-10-03", label: "Thunderstorm", icon: "storm", high: 14, low: 5}]};
            if (content.panel === "calendar" && content.pageItem && Quickshell.env("SHALE_WEATHER") === "search")
                content.pageItem.weatherCard.previewResults = [{name: "Chișinău", region: "Chișinău Municipality, Moldova"}, {name: "Chisinau", region: "Ialoveni, Moldova"}, {name: "Chișinău-Criș", region: "Arad, Romania"}];
            if (Quickshell.env("SHALE_LARGE_TEXT") === "1")
                ShellState.settings = Object.assign({}, ShellState.settings, { fontSize: 18, reducedMotion: true });
            if (Quickshell.env("SHALE_ACCENT") || Quickshell.env("SHALE_TONE"))
                ShellState.settings = Object.assign({}, ShellState.settings, {
                    accentColor: Quickshell.env("SHALE_ACCENT") || "#9ad6c6",
                    surfaceTone: Quickshell.env("SHALE_TONE") || "charcoal"
                });
            window.applyActivity();
        }
        // "ask", "on" or "off": the Activity panel's tracking state, kept over the helper's settings.
        function applyActivity() {
            const tracking = Quickshell.env("SHALE_ACTIVITY");
            if (tracking && ShellState.settings.activityTracking !== tracking)
                ShellState.settings = Object.assign({}, ShellState.settings, {activityTracking: tracking});
        }
        Connections {
            target: ShellState
            function onSettingsChanged() {
                if (Quickshell.env("SHALE_LARGE_TEXT") === "1" && (ShellState.settings.fontSize !== 18 || !ShellState.settings.reducedMotion))
                    ShellState.settings = Object.assign({}, ShellState.settings, { fontSize: 18, reducedMotion: true });
                const accent = Quickshell.env("SHALE_ACCENT");
                const tone = Quickshell.env("SHALE_TONE");
                if ((accent && ShellState.settings.accentColor !== accent) || (tone && ShellState.settings.surfaceTone !== tone))
                    ShellState.settings = Object.assign({}, ShellState.settings, {
                        accentColor: accent || ShellState.setting("accentColor", "#9ad6c6"),
                        surfaceTone: tone || ShellState.setting("surfaceTone", "charcoal")
                    });
                window.applyActivity();
            }
        }
        Timer {
            // After the helper's own first reports, so the stand-in hardware wins.
            interval: 1500
            running: /(^|-)bare$/.test(Quickshell.env("SHALE_DETAIL") || "")
            onTriggered: {
                Backend.capabilities = {commands: {hyprctl: true}, dbus: true, lid: false, builtinPanel: false, version: 1};
                ShellState.brightness = -1;
                ShellState.wifi = {available: false, reason: "No NetworkManager Wi-Fi device is available.", networks: [], powered: false, state: "unavailable"};
            }
        }
        Timer {
            interval: 2500
            running: Quickshell.env("SHALE_SCREENSHOT") !== ""
            onTriggered: (lockLoader.active ? lockLoader.item : content).grabToImage(result => {
                result.saveToFile(Quickshell.env("SHALE_SCREENSHOT"));
                Qt.quit();
            })
        }
    }
}
