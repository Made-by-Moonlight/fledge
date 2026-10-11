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
    signal changed(real value)
    function nudge(d) { s.changed(Math.max(s.from, Math.min(s.to, +(s.value + d).toFixed(s.decimals)))); }
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
