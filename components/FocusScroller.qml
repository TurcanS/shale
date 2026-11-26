import QtQuick

// Keeps the keyboard focus in view: when focus moves to an item inside `content`, `flickable` scrolls just far enough
// to show it, with a little room around it. Place it anywhere in the same window.
Item {
    id: root
    // A Flickable, or a ScrollView's contentItem (declared as an Item).
    property Item flickable: null
    readonly property Flickable target: flickable as Flickable
    property Item content: null
    property int margin: 12
    visible: false
    function reveal() {
        const item = Window.activeFocusItem;
        if (!item || !target || !content || !target.visible)
            return;
        let inside = item;
        while (inside && inside !== content)
            inside = inside.parent;
        if (!inside)
            return;
        const top = item.mapToItem(target.contentItem, 0, 0).y;
        const bottom = top + item.height;
        const shown = target.height;
        const most = Math.max(0, target.contentHeight - shown);
        if (top - margin < target.contentY)
            target.contentY = Math.max(0, top - margin);
        else if (bottom + margin > target.contentY + shown)
            target.contentY = Math.min(most, bottom + margin - shown);
    }
    Connections {
        target: root.Window
        function onActiveFocusItemChanged() {
            root.reveal();
        }
    }
}
