import QtQuick
import QtTest
import Quickshell
import "components" as C
import "core"

ShellRoot {
    id: root
    property int activations: 0
    property int failures: 0
    function check(condition, message) {
        if (!condition) failures++;
        console.log(condition ? "HOLD PASS:" : "HOLD FAIL:", message);
    }
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 480
        implicitHeight: 180
        C.HoldButton {
            id: button
            anchors.centerIn: parent
            width: 360
            text: "Test action"
            onConfirmed: root.activations++
        }
        Item { id: other; focus: true }
        TestCase { id: input; when: false }
        Timer {
            interval: 400
            running: true
            onTriggered: {
                input.mouseClick(button, 100, 30);
                input.wait(1500);
                root.check(root.activations === 0, "A click never activates");
                input.mousePress(button, 100, 30);
                input.wait(300);
                root.check(button.progress > 0, "Holding displays progress");
                input.mouseRelease(button, 100, 30);
                input.wait(1500);
                root.check(root.activations === 0 && button.progress === 0, "Early release cancels fully");
                button.forceActiveFocus();
                input.keyPress(Qt.Key_Space);
                input.wait(1500);
                input.keyRelease(Qt.Key_Space);
                root.check(root.activations === 1, "Holding Space activates once");
                button.triggered = false;
                input.mousePress(button, 100, 30);
                input.wait(300);
                input.keyClick(Qt.Key_Escape);
                input.wait(1500);
                input.mouseRelease(button, 100, 30);
                root.check(root.activations === 1, "Escape cancels a pending hold");
                input.mousePress(button, 100, 30);
                input.wait(300);
                button.armed = false;
                input.wait(1500);
                input.mouseRelease(button, 100, 30);
                root.check(root.activations === 1, "Disarming cancels a pending hold");
                button.armed = true;
                input.mousePress(button, 100, 30);
                input.wait(300);
                other.forceActiveFocus();
                input.wait(1500);
                input.mouseRelease(button, 100, 30);
                root.check(root.activations === 1, "Focus loss cancels a pending hold");
                input.mousePress(button, 100, 30);
                input.wait(300);
                button.visible = false;
                input.wait(1500);
                input.mouseRelease(button, 100, 30);
                root.check(root.activations === 1, "Hiding a control cancels its hold");
                button.visible = true;
                ShellState.settings = Object.assign({}, ShellState.settings, {reducedMotion: true});
                root.check(button.delay === 1400, "Reduced motion preserves the full safety delay");
                input.mousePress(button, 100, 30);
                input.wait(300);
                root.check(root.activations === 1, "Reduced-motion hold cannot activate early");
                input.wait(1200);
                input.mouseRelease(button, 100, 30);
                input.wait(200);
                root.check(root.activations === 2, "A full mouse hold activates exactly once");
                console.log("HOLD CHECK COMPLETE", root.failures);
                Qt.quit();
            }
        }
    }
}
