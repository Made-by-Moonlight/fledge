import QtQuick
import "../theme"

// Dragging shows the pointer's value at once (the live value lags the daemon) and emits `moved`
// at most every 50 ms plus a final value on release. The wheel emits `stepped(dir)` so callers use
// their accumulating step paths instead of writing absolute values from a stale reading.
Item {
    id: s
    property real value: 0
    signal moved(real v)
    signal stepped(int dir)
    property real dragValue: 0
    property bool dirty: false
    // Stay on the dragged value briefly after release, until the live value has caught up.
    property bool holding: false
    readonly property real fill: (ma.pressed || holding) ? dragValue : value
    implicitHeight: 18

    function flush() { if (dirty) { dirty = false; moved(dragValue); } }

    Timer { id: throttle; interval: 50; repeat: true; onTriggered: { if (s.dirty) s.flush(); else stop(); } }
    Timer { id: hold; interval: 600; onTriggered: s.holding = false }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: 6; radius: 3; color: Theme.surface
        Rectangle { width: parent.width * Math.max(0, Math.min(1, s.fill)); height: parent.height; radius: 3; color: Theme.accent }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        function at(x) {
            s.dragValue = Math.max(0, Math.min(1, x / width));
            s.dirty = true;
            if (!throttle.running) { s.flush(); throttle.start(); }
        }
        onPressed: m => { hold.stop(); s.holding = false; at(m.x); }
        onPositionChanged: m => { if (pressed) at(m.x); }
        onReleased: { s.flush(); throttle.stop(); s.holding = true; hold.restart(); }
        onCanceled: { s.flush(); throttle.stop(); s.holding = true; hold.restart(); }
        onWheel: w => s.stepped(w.angleDelta.y > 0 ? 1 : -1)
    }
}
