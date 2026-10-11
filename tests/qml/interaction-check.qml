import QtQuick
import QtQml.Models
import QtTest
import Quickshell
import "components" as C
import "core"
import "features"
import "services"

ShellRoot {
    id: test
    property int step: 0
    property int ticks: 0
    property int failures: 0
    property string priorError: ""
    property string selected: ""
    // Set while a check drives real input: its waits run the event loop, and the step timer must not.
    property bool busy: false
    function check(condition, description) {
        if (!condition) {
            failures++;
            console.error("CHECK FAIL:", description);
        } else
            console.log("CHECK PASS:", description);
    }
    FloatingWindow {
        id: inputWindow
        visible: true
        implicitWidth: 1120
        implicitHeight: 600
        PanelContent {
            id: panel
            width: 680
            height: parent.height
            panel: ShellState.panel || "launcher"
        }
        TrayMenuList {
            id: trayList
            visible: false
            appName: "Steam"
        }
        // Bar-style buttons sharing one tooltip, as Bar.qml has them, and a notification card. One window
        // for everything: test keys go to the focused window.
        Item {
            x: 700
            width: 400
            height: parent.height
            C.Button {
                id: tipButton
                x: 20
                y: 20
                width: 30
                height: 30
                glyph: "bell"
                hint: "Notifications"
                tooltip: barTooltip
            }
            C.Button {
                id: neighbourButton
                x: 54
                y: 20
                width: 30
                height: 30
                glyph: "settings"
                hint: "Control center"
                tooltip: barTooltip
            }
            NotificationCard {
                id: keyCard
                y: 80
                notification: ({id: 0, appName: "", summary: "", body: "", actions: [], original: null})
            }
        }
        C.Tooltip {
            id: barTooltip
            anchor.window: inputWindow
        }
        TestCase { id: input; when: false }
    }
    function findButton(item, label) {
        for (const child of item.children) {
            if (child.visible && child.text === label && child.clicked !== undefined)
                return child;
            const found = findButton(child, label);
            if (found)
                return found;
        }
        return null;
    }
    function checkTooltip() {
        input.mouseMove(tipButton, 15, 15);
        input.wait(250);
        check(tipButton.hovered && !barTooltip.visible, "A bar button's tooltip waits for the pointer to rest");
        input.wait(450);
        check(barTooltip.visible && barTooltip.target === tipButton && barTooltip.text === "Notifications", "Resting on a bar button shows its hint in a tooltip");
        input.mouseMove(neighbourButton, 15, 15);
        input.wait(60);
        check(barTooltip.visible && barTooltip.text === "Control center", "Moving to a neighbouring button switches the tooltip at once");
        input.mousePress(neighbourButton, 15, 15);
        input.wait(Theme.leave + 120);
        check(!barTooltip.visible, "Pressing a button hides its tooltip");
        input.mouseRelease(neighbourButton, 15, 15);
        input.mouseMove(tipButton, 200, 200);
        input.wait(900);
        check(!barTooltip.visible, "The tooltip stays away once the pointer leaves");
    }
    function checkNotificationKeys() {
        let invoked = 0;
        const actionable = {id: 951, appName: "Mail", summary: "Keyboard", body: "", timestamp: Date.now(), original: {resident: false, dismiss() {}},
            actions: [{identifier: "default", text: "", invoke() { invoked++; }}]};
        Services.notifications = [actionable];
        keyCard.notification = actionable;
        neighbourButton.forceActiveFocus(Qt.TabFocusReason);
        input.keyClick(Qt.Key_Tab);
        check(keyCard.activeFocus && keyCard.border.width > 0, "Tab reaches a notification card and shows its focus ring");
        input.keyClick(Qt.Key_Return);
        check(invoked === 1 && Services.notifications.length === 0, "Enter on a focused card runs its default action");
        const plain = {id: 952, appName: "Mail", summary: "Plain", body: "", timestamp: Date.now(), actions: [], original: null};
        Services.notifications = [plain];
        keyCard.notification = plain;
        keyCard.forceActiveFocus(Qt.TabFocusReason);
        input.keyClick(Qt.Key_Space);
        check(Services.notifications.length === 1, "Space on a card without a default action leaves it in history");
        input.keyClick(Qt.Key_Delete);
        check(Services.notifications.length === 0, "Delete dismisses the focused card");
    }
    function checkCaptureAudio(page) {
        const system = findButton(page, "System"), microphone = findButton(page, "Microphone"), none = findButton(page, "None");
        check(!!system && !!microphone && !!none && none.selected, "Recording offers no audio, system audio or the microphone, none by default");
        if (!system || !microphone)
            return;
        input.mouseClick(system);
        check(ShellState.setting("recordAudio", "") === "system" && system.selected && !microphone.selected, "System audio can be chosen");
        input.mouseClick(microphone);
        check(ShellState.setting("recordAudio", "") === "microphone" && microphone.selected && !system.selected, "Choosing the microphone turns system audio off");
        input.mouseClick(system);
        check(system.selected && !microphone.selected, "System audio and the microphone are never both on");
        ShellState.setSetting("recordAudio", "none");
    }
    function checkActivity(page) {
        check(page.tracking === "ask" && !!findButton(page, "Not now"), "Activity asks before recording anything");
        input.mouseClick(findButton(page, "Not now"));
        check(ShellState.setting("activityTracking", "") === "off" && !findButton(page, "Not now") && !!findButton(page, "Turn on"), "Not now turns tracking off and leaves a way back");
        input.mouseClick(findButton(page, "Turn on"));
        check(ShellState.setting("activityTracking", "") === "on" && !findButton(page, "Turn on"), "Turn on shows the activity panel");
        input.wait(400);
        const start = new Date(page.selected);
        const shifted = days => {
            const date = new Date(start);
            date.setDate(date.getDate() + days);
            return Qt.formatDate(date, "yyyy-MM-dd");
        };
        const heatmap = page.nextItemInFocusChain(true);
        let grid = heatmap;
        for (let i = 0; i < 20 && grid && grid.Accessible.role !== Accessible.Table; i++)
            grid = grid.nextItemInFocusChain(true);
        check(!!grid && grid.Accessible.role === Accessible.Table, "Tab reaches the activity heatmap");
        if (!grid)
            return;
        grid.forceActiveFocus(Qt.TabFocusReason);
        input.keyClick(Qt.Key_Left);
        input.keyClick(Qt.Key_Up);
        check(page.selectedDate === shifted(-8), "Arrow keys move a week across the heatmap and a day down it");
        input.keyClick(Qt.Key_Return);
        check(page.mode === "day", "Enter on the heatmap opens the selected day");
        page.mode = "apps";
        input.wait(400);
        page.appsData = {range: "week", start: "", end: "", total: 120, previousTotal: 0, days: [],
            apps: [{app: "kitty", active: 60, watching: 0, total: 60, share: 0.5, previous: 0}, {app: "zen", active: 60, watching: 0, total: 60, share: 0.5, previous: 0}]};
        let row = page.nextItemInFocusChain(true);
        for (let i = 0; i < 40 && row && !(row.modelData && row.modelData.app === "kitty"); i++)
            row = row.nextItemInFocusChain(true);
        check(!!row && row.modelData.app === "kitty", "Tab reaches the app rows");
        if (!row)
            return;
        row.forceActiveFocus(Qt.TabFocusReason);
        input.keyClick(Qt.Key_Down);
        input.keyClick(Qt.Key_Return);
        check(page.appDetail === "zen", "Down and Enter open the next app");
        ShellState.setSetting("activityTracking", "ask");
    }
    property var systemKeys: null
    property int systemSamples: 0
    function checkSystem(page) {
        check(page.resources.length >= 2 && page.resources[0].key === "cpu" && page.resources[1].key === "memory", "System lists CPU and memory first");
        check(page.sample.cpu.usage >= 0 && page.sample.cpu.usage <= 100 && page.sample.memory.used > 0, "System samples real usage");
        page.forceActiveFocus();
        page.selected = "cpu";
        input.keyClick(Qt.Key_Down);
        check(page.selected === "memory", "Down selects the next resource");
        input.keyClick(Qt.Key_End);
        check(page.selected === page.resources[page.resources.length - 1].key, "End selects the last resource");
        input.keyClick(Qt.Key_Home);
        input.keyClick(Qt.Key_Up);
        check(page.selected === "cpu", "Selection stops at the first resource");
    }
    function checkTrayMenu() {
        const kinds = () => trayList.rows.map(row => row.kind).join(",");
        const library = {text: "_Library", enabled: true, isSeparator: false, hasChildren: true, buttonType: 0};
        const friends = {text: "Friends && chat", enabled: false, isSeparator: false, hasChildren: false, buttonType: 1, checkState: Qt.Checked};
        const rule = {isSeparator: true};
        trayList.entries = [rule, library, rule, rule, friends, rule];
        check(kinds() === "open,separator,entry,separator,entry,separator,quit", "Tray menu drops doubled separators and adds Open and Quit");
        check(trayList.label(library.text) === "Library" && trayList.label(friends.text) === "Friends & chat", "Tray menu labels drop mnemonic markers");
        trayList.entries = [library, {text: "E_xit Steam", enabled: true, isSeparator: false}];
        check(kinds() === "open,entry,entry", "Quit is left out when the app's menu has its own");
        trayList.entries = [];
        trayList.canOpen = false;
        check(kinds() === "quit", "An app without a menu still gets Quit");
        trayList.canOpen = true;
        const chosen = [];
        const choose = entry => chosen.push(entry.text);
        let back = 0, closed = 0;
        const goBack = () => back++, close = () => closed++;
        trayList.entryChosen.connect(choose);
        trayList.backRequested.connect(goBack);
        trayList.closeRequested.connect(close);
        trayList.activate({kind: "entry", entry: friends});
        trayList.activate({kind: "entry", entry: library});
        check(chosen.join() === "_Library", "Disabled tray entries can't be chosen");
        trayList.submenu = "Library";
        trayList.entries = [friends];
        check(kinds() === "back,entry", "A submenu shows Back instead of Open and Quit");
        trayList.dismiss();
        trayList.submenu = "";
        trayList.dismiss();
        check(back === 1 && closed === 1, "Escape leaves a submenu first, then closes the menu");
        trayList.entryChosen.disconnect(choose);
        trayList.backRequested.disconnect(goBack);
        trayList.closeRequested.disconnect(close);
    }
    Instantiator {
        id: notificationProbe
        model: Services.notificationModel
        delegate: QtObject { required property var notificationData }
    }
    Instantiator {
        id: popupProbe
        model: Services.popupModel
        delegate: QtObject { required property var notificationData }
    }
    function checkNotifications() {
        const first = {id: 901, appName: "Alpha", summary: "First", timestamp: 10, actions: [], original: null};
        const second = {id: 902, appName: "Beta", summary: "Second", timestamp: 20, actions: [], original: null};
        Services.notifications = [first];
        Services.popupIds = [901];
        const historyDelegate = notificationProbe.objectAt(0);
        const popupDelegate = popupProbe.objectAt(0);
        Services.notifications = [second, first];
        Services.popupIds = [901, 902];
        check(notificationProbe.objectAt(1) === historyDelegate && popupProbe.objectAt(0) === popupDelegate, "Adding another notification preserves existing delegates");
        Services.notifications = [second, Object.assign({}, first, {summary: "Updated", appName: "Zeta"})];
        check(notificationProbe.objectAt(1) === historyDelegate && historyDelegate.notificationData.summary === "Updated", "Notification updates move the same delegate and refresh its content");
        check(popupProbe.objectAt(0) === popupDelegate && popupDelegate.notificationData.summary === "Updated", "Popup updates preserve identity and refresh content");
        Services.dismissNotification(902);
        check(notificationProbe.objectAt(0) === historyDelegate && Services.notificationModel.count === 1 && Services.popupModel.count === 1, "Dismissing one notification preserves the other");
        Services.dismissAllNotifications();
        check(Services.notificationModel.count === 0 && Services.popupModel.count === 0, "Clear all empties both notification models");
        Services.notifications = [
            {id: 911, appName: "Alpha", summary: "Old", timestamp: 10, actions: [], original: null},
            {id: 912, appName: "Beta", summary: "New", timestamp: 30, actions: [], original: null},
            {id: 913, appName: "Alpha", summary: "Newer alpha", timestamp: 20, actions: [], original: null}
        ];
        const order = [];
        for (let i = 0; i < Services.notificationModel.count; i++)
            order.push(Services.notificationModel.get(i).notificationId);
        check(order.join(",") === "912,913,911", "History groups follow their newest notification");
        Services.dismissAllNotifications();
        const incoming = id => ({id: id, summary: "Popup " + id, body: "", appName: "Burst", appIcon: "", image: "", urgency: 1, actions: [], transient: false, expireTimeout: -1, dismiss() {}, expire() {}});
        for (const id of [921, 922, 923, 924])
            Services.receiveNotification(incoming(id));
        check(Services.popupIds.join(",") === "922,923,924", "A fourth popup retires the oldest instead of being dropped");
        Services.pausePopup(922, true);
        Services.receiveNotification(incoming(925));
        check(Services.popupIds.join(",") === "922,924,925", "A hovered popup is never retired");
        Services.dismissAllNotifications();
        const inHistory = id => {
            for (let i = 0; i < Services.notificationModel.count; i++)
                if (Services.notificationModel.get(i).notificationId === id)
                    return true;
            return false;
        };
        let closings = 0;
        Services.receiveNotification(Object.assign(incoming(941), {actions: [{identifier: "open", text: "Open", invoke() {}}], expire() { closings++; }}));
        Services.popupDeadlines[941] = 1;
        Services.popupClock.triggered();
        check(Services.popupIds.indexOf(941) === -1 && closings === 0 && Services.notifications[0].actions.length === 1, "A popup that times out stays in history with its actions");
        Services.receiveNotification(Object.assign(incoming(942), {urgency: 2, expireTimeout: 1500}));
        check(Services.popupIds.indexOf(942) >= 0 && Services.popupDeadlines[942] === 0, "Critical notifications stay until dismissed");
        Services.receiveNotification(Object.assign(incoming(943), {transient: true, expire() { closings++; }}));
        check(Services.popupIds.indexOf(943) >= 0 && !inHistory(943) && inHistory(941), "Transient notifications pop up but stay out of history");
        Services.hidePopup(943);
        check(closings === 1 && !Services.notifications.some(n => n.id === 943), "A transient notification closes with its popup");
        Services.dismissAllNotifications();
        let invoked = 0;
        Services.notifications = [{id: 931, appName: "Mail", summary: "Message", timestamp: 1, original: {resident: false, dismiss() {}},
            actions: [{identifier: "reply", text: "Reply", invoke() {}}, {identifier: "default", text: "", invoke() { invoked++; }}]}];
        check(Services.invokeDefault(931) && invoked === 1 && Services.notifications.length === 0, "Clicking a card runs its default action and dismisses it");
        Services.notifications = [{id: 932, appName: "Mail", summary: "Plain", timestamp: 1, actions: [], original: null}];
        check(!Services.invokeDefault(932), "Cards without a default action report no action");
        Services.dismissAllNotifications();
        ShellState.open("control");
        ShellState.osdVisible = false;
        ShellState.osd("Volume", 0.5, "volume", false);
        check(!ShellState.osdVisible, "Volume OSD stays hidden while control center shows the slider");
        ShellState.detail = "wifi";
        ShellState.osd("Volume", 0.5, "volume", false);
        check(ShellState.osdVisible, "Volume OSD returns on control pages without a volume slider");
        ShellState.close();
        ShellState.osdVisible = false;
        ShellState.osd("Muted", 0.4, "mute", true);
        check(ShellState.osdVisible && ShellState.osdMuted && ShellState.osdValue === 0.4, "Muted OSD keeps the real level");
        ShellState.osdVisible = false;
    }
    Component.onCompleted: ShellState.open("launcher")
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            if (test.busy)
                return;
            if (++test.ticks > 80) {
                test.check(false, "Interaction check timed out");
                Qt.quit();
                return;
            }
            const page = panel.pageItem;
            if (!page || !Backend.ready)
                return;
            switch (test.step) {
            case 0:
                page.query = "6 * 7";
                test.step++;
                break;
            case 1:
                if (!page.calculationValid)
                    return;
                test.check(page.calculation === "42", "Calculator evaluates current expression");
                page.query = "8 * 8";
                test.check(!page.calculationValid && page.calculation === "", "Editing invalidates the previous result immediately");
                test.step++;
                break;
            case 2:
                if (!page.calculationValid)
                    return;
                test.check(page.calculation === "64", "Only the latest expression becomes copyable");
                test.priorError = Backend.lastError;
                page.query = "1 / 0";
                test.step++;
                break;
            case 3:
                if (page.calculating || !page.calculationError)
                    return;
                test.check(!page.calculationValid, "Invalid expressions cannot be copied");
                const sequence = Backend.sequence;
                page.copyCalculation();
                test.check(Backend.sequence === sequence, "Invalid copy never requests clipboard modification");
                test.check(Backend.lastError === test.priorError, "Incomplete arithmetic does not pollute global errors");
                page.query = "firefox";
                test.step++;
                break;
            case 4:
                test.check(!page.calculatorQuery && !page.calculationValid && page.calculation === "", "Application search clears inline calculation state");
                test.check(page.mode === "apps" && page.results.every(item => item.kind === "app" && !!item.entry), "Plain queries search applications only");
                test.check(page.modeOf(":smile") === "emoji" && page.modeOf("/notes") === "files" && page.modeOf("?weather") === "web" && page.modeOf("fire:fox") === "apps", "A leading prefix picks the launcher mode");
                test.check(page.isConversion("10 km to mi") && page.isConversion("72 f in c") && !page.isConversion("firefox") && !page.isConversion("= 2 + 2") && !page.isExpression("/2"), "Unit conversions are recognized without catching prefixes");
                test.check(!page.isExpression("1Password") && !page.isExpression("123") && page.isExpression("6 * 7"), "Numeric app names stay in application search");
                page.lastPointer = Qt.point(-1, -1);
                test.check(!page.pointerMoved(Qt.point(40, 80)) && !page.pointerMoved(Qt.point(40, 80)), "Rows appearing under a resting pointer keep keyboard selection");
                test.check(page.pointerMoved(Qt.point(40, 120)), "Moving the pointer selects the hovered row");
                page.query = ":heart";
                test.step = 42;
                break;
            case 42:
                // The emoji list loads on first use.
                if (!page.results.length)
                    return;
                test.check(page.mode === "emoji" && page.results.every(item => item.kind === "emoji"), "A colon searches emoji");
                // Leaving emoji mode must not hand app rows to the emoji grid (any QML warning fails the check).
                page.query = "fire";
                page.query = "";
                test.step = 40;
                break;
            case 40:
                // Needs a few installed apps; select the third, then pin a later one so the list re-sorts.
                if (page.results.length < 6) {
                    test.check(true, "Re-sort keeps selection (skipped: fewer than 6 apps installed)");
                    page.query = "= 2^8";
                    test.step = 5;
                    break;
                }
                page.moveSelection(2);
                test.selected = page.results[page.view.currentIndex].key;
                ShellState.setSetting("pinnedApps", [page.results[5].key]);
                test.step = 41;
                break;
            case 41:
                test.check(page.results[0].key !== test.selected && page.results[page.view.currentIndex].key === test.selected,
                           "Re-sorting the same query (pinning) keeps the selected app");
                ShellState.setSetting("pinnedApps", []);
                page.query = "= 2^8";
                test.step = 5;
                break;
                case 5:
                    if (!page.calculationValid) return;
                    test.check(page.calculation === "256", "Explicit expressions and caret powers calculate inline");
                    test.check(page.expression("= 6 × 7 ÷ 2 − 1") === "6 * 7 / 2 - 1", "Common arithmetic symbols are normalized");
                    ShellState.open("control", "display-a");
                    ShellState.toggle("control", "display-b");
                    test.check(ShellState.panel === "control" && ShellState.screenName === "display-b", "Requesting an open panel on another output moves it");
                    ShellState.toggle("control", "display-b");
                    test.check(ShellState.panel === "", "Toggling on the same output closes it");
                test.checkNotifications();
                test.checkTrayMenu();
                ShellState.open("clipboard");
                test.step++;
                break;
            case 6:
                page.query = "old";
                page.refresh();
                const oldRequest = Backend.sequence;
                page.query = "new";
                page.refresh();
                const newRequest = Backend.sequence;
                Backend.receive(JSON.stringify({ id: oldRequest, ok: true, result: { entries: [{raw: "old", text: "old"}] } }));
                test.check(page.busy && page.entries.length === 0, "Stale clipboard response cannot replace results or clear loading");
                Backend.receive(JSON.stringify({ id: newRequest, ok: true, result: { entries: [{raw: "new", text: "new"}] } }));
                test.check(!page.busy && page.entries[0].text === "new", "Latest clipboard response becomes selectable");
                page.query = "next";
                const beforeCopy = Backend.sequence;
                page.copy({raw: "new", text: "new"});
                test.check(page.entries.length === 0 && Backend.sequence === beforeCopy, "Changing search clears stale entries and blocks stale copy");
                page.busy = false;
                page.mutate("system.stats", {});
                const pendingMutation = Backend.sequence;
                page.mutate("system.stats", {});
                page.copy({raw: "new", text: "new"});
                test.check(page.mutating && Backend.sequence === pendingMutation, "Pending clipboard mutation blocks duplicate actions and copy");
                Backend.receive(JSON.stringify({id: pendingMutation, ok: false, error: {message: "Temporary history failure"}}));
                test.check(!page.mutating && page.error === "Temporary history failure", "Clipboard mutation failure restores controls and exposes retry error");
                ShellState.open("capture");
                test.step++;
                break;
            case 7:
                if (page.missingTool === undefined)
                    return;
                page.kind = "recording";
                test.step++;
                break;
            case 8:
                test.busy = true;
                test.checkCaptureAudio(page);
                ShellState.open("activity");
                test.busy = false;
                test.step++;
                break;
            case 9:
                if (page.tracking === undefined)
                    return;
                test.busy = true;
                test.checkActivity(page);
                test.checkTooltip();
                test.checkNotificationKeys();
                test.busy = false;
                ShellState.open("system");
                test.step++;
                break;
            case 10:
                // Two samples from the real helper: the second has rates and a two-point history.
                if (page.sample === undefined || !page.sample || (page.history.cpu || []).length < 2)
                    return;
                test.busy = true;
                test.checkSystem(page);
                test.systemKeys = page.resourceKeys;
                test.systemSamples = page.history.cpu.length;
                test.busy = false;
                test.step++;
                break;
            case 11:
                if (page.history.cpu.length <= test.systemSamples && page.history.cpu.length < page.capacity)
                    return;
                test.check(page.resourceKeys === test.systemKeys, "A new sample keeps the resource rows instead of rebuilding them");
                console.log("INTERACTION CHECK COMPLETE", test.failures);
                Qt.quit();
                break;
            }
        }
    }
}
