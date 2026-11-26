import QtQuick
import QtQuick.Layouts
import "../core"

Button {
    id: root
    // Optional second line explaining what the switch does or its current state.
    property string description: ""
    // With a glyph the row becomes a header-style toggle (Wi-Fi, Bluetooth); positive adds a status dot.
    property bool positive: false
    // The setting this switch changes, for the reset key beside its name while it differs from how Shale comes.
    property string settingKey: ""
    // Flat inside a Group: no card of its own, only a hover highlight.
    implicitHeight: Math.max(glyph !== "" ? 60 : description !== "" ? 58 : Theme.controlLarge + 4, toggleContent.implicitHeight + topPadding + bottomPadding)
    padding: Theme.gapL
    leftPadding: glyph !== "" ? Theme.gapM : Theme.gapL
    topPadding: Theme.gapS + 2
    bottomPadding: Theme.gapS + 2
    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: selected
    Accessible.description: description
    // A whole row only gives a little under the pointer.
    scale: down && !Theme.reduced ? Theme.rowPressScale : 1
    pressDepth: 0
    background: Rectangle {
        radius: root.flat ? Theme.radiusCard + 2 : Theme.radiusCard
        color: root.flat ? (root.hovered || root.visualFocus || root.down ? Theme.rowWash(root.down) : "transparent")
             : root.hovered || root.visualFocus || root.down ? Theme.mix(Theme.module, Theme.text, 0.05) : Theme.module
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }
    contentItem: RowLayout {
        // Named: contentItem is created late, and a binding through it doesn't see later size changes.
        id: toggleContent
        spacing: Theme.gapL
        GlyphTile {
            visible: root.glyph !== ""
            size: 36
            glyph: root.glyph
            positive: root.positive
            selected: root.selected
            opacity: root.enabled ? 1 : Theme.disabledOpacity
            Layout.rightMargin: -Theme.gapXs
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            // The name wraps when the line is too short; the reset key sits right after it while the setting is changed.
            Item {
                Layout.fillWidth: true
                implicitHeight: name.implicitHeight
                Label {
                    id: name
                    width: Math.min(implicitWidth, parent.width - (rowReset.visible ? rowReset.width + Theme.gapXs : 0))
                    text: root.text
                    wrapMode: Text.WordWrap
                    font.weight: root.glyph !== "" ? Font.DemiBold : Font.Normal
                    color: root.enabled ? Theme.text : Theme.textFaint
                }
                RowReset {
                    id: rowReset
                    x: name.width + Theme.gapXs
                    y: Math.round((Math.min(name.implicitHeight, name.font.pixelSize * 1.4) - height) / 2)
                    key: root.settingKey
                    name: root.text
                }
            }
            Label {
                visible: root.description !== ""
                text: root.description
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                // Header rows (with a glyph) keep status to one line; setting explanations may wrap.
                maximumLineCount: root.glyph !== "" ? 1 : 3
                elide: Text.ElideRight
                color: Theme.textDim
                font.pixelSize: Theme.small
            }
        }
        SwitchTrack {
            on: root.selected
            hot: root.hovered || root.visualFocus || root.down
            opacity: root.enabled ? 1 : Theme.disabledOpacity
            Layout.preferredWidth: 40
            Layout.preferredHeight: 22
        }
    }
}
