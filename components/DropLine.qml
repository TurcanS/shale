import QtQuick
import QtQuick.Layouts
import "../core"

// Where a dragged OrderRow will land: an accent line between the rows of the group nearest to it. It sits in the
// page's layout without a height of its own (give it a negative top margin of the layout's spacing) and draws over
// the groups above it.
Item {
    id: root
    // The lists a row may land in: [{key, group}], `group` being the Group that holds that list's OrderRows.
    property var targets: []
    // The row being dragged, or null.
    property Item row: null
    // {key, index}: the list and the place in it, counted without the dragged row.
    readonly property var drop: row ? find(row.dragOffset) : null
    Layout.fillWidth: true
    Layout.preferredHeight: 0
    z: 3
    function rowsOf(group) {
        return group.shown.filter(item => item.itemId !== undefined && item !== row && item.shown);
    }
    // The nearest group by height, then the place among its rows where the dragged row's middle falls.
    function find(offset) {
        const middle = row.mapToItem(root, 0, row.height / 2).y;
        let best = null;
        let bestDistance = Infinity;
        for (const target of targets) {
            const group = target.group;
            if (!group || !group.visible)
                continue;
            const top = group.mapToItem(root, 0, 0).y;
            const distance = middle < top ? top - middle : middle > top + group.height ? middle - top - group.height : 0;
            if (distance < bestDistance) {
                best = target;
                bestDistance = distance;
            }
        }
        if (!best)
            return null;
        const rows = rowsOf(best.group);
        const index = rows.filter(item => item.mapToItem(root, 0, item.height / 2).y < middle).length;
        const after = index > 0 ? rows[index - 1] : null;
        const before = index < rows.length ? rows[index] : null;
        const top = best.group.mapToItem(root, 0, 0);
        return {
            key: best.key,
            index: index,
            x: top.x,
            width: best.group.width,
            y: before ? before.mapToItem(root, 0, 0).y : after ? after.mapToItem(root, 0, after.height).y : top.y + 4
        };
    }
    Rectangle {
        visible: !!root.drop
        x: root.drop ? root.drop.x + 12 : 0
        y: root.drop ? root.drop.y - 1 : 0
        width: root.drop ? root.drop.width - 24 : 0
        height: 2
        radius: 1
        color: Theme.accent
    }
}
