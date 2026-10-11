import QtQuick
import "../theme"

Column {
    id: f
    property string label
    property alias text: input.text
    property string placeholder
    signal edited(string text)
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
            Text { visible: !parent.text; text: f.placeholder; color: Theme.muted; font: parent.font }
        }
    }
}
