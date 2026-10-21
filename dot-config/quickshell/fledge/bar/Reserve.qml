import Quickshell
import Quickshell.Wayland
import QtQuick

// An invisible surface that only reserves space along one screen edge. The bar is drawn by
// one fullscreen surface that ignores exclusive zones, so the bar edge's zone is held by this.
PanelWindow {
    id: reserve
    required property string edge   // top | bottom | left | right
    property int size: 0
    anchors { top: reserve.edge !== "bottom"; bottom: reserve.edge !== "top"; left: reserve.edge !== "right"; right: reserve.edge !== "left" }
    implicitWidth: 1
    implicitHeight: 1
    exclusiveZone: size
    exclusionMode: ExclusionMode.Normal
    aboveWindows: false
    focusable: false
    color: "transparent"
    mask: Region {}
    WlrLayershell.namespace: "fledge-frame-reserve"
}
