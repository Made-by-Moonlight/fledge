import Quickshell
import Quickshell.Wayland
import QtQuick
import "../theme"
import "../services"

// The attached bar for one screen: a thin dark strip along the bar edge carrying a tab per
// section (left from the corner, centre, right into the corner); the other edges have no
// border. One fullscreen surface draws it (no seams between pieces) and takes clicks only on
// the strip and the tabs; an invisible Reserve holds the exclusive zone, so windows tile
// below the tabs. Only on screens that show a bar (ShellState.showsBar).
Scope {
    id: root
    required property ShellScreen screen
    readonly property bool top: Settings.barPosition !== "bottom"
    readonly property bool shown: ShellState.barVisible

    Reserve { screen: root.screen; visible: root.shown; edge: root.top ? "top" : "bottom"; size: Theme.barHeight }

    PanelWindow {
        id: bar
        screen: root.screen
        visible: root.shown
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        focusable: false
        color: "transparent"
        WlrLayershell.namespace: "fledge-bar"
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
            x: Theme.gap
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
            x: parent.width - width - Theme.gap
            anchors.verticalCenter: leftTab.verticalCenter
            modules: Settings.barRight
            screen: root.screen
        }
    }
}
