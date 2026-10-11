import QtQuick
import "../theme"

Item {
    id: s
    property real value: 0
    signal moved(real v)
    implicitHeight: 18
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: 6; radius: 3; color: Theme.surface
        Rectangle { width: parent.width * Math.max(0, Math.min(1, s.value)); height: parent.height; radius: 3; color: Theme.accent }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        function at(x) { s.moved(Math.max(0, Math.min(1, x / width))); }
        onPressed: m => at(m.x)
        onPositionChanged: m => { if (pressed) at(m.x); }
        onWheel: w => s.moved(Math.max(0, Math.min(1, s.value + (w.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
