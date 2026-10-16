import QtQuick
import "../theme"
import "../components"

// A labelled line of text. `error` shows under it; `secret` hides what's typed
// (eye icon to show it). Return emits accepted() and stops there, so a step
// decides whether Return moves to the next field or the next step.
Column {
    id: f
    property string label
    property alias text: input.text
    property string placeholder
    property string error
    property bool secret: false
    property bool shown: false
    signal accepted()
    spacing: 4
    width: 420
    function focusInput() { input.forceActiveFocus(); }
    Glyph { text: f.label; color: Theme.muted; font.pixelSize: Theme.fontSmall; visible: f.label !== "" }
    Rectangle {
        width: f.width; height: 38; radius: 7; color: Theme.bgRaised
        border.color: f.error !== "" ? Theme.error : input.activeFocus ? Theme.accent : Theme.surface
        TextInput {
            id: input
            anchors { fill: parent; margins: 10; rightMargin: f.secret ? 40 : 10 }
            clip: true
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.fg; font.family: Theme.font; font.pixelSize: Theme.fontSize
            echoMode: f.secret && !f.shown ? TextInput.Password : TextInput.Normal
            // Repeats of a held Return are swallowed: accepted() can mean next().
            Keys.onReturnPressed: ev => { ev.accepted = true; if (!ev.isAutoRepeat) f.accepted(); }
            Keys.onEnterPressed: ev => { ev.accepted = true; if (!ev.isAutoRepeat) f.accepted(); }
            Text { visible: !parent.text; text: f.placeholder; textFormat: Text.PlainText; color: Theme.muted; font: parent.font; anchors.verticalCenter: parent.verticalCenter }
        }
        Glyph {
            visible: f.secret
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            text: f.shown ? "󰈉" : "󰈈"; color: Theme.muted
            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: f.shown = !f.shown }
        }
    }
    Glyph { text: f.error; color: Theme.error; font.pixelSize: Theme.fontSmall; visible: f.error !== "" }
}
