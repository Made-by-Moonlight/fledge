import QtQuick
import "../theme"

Column {
    id: c
    property string label
    property var options: []      // [[value, label], ...]
    property var value
    signal picked(var value)
    spacing: 4
    Glyph { text: c.label; color: Theme.muted; font.pixelSize: Theme.fontSmall; visible: c.label !== "" }
    Rectangle {
        height: 30; width: row.implicitWidth + 4; radius: 8; color: Theme.surface
        Row {
            id: row; anchors.centerIn: parent
            Repeater {
                model: c.options
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool on: c.value === modelData[0]
                    height: 26; width: t.implicitWidth + 20; radius: 6
                    color: on ? Theme.bg : "transparent"
                    Glyph { id: t; anchors.centerIn: parent; text: parent.modelData[1]; font.pixelSize: Theme.fontSmall; color: parent.on ? Theme.accent : Theme.fgDim }
                    MouseArea { anchors.fill: parent; onClicked: c.picked(parent.modelData[0]) }
                }
            }
        }
    }
}
