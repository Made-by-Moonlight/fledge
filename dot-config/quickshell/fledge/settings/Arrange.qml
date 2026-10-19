import QtQuick
import "../theme"
import "../components"
import "Layout.js" as Layout

// The arrangement canvas on Settings › Displays: every enabled monitor at its physical size
// (Layout.js), click to select, drag to move (snapping, never overlapping, settling against a
// neighbour on release), rotate the selected one. It only draws and reports: the page owns the
// rects and stages what comes back.
Column {
    id: arr
    property var mons: []          // Layout monitors, plus name (connector) and title (model)
    property var rects: []         // mm, in and out
    property string selected: ""
    signal moved(var rects)
    signal picked(string key)
    signal rotated(string key, int dir)
    spacing: 10

    readonly property var current: mons.find(m => m.key === selected) ?? null

    Rectangle {
        id: canvas
        width: arr.width; height: 280; radius: Theme.radius; color: Theme.bgRaised; clip: true
        // Frozen while dragging: refitting as the extent changes would move the canvas under the cursor.
        property var frozen: null
        readonly property var view: frozen ?? Layout.fit(arr.rects, width, height, 24)

        Repeater {
            // Keyed by monitor, not by rect: a drag rewrites rects, and a delegate rebuilt mid-drag
            // would lose the mouse grab.
            model: arr.mons
            delegate: Rectangle {
                id: box
                required property var modelData
                readonly property var r: arr.rects.find(q => q.key === modelData.key) ?? null
                readonly property bool on: arr.selected === modelData.key
                // Overlapping or touching nothing: the reason Apply is off, shown where it is.
                readonly property bool bad: r !== null && arr.rects.length > 1
                    && (arr.rects.some(o => o.key !== r.key && Layout.overlaps(r, o))
                        || !arr.rects.some(o => o.key !== r.key && Layout.touching(r, o)))
                readonly property var lg: Layout.logical(modelData)
                visible: r !== null
                x: r ? canvas.view.ox + r.x * canvas.view.scale : 0
                y: r ? canvas.view.oy + r.y * canvas.view.scale : 0
                width: r ? r.w * canvas.view.scale : 0
                height: r ? r.h * canvas.view.scale : 0
                radius: 6; clip: true
                color: on ? Qt.tint(Theme.surface, Theme.accentSoft) : Theme.surface
                border.width: 2; border.color: bad ? Theme.error : on ? Theme.accent : Qt.lighter(Theme.surface, 1.3)

                Column {
                    anchors.centerIn: parent; width: parent.width - 10; spacing: 2
                    Glyph { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                            text: box.modelData.name; font.bold: true; color: box.on ? Theme.accent : Theme.fg }
                    Glyph { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                            text: box.modelData.title; font.pixelSize: Theme.fontSmall; color: Theme.fgDim; visible: text !== "" }
                    Glyph { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                            font.pixelSize: Theme.fontSmall; color: Theme.muted
                            text: box.lg[0] + "×" + box.lg[1] + " · " + (box.modelData.transform & 3) * 90 + "°" + (box.modelData.transform & 4 ? " flipped" : "") }
                    Glyph { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                            visible: !Layout.trusted(box.modelData); text: "size unknown"; font.pixelSize: 10; font.italic: true; color: Theme.muted }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    property point press
                    property var start: null
                    property bool dragging: false
                    onPressed: mouse => {
                        arr.picked(box.modelData.key);
                        press = mapToItem(canvas, mouse.x, mouse.y);
                        start = box.r ? { x: box.r.x, y: box.r.y } : null;
                        dragging = false;
                        canvas.frozen = canvas.view;
                    }
                    onPositionChanged: mouse => {
                        if (!start) return;
                        const p = mapToItem(canvas, mouse.x, mouse.y);
                        if (!dragging && Math.hypot(p.x - press.x, p.y - press.y) < 4) return;
                        dragging = true;
                        const s = canvas.view.scale || 1;
                        arr.moved(Layout.drag(arr.rects, box.modelData.key, start.x + (p.x - press.x) / s, start.y + (p.y - press.y) / s, 12));
                    }
                    // Dropped clear of everything, it slides back to touch the nearest monitor.
                    function done() {
                        if (dragging) arr.moved(Layout.settle(arr.rects, box.modelData.key));
                        dragging = false; start = null; canvas.frozen = null;
                    }
                    onReleased: done()
                    onCanceled: done()
                }
            }
        }
        Glyph { anchors.centerIn: parent; visible: arr.rects.length === 0; color: Theme.muted; text: "No monitor is switched on" }
    }

    Row {
        spacing: 8
        Glyph { width: 220; height: 30; elide: Text.ElideRight; font.bold: true
                text: arr.current ? arr.current.name + (arr.current.title ? "  " + arr.current.title : "") : "Click a monitor to select it" }
        // Hyprland's transforms are Wayland's: 90 is a quarter-turn anticlockwise, so left is +1.
        Button { text: "⟲ Rotate left"; enabled: arr.current !== null; onClicked: arr.rotated(arr.selected, 1) }
        Button { text: "⟳ Rotate right"; enabled: arr.current !== null; onClicked: arr.rotated(arr.selected, -1) }
    }
}
