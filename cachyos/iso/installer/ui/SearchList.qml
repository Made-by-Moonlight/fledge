import QtQuick
import "../theme"
import "../components"

// A filter box over a long list (layouts, variants, timezones).
// Return picks the first match when the current value isn't among the matches,
// then emits accepted(). Up/Down move the selection.
Column {
    id: s
    property var items: []                 // [{ value, label }]
    property string value
    property string placeholder: "Type to search"
    property int listHeight: 360
    signal picked(string value)
    signal accepted()
    spacing: 8
    width: 520
    readonly property var matches: {
        const q = search.text.toLowerCase();
        return q === "" ? s.items : s.items.filter(i => i.value.toLowerCase().includes(q) || i.label.toLowerCase().includes(q));
    }
    function focusInput() { search.focusInput(); }
    function move(d) {
        const i = s.matches.findIndex(m => m.value === s.value);
        const j = Math.max(0, Math.min(s.matches.length - 1, i + d));
        if (s.matches[j]) { s.picked(s.matches[j].value); list.positionViewAtIndex(j, ListView.Contain); }
    }
    Input {
        id: search; width: s.width; placeholder: s.placeholder
        onAccepted: {
            if (s.matches.length > 0 && !s.matches.some(m => m.value === s.value)) s.picked(s.matches[0].value);
            s.accepted();
        }
        Keys.onUpPressed: s.move(-1)
        Keys.onDownPressed: s.move(1)
    }
    Rectangle {
        width: s.width; height: s.listHeight; radius: Theme.radius; color: Theme.bgRaised; clip: true
        ListView {
            id: list
            anchors { fill: parent; margins: 6 }
            model: s.matches
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                required property var modelData
                readonly property bool sel: modelData.value === s.value
                width: list.width; height: 30; radius: 6
                color: sel ? Theme.accentSoft : ma.containsMouse ? Theme.surface : "transparent"
                Glyph {
                    anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    text: parent.modelData.label; elide: Text.ElideRight
                    color: parent.sel ? Theme.accent : Theme.fg
                }
                MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: s.picked(parent.modelData.value) }
            }
            // Show the current value. Deferred: at onCompleted the view has no size yet, and
            // the items (xkb rules, timezones) can arrive after the page opens.
            function reveal() { const i = s.matches.findIndex(m => m.value === s.value); if (i >= 0) positionViewAtIndex(i, ListView.Center); }
            Component.onCompleted: Qt.callLater(reveal)
            onCountChanged: Qt.callLater(reveal)
        }
    }
}
