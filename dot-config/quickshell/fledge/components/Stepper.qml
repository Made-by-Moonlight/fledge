import QtQuick
import "../theme"

Column {
    id: s
    property string label
    property real value
    property real from: 0
    property real to: 100
    property real step: 1
    property int decimals: 0
    property string suffix: ""
    // When set, − and + move to the next of these (ascending) instead of by step.
    property var values: []
    signal changed(real value)
    function nudge(d) {
        if (s.values.length) {
            const next = d > 0 ? s.values.find(v => v > s.value + 1e-9) : s.values.slice().reverse().find(v => v < s.value - 1e-9);
            if (next !== undefined) s.changed(next);
            return;
        }
        s.changed(Math.max(s.from, Math.min(s.to, +(s.value + d).toFixed(s.decimals))));
    }
    spacing: 4
    Glyph { text: s.label; color: Theme.muted; font.pixelSize: Theme.fontSmall; visible: s.label !== "" }
    Row {
        spacing: 6
        Button { text: "−"; width: 30; onClicked: s.nudge(-s.step) }
        Rectangle { width: 90; height: 30; radius: 7; color: Theme.bgRaised
            Glyph { anchors.centerIn: parent; text: s.value.toFixed(s.decimals) + s.suffix } }
        Button { text: "+"; width: 30; onClicked: s.nudge(s.step) }
    }
}
