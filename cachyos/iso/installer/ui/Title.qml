import QtQuick
import "../theme"
import "../components"

Column {
    property string text
    property string sub
    spacing: 6
    Glyph { text: parent.text; font.pixelSize: 24; font.bold: true }
    Glyph { text: parent.sub; color: Theme.muted; visible: parent.sub !== ""; width: 640; wrapMode: Text.WordWrap }
}
