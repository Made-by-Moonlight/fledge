import Quickshell
import Quickshell.Hyprland
import QtQuick
import "../../theme"

Row {
    id: root
    property var screen: null
    readonly property var monitor: screen ? Hyprland.monitorFor(screen) : null
    spacing: 6

    Repeater {
        model: Hyprland.workspaces.values.filter(w => w.id > 0 && (!root.monitor || w.monitor === root.monitor))
        delegate: Rectangle {
            required property var modelData
            anchors.verticalCenter: parent.verticalCenter
            width: modelData.active ? 22 : 8
            height: 8
            radius: 4
            color: modelData.active ? Theme.accent : (modelData.toplevels.values.length > 0 ? Theme.fgDim : Theme.muted)
            Behavior on width { NumberAnimation { duration: Theme.anim } }
            MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: parent.modelData.activate() }
        }
    }
}
