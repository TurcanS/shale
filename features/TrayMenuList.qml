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
    // Folding out (TrayMenu): each row unfolds on its hinge under the one above, foldGap ms after it; foldAt is how
    // far into the fold the menu is, in ms.
    property bool foldActive: false
    property real foldAt: 0
    property int foldGap: 60
    property int foldSpan: 260
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
    // Scrolls a row the keyboard reached into view.
    function reveal(item) {
        const y = item.mapToItem(column, 0, 0).y;
        if (y < scroller.contentY)
            scroller.contentY = y;
        else if (y + item.height > scroller.contentY + scroller.height)
            scroller.contentY = y + item.height - scroller.height;
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
    // A long menu (a chat app's, a game launcher's) scrolls inside the screen instead of running off it.
    Flickable {
        id: scroller
        anchors.fill: parent
        contentHeight: column.implicitHeight
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        ColumnLayout {
            id: column
            width: scroller.width
            spacing: 2
            C.Label {
                visible: root.submenu !== ""
                text: root.submenu
                color: Theme.textDim
                font.pixelSize: 12
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
                    required property int index
                    readonly property real fold: root.foldActive ? Motion.clamp((root.foldAt - index * root.foldGap) / Math.max(1, root.foldSpan), 0, 1) : 1
                    opacity: Math.min(1, fold * 3)
                    transform: Rotation {
                        origin.x: rowLoader.width / 2
                        origin.y: 0
                        axis { x: 1; y: 0; z: 0 }
                        angle: rowLoader.fold >= 1 ? 0 : 92 * (1 - Motion.seat(Motion.ov(1.4), rowLoader.fold))
                    }
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
                                color: Theme.separator
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
                            cornerRadius: 8
                            leftPadding: 10
                            rightPadding: 10
                            hint: text
                            text: row.kind === "back" ? "Back" : row.kind === "open" ? "Open " + root.appName
                                : row.kind === "quit" ? "Quit " + root.appName : root.label(entry.text)
                            onClicked: root.activate(row)
                            onActiveFocusChanged: if (activeFocus) root.reveal(rowButton)
                            Keys.onReturnPressed: root.activate(row)
                            Keys.onEnterPressed: root.activate(row)
                            contentItem: RowLayout {
                                spacing: Theme.gapM
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
                                    color: rowButton.foreground
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
}
