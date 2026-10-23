import QtQuick
import QtQuick.Layouts
import "../theme"
import "../components"

// Focused and unfocused opacity sliders (Settings › Apps). `save` fires 400 ms after the last
// move, not per pixel: each save is an apply and a Hyprland reload, which is what puts the new
// value on the open windows. Until then the sliders show what's being dragged.
ColumnLayout {
    id: ed
    property string title
    property var value: ({ active: 1, inactive: 1 })
    signal save(var v)
    property var pending: null
    readonly property var shown: pending ?? value
    spacing: 6

    function move(k, v) {
        const n = Object.assign({}, shown);
        n[k] = Math.max(0.1, Math.min(1, Math.round(v * 100) / 100));
        pending = n;
        debounce.restart();
    }
    Timer { id: debounce; interval: 400; onTriggered: { if (ed.pending) ed.save(ed.pending); ed.pending = null; } }

    Glyph { text: ed.title; visible: ed.title !== ""; font.bold: true }
    Repeater {
        model: [["active", "Focused"], ["inactive", "Unfocused"]]
        delegate: RowLayout {
            id: line
            required property var modelData
            Layout.fillWidth: true; spacing: 10
            Glyph { text: line.modelData[1]; color: Theme.fgDim; Layout.preferredWidth: 80 }
            Slider {
                objectName: "opacity " + line.modelData[0]
                Layout.fillWidth: true; value: ed.shown[line.modelData[0]]
                onMoved: v => ed.move(line.modelData[0], v)
                onStepped: d => ed.move(line.modelData[0], ed.shown[line.modelData[0]] + d * 0.05)
            }
            Glyph { text: Math.round(ed.shown[line.modelData[0]] * 100) + "%"; color: Theme.muted
                    Layout.preferredWidth: 40; horizontalAlignment: Text.AlignRight }
        }
    }
}
