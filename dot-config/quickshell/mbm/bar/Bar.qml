import Quickshell
import Quickshell.Wayland
import QtQuick
import "../theme"
import "../services"

PanelWindow {
    id: bar
    visible: ShellState.barVisible
    readonly property bool top: Settings.barPosition !== "bottom"
    anchors { top: bar.top; bottom: !bar.top; left: true; right: true }
    margins { top: Theme.gap; bottom: Theme.gap; left: Theme.gap; right: Theme.gap }
    implicitHeight: Theme.barHeight
    exclusionMode: ExclusionMode.Auto
    color: "transparent"
    WlrLayershell.namespace: "mbm-bar"

    Island { anchors.left: parent.left; modules: Settings.barLeft; screen: bar.screen }
    Island { anchors.horizontalCenter: parent.horizontalCenter; modules: Settings.barCentre; screen: bar.screen }
    Island { anchors.right: parent.right; modules: Settings.barRight; screen: bar.screen }
}
