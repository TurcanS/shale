import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

// The rows of a tray app's menu in Shale's style. TrayMenu feeds it the app's QsMenuEntry objects;
// the interaction check feeds it plain objects with the same fields.
FocusScope {
    id: root
    property var entries: []
    property string appName: ""
    property bool canOpen: true
    // Title of the open submenu, or "" at the top level.
    property string submenu: ""
    signal openRequested()
    signal quitRequested()
    signal entryChosen(var entry)
    signal backRequested()
    signal closeRequested()
    implicitWidth: 260
    implicitHeight: column.implicitHeight

    // "_Quit" and "&Quit" mark keyboard mnemonics; a doubled marker is the literal character.
    function label(text) {
        return String(text || "").replace(/([_&])\1|[_&]/g, (match, doubled) => doubled || "").trim();
    }
    function ownsQuit(list) {
        return list.some(entry => !entry.isSeparator && /^(quit|exit|close)\b/i.test(label(entry.text)));
    }
    readonly property var rows: {
        const rows = [];
        if (submenu !== "")
            rows.push({kind: "back"});
        else if (canOpen)
            rows.push({kind: "open"});
        for (const entry of entries) {
            // No leading, trailing or doubled separators.
            if (entry.isSeparator) {
                if (rows.length && rows[rows.length - 1].kind !== "separator")
                    rows.push({kind: "separator"});
            } else
                rows.push({kind: "entry", entry: entry});
        }
        if (submenu === "" && !ownsQuit(entries)) {
            if (rows.length && rows[rows.length - 1].kind !== "separator")
                rows.push({kind: "separator"});
            rows.push({kind: "quit"});
        }
        while (rows.length && rows[rows.length - 1].kind === "separator")
            rows.pop();
        return rows;
    }
    function activate(row) {
        if (row.kind === "back")
            backRequested();
        else if (row.kind === "open")
            openRequested();
        else if (row.kind === "quit")
            quitRequested();
        else if (row.kind === "entry" && row.entry.enabled !== false)
            entryChosen(row.entry);
    }
    function dismiss() {
        if (submenu !== "")
            backRequested();
        else
            closeRequested();
    }
    function focusFirst() {
        for (let i = 0; i < repeater.count; i++) {
            const row = repeater.itemAt(i) ? repeater.itemAt(i).item : null;
            if (row && row.activeFocusOnTab && row.enabled) {
                row.forceActiveFocus(Qt.TabFocusReason);
                return;
            }
        }
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape || (event.key === Qt.Key_Left && submenu !== "")) {
            dismiss();
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
            const current = Window.activeFocusItem;
            const next = current ? current.nextItemInFocusChain(event.key === Qt.Key_Down) : null;
            if (next)
                next.forceActiveFocus(Qt.TabFocusReason);
            else
                focusFirst();
        } else
            return;
        event.accepted = true;
    }
    ColumnLayout {
        id: column
        width: parent.width
        spacing: 2
        C.Label {
            visible: root.submenu !== ""
            text: root.submenu
            color: Theme.muted
            font.pixelSize: Theme.small
            elide: Text.ElideRight
            Layout.fillWidth: true
            Layout.leftMargin: 10
            Layout.topMargin: 4
            Layout.bottomMargin: 2
        }
        Repeater {
            id: repeater
            model: root.rows
            delegate: Loader {
                id: rowLoader
                required property var modelData
                Layout.fillWidth: true
                sourceComponent: modelData.kind === "separator" ? separator : button
                Component {
                    id: separator
                    Item {
                        implicitHeight: 9
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 1
                            color: Theme.border
                        }
                    }
                }
                Component {
                    id: button
                    C.Button {
                        id: rowButton
                        readonly property var row: rowLoader.modelData
                        readonly property var entry: row.entry || null
                        flat: true
                        danger: row.kind === "quit"
                        enabled: row.kind !== "entry" || entry.enabled !== false
                        implicitHeight: Math.max(32, Theme.body + 18)
                        hint: text
                        text: row.kind === "back" ? "Back" : row.kind === "open" ? "Open " + root.appName
                            : row.kind === "quit" ? "Quit " + root.appName : root.label(entry.text)
                        onClicked: root.activate(row)
                        Keys.onReturnPressed: root.activate(row)
                        Keys.onEnterPressed: root.activate(row)
                        contentItem: RowLayout {
                            spacing: 10
                            // Checkbox and radio entries keep one column for their mark, so labels line up.
                            C.Icon {
                                visible: row.kind === "back" || (!!entry && entry.buttonType > 0)
                                name: row.kind === "back" ? "back" : entry && entry.checkState === Qt.Checked ? "check" : ""
                                size: 14
                                Layout.preferredWidth: 14
                            }
                            Image {
                                visible: !!entry && !!entry.icon
                                source: entry && entry.icon ? entry.icon : ""
                                sourceSize.width: 16
                                sourceSize.height: 16
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                fillMode: Image.PreserveAspectFit
                            }
                            C.Label {
                                text: rowButton.text
                                color: !rowButton.enabled ? Theme.disabled : row.kind === "quit" ? Theme.danger : Theme.text
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            C.Icon {
                                visible: !!entry && !!entry.hasChildren
                                name: "chevron"
                                size: 14
                            }
                        }
                    }
                }
            }
        }
    }
}
