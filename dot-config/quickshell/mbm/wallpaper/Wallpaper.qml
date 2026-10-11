import Quickshell
import Quickshell.Wayland
import QtQuick
import "../theme"

PanelWindow {
    id: wall
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "mbm-wallpaper"
    color: Theme.bg

    // Moonrise is rendered at three sizes; take the closest. Crop keeps the owl centred.
    readonly property string file: {
        const w = Math.max(screen.width, screen.height), r = w / Math.min(screen.width, screen.height);
        if (r > 2.0) return "moonrise-3440x1440.png";
        return w >= 2560 ? "moonrise-2560x1440.png" : "moonrise-1920x1080.png";
    }

    Image {
        anchors.fill: parent
        source: "file://" + Theme.assets + "/" + wall.file
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: wall.screen.width
    }
}
