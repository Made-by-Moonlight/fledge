import QtQuick
import "../theme"

Rectangle {
    id: b
    property string text
    property bool primary: false
    property bool enabled: true
    signal clicked()
    height: 30; width: label.implicitWidth + 24; radius: 7
    color: primary ? Theme.accent : Theme.surface
    opacity: enabled ? 1 : 0.5
    // Named by its text so a test can ask what has the focus. `enabled` above shadows
    // Item's, so a disabled button is taken out of the Tab order by hand.
    objectName: text
    activeFocusOnTab: enabled
    FocusRing { shown: b.activeFocus; onAccent: b.primary }
    // Accepted, so a scope above (the installer's Return = next step) doesn't also act.
    Keys.onPressed: ev => {
        if (!b.enabled || ![Qt.Key_Space, Qt.Key_Return, Qt.Key_Enter].includes(ev.key)) return;
        ev.accepted = true;
        if (!ev.isAutoRepeat) b.clicked();
    }
    Glyph { id: label; anchors.centerIn: parent; text: b.text; color: b.primary ? Theme.bg : Theme.fg; font.bold: b.primary }
    MouseArea { anchors.fill: parent; enabled: b.enabled; onClicked: b.clicked() }
}
