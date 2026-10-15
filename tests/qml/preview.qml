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
        readonly property bool barPreview: Quickshell.env("SHALE_PREVIEW") === "bar"
        PanelContent {
            id: content
            visible: !lockLoader.active && !window.barPreview
            anchors.centerIn: parent
            width: Math.min(parent.width - 24, preferredWidth)
            height: Math.min(parent.height - 90, preferredHeight)
            panel: ["lock", "bar"].indexOf(Quickshell.env("SHALE_PREVIEW")) >= 0 ? "launcher" : Quickshell.env("SHALE_PREVIEW") || "launcher"
            active: true
        }
        // The bar as it sits at the top of a screen, with a few status items showing.
        Rectangle {
            id: barFrame
            visible: window.barPreview
            width: parent.width
            height: 42
            color: "#000000"
            BarContent {
                readonly property bool edge: ShellState.setting("barStyle", "floating") === "edge"
                x: edge ? 0 : 8
                y: edge ? 0 : 5
                width: parent.width - 2 * x
                height: 32
                outputName: "preview"
            }
        }
        Component.onCompleted: {
            ShellState.panel = content.panel;
            // "bare" / "<page>-bare": a desktop PC with no backlight, Wi-Fi, lid or capture tools.
            // "wifi-vpn": the Wi-Fi page with sample VPN profiles.
            ShellState.detail = (Quickshell.env("SHALE_DETAIL") || "").replace(/-?bare$/, "").replace(/-vpn$/, "");
            window.applyVpn();
            if (content.panel === "launcher" && content.pageItem && Quickshell.env("SHALE_QUERY"))
                content.pageItem.query = Quickshell.env("SHALE_QUERY");
            if (content.panel === "settings" && content.pageItem && Quickshell.env("SHALE_CATEGORY"))
                content.pageItem.category = Quickshell.env("SHALE_CATEGORY");
            if (content.panel === "capture" && content.pageItem && Quickshell.env("SHALE_CAPTURE_KIND"))
                content.pageItem.kind = Quickshell.env("SHALE_CAPTURE_KIND");
            if (content.panel === "notifications" && Quickshell.env("SHALE_POPULATED") === "1")
                Services.notifications = [{id: 99001, appName: "Calendar", summary: "Design review", body: "A long notification with several lines of text. ".repeat(25), timestamp: Date.now(), urgency: 1, actions: [{text: "Open event"}, {text: "Snooze until tomorrow"}], original: null}, {id: 99002, appName: "Downloads", summary: "Wallpaper saved", body: "Ready in your local collection.", image: Qt.resolvedUrl("assets/icons/music.svg"), timestamp: Date.now(), urgency: 1, actions: [], original: null}];
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
            window.applySettings();
            if (window.barPreview) {
                ShellState.keyboard = {layouts: [{code: "us", variant: ""}, {code: "ro", variant: ""}], index: 0, name: "English (US)"};
                ShellState.presentation = true;
            }
        }
        // SHALE_SETTINGS: a JSON object of settings kept over the helper's.
        readonly property var previewSettings: JSON.parse(Quickshell.env("SHALE_SETTINGS") || "{}")
        function applySettings() {
            if (Object.keys(previewSettings).some(key => JSON.stringify(ShellState.settings[key]) !== JSON.stringify(previewSettings[key])))
                ShellState.settings = Object.assign({}, ShellState.settings, previewSettings);
        }
        readonly property var sampleVpn: ({available: true, connections: [{path: "/s/2", name: "home-wg", kind: "wireguard", state: "on"},
                                                                         {path: "/s/1", name: "Office", kind: "openvpn", state: "off"}]})
        function applyVpn() {
            if (/-vpn$/.test(Quickshell.env("SHALE_DETAIL") || "") && ShellState.vpn !== sampleVpn)
                ShellState.vpn = sampleVpn;
        }
        Connections {
            target: ShellState
            function onVpnChanged() {
                window.applyVpn();
            }
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
                window.applySettings();
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
        // SHALE_SCROLL: how far down a Settings page to show.
        Timer {
            interval: 1800
            running: content.panel === "settings" && Quickshell.env("SHALE_SCROLL") !== ""
            onTriggered: content.pageItem.scrollTo(Number(Quickshell.env("SHALE_SCROLL")))
        }
        Timer {
            interval: 2500
            running: Quickshell.env("SHALE_SCREENSHOT") !== ""
            onTriggered: (lockLoader.active ? lockLoader.item : window.barPreview ? barFrame : content).grabToImage(result => {
                result.saveToFile(Quickshell.env("SHALE_SCREENSHOT"));
                Qt.quit();
            })
        }
    }
}
