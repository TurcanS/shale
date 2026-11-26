import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../core"
import "../services"
import "../components" as C

// What came in during a focus session, grouped by app. Stays until dismissed.
PanelWindow {
    id: digestWindow
    // Whether this window's screen is the one toasts show on now.
    property bool target: false
    readonly property var digest: Focus.digest
    property var retained: null
    onDigestChanged: if (digest)
        retained = digest
    readonly property var groups: retained ? retained.groups : []
    property real reveal: digestWindow.target && !!digest && !ShellState.locked ? 1 : 0
    Behavior on reveal { NumberAnimation { duration: digestWindow.digest ? Theme.enter : Theme.leave; easing.type: Easing.OutCubic } }
    anchors {
        top: true
    }
    margins.top: ShellState.barBottomOn(digestWindow.screen ? digestWindow.screen.name : "") + 9
    implicitWidth: Math.min(380, screen.width - 24)
    implicitHeight: digestColumn.implicitHeight + 2 * Theme.gapM
    visible: reveal > 0
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shale-digest"
    WlrLayershell.layer: WlrLayer.Overlay
    Rectangle {
        anchors.fill: parent
        radius: 18
        color: Theme.module
        border.width: 1
        border.color: Theme.cardEdge
        opacity: digestWindow.reveal
        transform: Translate { y: Theme.reduced ? 0 : (1 - digestWindow.reveal) * -8 }
        ColumnLayout {
            id: digestColumn
            anchors.fill: parent
            anchors.margins: Theme.gapM
            spacing: Theme.gapS
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapM
                C.GlyphTile { glyph: "focus" }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    C.Label {
                        text: digestWindow.retained ? "While you focused · " + digestWindow.retained.minutes + " min" : ""
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    C.Caption {
                        readonly property int total: digestWindow.retained ? digestWindow.retained.total : 0
                        text: total + (total === 1 ? " notification" : " notifications") + " from " + digestWindow.groups.length + (digestWindow.groups.length === 1 ? " app" : " apps")
                        Layout.fillWidth: true
                    }
                }
                C.Button {
                    glyph: "close"
                    flat: true
                    hint: "Dismiss"
                    onClicked: Focus.digest = null
                }
            }
            Repeater {
                model: digestWindow.groups.slice(0, 4)
                RowLayout {
                    id: digestRow
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.leftMargin: 2
                    spacing: Theme.gapM
                    Item {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        Image {
                            id: digestIcon
                            anchors.centerIn: parent
                            visible: status === Image.Ready
                            source: digestRow.modelData.appIcon ? Quickshell.iconPath(digestRow.modelData.appIcon, "dialog-information") : ""
                            sourceSize.width: 24
                            sourceSize.height: 24
                            width: 24
                            height: 24
                        }
                        C.Icon {
                            anchors.centerIn: parent
                            visible: !digestIcon.visible
                            name: "bell"
                            size: 16
                            color: Theme.textMuted
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        C.Label {
                            text: digestRow.modelData.appName
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        C.Caption {
                            text: digestRow.modelData.latest
                            visible: text !== ""
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            Layout.fillWidth: true
                        }
                    }
                    C.Label {
                        text: String(digestRow.modelData.count)
                        font.family: Theme.mono
                        font.pixelSize: Theme.small
                        color: Theme.textMuted
                    }
                }
            }
            C.Caption {
                visible: digestWindow.groups.length > 4
                text: "and " + (digestWindow.groups.length - 4) + " more"
                Layout.leftMargin: 42
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.gapXs
                spacing: Theme.gapS
                Item { Layout.fillWidth: true }
                C.Button {
                    text: "Dismiss"
                    flat: true
                    onClicked: Focus.digest = null
                }
                C.Button {
                    text: "Open notifications"
                    onClicked: {
                        Focus.digest = null;
                        ShellState.open("notifications", digestWindow.screen.name);
                    }
                }
            }
        }
    }
}
