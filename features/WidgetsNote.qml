import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../core"
import "../services"
import "../components" as C

// The Note card: one running note, a line each, ticked off with its circle and removed with ×. The desktop never
// takes the keyboard, so the add field opens Find with "note " typed; Enter there adds the line here.
WidgetsCard {
    id: root
    padding: 16
    ColumnLayout {
        anchors.fill: parent
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gapS
            C.Label {
                text: "Note"
                font.pixelSize: 15
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }
            C.Label {
                visible: Note.lines.length > 0
                text: Note.remaining === 0 ? "All done" : Note.remaining + (Note.remaining === 1 ? " item" : " items")
                color: Theme.textDim
                font.pixelSize: 12
                font.features: ({"tnum": 1})
            }
        }
        ListView {
            id: lines
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: Note.lines
            // The newest lines are the ones in view.
            onCountChanged: Qt.callLater(positionViewAtEnd)
            Component.onCompleted: positionViewAtEnd()
            C.Label {
                visible: lines.count === 0
                text: Note.loaded ? "Nothing on the note yet." : ""
                color: Theme.textDim
                font.pixelSize: 13
                width: lines.width
            }
            delegate: Item {
                id: line
                required property var modelData
                required property int index
                width: lines.width
                implicitHeight: Math.max(20, lineText.implicitHeight)
                HoverHandler {
                    id: hover
                }
                // The circle ticks the line off, or back on.
                AbstractButton {
                    id: check
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 20
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    Accessible.role: Accessible.CheckBox
                    Accessible.checkable: true
                    Accessible.checked: line.modelData.done
                    Accessible.name: line.modelData.text
                    onClicked: Note.toggle(line.index)
                    contentItem: Item {}
                    background: Rectangle {
                        anchors.centerIn: parent
                        width: 14
                        height: 14
                        radius: 7
                        color: line.modelData.done ? Theme.accent : check.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        border.width: line.modelData.done ? 0 : 1.5
                        border.color: check.hovered ? Theme.textDim : Theme.textFaint
                        C.Icon {
                            anchors.centerIn: parent
                            visible: line.modelData.done
                            name: "check"
                            size: 10
                            color: Theme.accentInk
                        }
                    }
                }
                C.Label {
                    id: lineText
                    anchors.left: check.right
                    anchors.leftMargin: 4
                    anchors.right: remove.visible ? remove.left : parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: line.modelData.text
                    color: line.modelData.done ? Theme.textFaint : Theme.text
                    font.pixelSize: 14
                    font.strikeout: line.modelData.done
                }
                C.Button {
                    id: remove
                    visible: hover.hovered
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "close"
                    flat: true
                    hint: "Remove " + line.modelData.text
                    focusPolicy: Qt.NoFocus
                    implicitWidth: 20
                    implicitHeight: 20
                    padding: 3
                    cornerRadius: 6
                    onClicked: Note.remove(line.index)
                }
            }
        }
        // Looks like a field; Find does the typing.
        AbstractButton {
            id: add
            Layout.fillWidth: true
            implicitHeight: 32
            hoverEnabled: true
            focusPolicy: Qt.NoFocus
            Accessible.name: "Add to the note"
            onClicked: {
                ShellState.open("launcher", root.outputName);
                ShellState.detail = "note ";
            }
            background: Rectangle {
                radius: Theme.radiusKey
                color: Qt.rgba(1, 1, 1, add.hovered ? 0.09 : 0.06)
                Behavior on color {
                    ColorAnimation {
                        duration: Theme.fast
                    }
                }
            }
            contentItem: C.Label {
                leftPadding: 10
                rightPadding: 10
                text: "Add a line, then Enter"
                color: Theme.textFaint
                font.pixelSize: 13
            }
        }
    }
}
