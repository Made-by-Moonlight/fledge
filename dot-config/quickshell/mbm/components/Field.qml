import QtQuick
import "../theme"

// Two signals on purpose. `edited(text)` fires on every keystroke: use it for live things
// (filters, enabling a button). `committed(text)` fires on Return or focus loss: use it for
// anything that writes settings, since each write runs an apply and a Hyprland reload.
Column {
    id: f
    property string label
    property alias text: input.text
    property string placeholder
    signal edited(string text)
    signal committed(string text)
    spacing: 4
    Glyph { text: f.label; color: Theme.muted; font.pixelSize: Theme.fontSmall; visible: f.label !== "" }
    Rectangle {
        width: f.width; height: 34; radius: 7; color: Theme.bgRaised
        border.color: input.activeFocus ? Theme.accent : Theme.surface
        TextInput {
            id: input
            anchors.fill: parent; anchors.margins: 8; clip: true
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.fg; font.family: Theme.font; font.pixelSize: Theme.fontSize
            onTextEdited: f.edited(text)
            onEditingFinished: f.committed(text)
            Text { visible: !parent.text; text: f.placeholder; textFormat: Text.PlainText; color: Theme.muted; font: parent.font }
        }
    }
}
