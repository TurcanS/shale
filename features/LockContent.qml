pragma ComponentBehavior: Bound
import QtQuick
import "../core"

// What one output shows while locked, in the chosen style. `context` is the shared LockScreen (or a preview
// stand-in). Only counts are shown for notifications; their contents stay private.
Item {
    id: root
    required property var context
    property string screenName: ""
    Loader {
        anchors.fill: parent
        focus: true
        sourceComponent: ({classic: classic, station: station})[ShellState.setting("lockStyle", "particles")] || particles
    }
    Component {
        id: station
        LockStation {
            context: root.context
            screenName: root.screenName
        }
    }
    Component {
        id: particles
        LockParticles {
            context: root.context
            screenName: root.screenName
        }
    }
    Component {
        id: classic
        LockClassic {
            context: root.context
            screenName: root.screenName
        }
    }
}
