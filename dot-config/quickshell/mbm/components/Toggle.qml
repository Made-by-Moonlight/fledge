import QtQuick
import "../theme"

Row {
    id: t
    property bool checked
    property string label
    signal toggled(bool checked)
    spacing: 10
    Rectangle {
        width: 38; height: 20; radius: 10; color: t.checked ? Theme.accent : Theme.surface
        Rectangle { width: 16; height: 16; radius: 8; y: 2; x: t.checked ? 20 : 2; color: t.checked ? Theme.bg : Theme.fgDim
                    Behavior on x { NumberAnimation { duration: Theme.anim } } }
        MouseArea { anchors.fill: parent; onClicked: t.toggled(!t.checked) }
    }
    Glyph { text: t.label; anchors.verticalCenter: parent.verticalCenter }
}
