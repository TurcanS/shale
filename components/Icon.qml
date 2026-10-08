import QtQuick

Item {
    id: root
    property string name: "grid"
    property int size: 18
    property bool invert: false
    width: size
    height: size
    implicitWidth: size
    implicitHeight: size
    Image {
        anchors.fill: parent
        sourceSize.width: root.size * 2
        sourceSize.height: root.size * 2
        source: root.name ? Qt.resolvedUrl("../assets/icons/" + root.name + (root.invert ? "-dark" : "") + ".svg") : ""
        fillMode: Image.PreserveAspectFit
        smooth: true
    }
}
