import Quickshell
import Quickshell.Hyprland
import QtQuick
import "../../theme"
import "../../services"

// Workspace dots. The main monitor's bar lists every monitor's workspaces, grouped left to
// right with a divider between monitors, so those on a monitor without a bar stay visible;
// any other bar lists its own monitor's.
Row {
    id: root
    property var screen: null
    readonly property var monitor: screen ? Hyprland.monitorFor(screen) : null
    readonly property bool main: ShellState.keyOfScreen(screen) === ShellState.mainKey
    spacing: Theme.gap

    readonly property var groups: {
        const ws = Hyprland.workspaces.values.filter(w => w.id > 0).sort((a, b) => a.id - b.id);
        if (!root.main) return [ws.filter(w => !root.monitor || w.monitor === root.monitor)];
        const mons = [...ShellState.monitors].sort((a, b) => a.x - b.x || a.y - b.y);
        return mons.map(m => ws.filter(w => w.monitor?.name === m.name)).filter(g => g.length > 0);
    }

    Repeater {
        model: root.groups
        delegate: Row {
            id: group
            required property var modelData
            required property int index
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(6 * Theme.barScale)

            Rectangle {
                visible: group.index > 0
                anchors.verticalCenter: parent.verticalCenter
                width: 1; height: Math.round(12 * Theme.barScale)
                color: Theme.surface
            }
            Repeater {
                model: group.modelData
                delegate: Rectangle {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round((modelData.active ? 22 : 8) * Theme.barScale)
                    height: Math.round(8 * Theme.barScale)
                    radius: height / 2
                    // Wide where it's showing on its monitor; accent only for the focused one
                    // (on the main bar several monitors' showing workspaces sit side by side).
                    color: (root.main ? modelData.focused : modelData.active) ? Theme.accent
                         : (modelData.active || modelData.toplevels.values.length > 0 ? Theme.fgDim : Theme.muted)
                    Behavior on width { NumberAnimation { duration: Theme.anim } }
                    MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: parent.modelData.activate() }
                }
            }
        }
    }
}
