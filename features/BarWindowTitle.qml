import QtQuick
import QtQuick.Layouts
import Quickshell
import "../core"
import "../services"
import "../components" as C

BarKey {
    id: titleKey
    // The bar this item is on: its screen, layout, weather and helpers.
    required property var bar
    readonly property var window: Services.activeWindow
    readonly property string appId: window ? (window.wayland ? window.wayland.appId || "" : (window.lastIpcObject || {}).class || "") : ""
    readonly property var entry: appId && DesktopEntries.heuristicLookup ? DesktopEntries.heuristicLookup(appId) : null
    readonly property string app: {
        const name = entry && entry.name ? entry.name : appId.split(".").pop();
        return name.charAt(0).toUpperCase() + name.slice(1);
    }
    readonly property string title: window ? window.title || "" : ""
    shown: bar.width > 1400
    leftPadding: 8
    rightPadding: 8
    // Leaves room for the clock in the middle.
    implicitWidth: Math.min(Math.max(120, Math.min(340, bar.width / 2 - 460)), implicitContentWidth + leftPadding + rightPadding)
    hint: title || "Pages"
    onClicked: ShellState.toggle("overview", bar.outputName)
    contentItem: RowLayout {
        spacing: Theme.gapS
        Rectangle {
            visible: titleKey.app !== ""
            Layout.preferredWidth: 18
            Layout.preferredHeight: 18
            radius: 5
            color: Theme.key
            C.Label {
                anchors.centerIn: parent
                text: titleKey.app.charAt(0).toUpperCase()
                color: Theme.textSecondary
                font.pixelSize: 10
                font.weight: Font.Bold
                elide: Text.ElideNone
            }
        }
        C.Label {
            visible: titleKey.app !== ""
            text: titleKey.app
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.maximumWidth: 140
        }
        // Runs on from the app name like one line of text.
        C.Label {
            visible: text !== ""
            text: titleKey.app === "" ? (titleKey.title || "Shale") : titleKey.title && titleKey.title !== titleKey.app ? " · " + titleKey.title : ""
            color: Theme.textDim
            font.pixelSize: 12
            Layout.fillWidth: true
            Layout.leftMargin: titleKey.app === "" ? 0 : -Theme.gapS
        }
    }
}
