import QtQuick
import "../theme"

Rectangle {
    id: t
    property string glyph
    property string title
    property string sub
    property bool on: false
    property bool expandable: false
    signal clicked()
    signal expand()
    height: 48; radius: 9
    color: on ? Theme.accent : Theme.surface
    Row {
        anchors.fill: parent; anchors.leftMargin: 10; spacing: 8
        Glyph { id: icon; text: t.glyph; color: t.on ? Theme.bg : Theme.fg; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: Theme.fontLarge }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: t.width - 10 - 8 - icon.width - (t.expandable ? 28 : 10)
            Glyph { text: t.title; color: t.on ? Theme.bg : Theme.fg; font.bold: true; elide: Text.ElideRight; width: parent.width }
            Glyph { text: t.sub; color: t.on ? Theme.bg : Theme.muted; font.pixelSize: Theme.fontSmall; elide: Text.ElideRight; width: parent.width; opacity: 0.8 }
        }
    }
    MouseArea { anchors.fill: parent; onClicked: t.clicked() }
    Glyph {
        visible: t.expandable; text: "›"; color: t.on ? Theme.bg : Theme.muted; font.pixelSize: Theme.fontLarge
        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: t.expand() }
    }
}
