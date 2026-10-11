import Quickshell
import Quickshell.Wayland
import QtQuick
import "../theme"
import "../services"

// The attached bar and screen frame for one screen: a thin dark border round the screen whose
// bar edge carries a tab per section (left from the corner, centre, right into the corner),
// and a desktop with rounded corners. One fullscreen surface draws it all (no seams between
// pieces) and takes clicks only on the strip and the tabs; four invisible Reserve surfaces hold
// the exclusive zones, so windows tile inside the frame and below the tabs.
Scope {
    id: root
    required property ShellScreen screen
    readonly property bool top: Settings.barPosition !== "bottom"
    readonly property bool shown: ShellState.barVisible

    Reserve { screen: root.screen; visible: root.shown; edge: root.top ? "top" : "bottom"; size: Theme.barHeight }
    Reserve { screen: root.screen; visible: root.shown; edge: root.top ? "bottom" : "top"; size: Theme.frame }
    Reserve { screen: root.screen; visible: root.shown; edge: "left"; size: Theme.frame }
    Reserve { screen: root.screen; visible: root.shown; edge: "right"; size: Theme.frame }

    PanelWindow {
        id: bar
        screen: root.screen
        visible: root.shown
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        focusable: false
        color: "transparent"
        WlrLayershell.namespace: "mbm-bar"
        // Transparent pixels still belong to the surface; only the strip and tabs take input.
        mask: Region {
            item: strip
            Region { item: leftTab; intersection: Intersection.Combine }
            Region { item: centreTab; intersection: Intersection.Combine }
            Region { item: rightTab; intersection: Intersection.Combine }
        }

        Frame {
            anchors.fill: parent
            atTop: root.top
            tabs: [leftTab, centreTab, rightTab].filter(t => t.width > 0).map(t => [t.x, t.x + t.width])
        }

        // The bar edge's border, and one tab per non-empty section (the shapes' input areas).
        Item { id: strip; width: parent.width; height: Theme.frame; y: root.top ? 0 : parent.height - height }
        Item {
            id: leftTab
            width: left.width > 0 ? left.x + left.width + Theme.tabPad : 0
            height: Theme.barHeight
            y: root.top ? 0 : parent.height - height
        }
        Item {
            id: centreTab
            x: Math.round((parent.width - centre.width) / 2) - Theme.tabPad
            width: centre.width > 0 ? parent.width - 2 * x : 0
            height: Theme.barHeight
            y: leftTab.y
        }
        Item {
            id: rightTab
            x: right.x - Theme.tabPad
            width: right.width > 0 ? parent.width - x : 0
            height: Theme.barHeight
            y: leftTab.y
        }

        Section {
            id: left
            x: Theme.frame + Theme.gap
            anchors.verticalCenter: leftTab.verticalCenter
            modules: Settings.barLeft
            screen: root.screen
        }
        Section {
            id: centre
            // Truly centred on the screen, whatever the side sections' widths.
            x: Math.round((parent.width - width) / 2)
            anchors.verticalCenter: leftTab.verticalCenter
            modules: Settings.barCentre
            screen: root.screen
        }
        Section {
            id: right
            x: parent.width - width - Theme.frame - Theme.gap
            anchors.verticalCenter: leftTab.verticalCenter
            modules: Settings.barRight
            screen: root.screen
        }
    }
}
