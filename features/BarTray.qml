import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

RowLayout {
    id: tray
    // The bar this item is on: its screen, layout, weather and helpers.
    required property var bar
    // How many apps get their own icon; the rest open from the tray page. Narrow bars show none.
    readonly property int count: {
        const chosen = ShellState.setting("trayIcons", -1);
        return bar.width <= 1100 ? 0 : chosen >= 0 ? chosen : bar.width > 1700 ? 3 : 2;
    }
    readonly property bool shown: Services.trayItems.length > 0
    spacing: 2
    Repeater {
        model: Services.trayItems.slice(0, tray.count)
        BarKey {
            id: trayButton
            required property var modelData
            implicitWidth: 28
            hint: modelData.tooltipTitle || modelData.title || modelData.id
            tooltip: bar.tooltip
            contentItem: Item {
                Image {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    source: trayButton.modelData.icon
                    sourceSize.width: 32
                    sourceSize.height: 32
                    fillMode: Image.PreserveAspectFit
                }
            }
            selected: !!bar.trayMenu && bar.trayMenu.shown && bar.trayMenu.item === modelData
            onClicked: modelData.onlyMenu ? bar.trayMenu.toggle(modelData, bar.window, trayButton) : modelData.activate()
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: {
                    bar.tooltip.hide(trayButton, true);
                    bar.trayMenu.toggle(trayButton.modelData, bar.window, trayButton);
                }
            }
            TapHandler {
                acceptedButtons: Qt.MiddleButton
                onTapped: {
                    bar.tooltip.hide(trayButton, true);
                    trayButton.modelData.secondaryActivate();
                }
            }
            // Apps such as volume mixers act on scrolling; deltas are Qt's, as Plasma sends them.
            WheelHandler {
                onWheel: event => {
                    if (event.angleDelta.y !== 0)
                        trayButton.modelData.scroll(event.angleDelta.y, false);
                    if (event.angleDelta.x !== 0)
                        trayButton.modelData.scroll(event.angleDelta.x, true);
                }
            }
        }
    }
    BarKey {
        visible: Services.trayItems.length > tray.count
        implicitWidth: 28
        glyph: "tray"
        hint: "System tray"
        tooltip: bar.tooltip
        selected: bar.controlActive("tray")
        onClicked: bar.toggleControl("tray")
    }
}
