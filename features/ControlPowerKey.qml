import QtQuick
import "../core"
import "../components" as C

// A 44 px key in the power row.
C.Button {
    id: powerKey
    implicitHeight: 44
    labelSize: 13
    cornerRadius: Theme.radiusCard
    background: Rectangle {
        radius: powerKey.cornerRadius
        color: powerKey.selected ? Theme.raised : powerKey.hovered || powerKey.down || powerKey.visualFocus ? Theme.mix(Theme.module, Theme.text, 0.05) : Theme.module
        Behavior on color {
            ColorAnimation {
                duration: Theme.fast
            }
        }
        C.Raise {
            shown: powerKey.selected
        }
    }
}
