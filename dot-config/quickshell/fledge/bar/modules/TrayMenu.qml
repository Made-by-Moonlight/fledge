import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import "../../theme"
import "../../services"
import "../../components"

// A tray icon's menu drawn in the shell's own style. QsMenuAnchor shows a stock Qt menu, which
// ignores the palette (light, square, system font). Submenus open in place with a back row
// rather than as cascading popups: one surface, one focus grab. A layer surface like the other
// popups, not a PopupWindow: Hyprland's focus grab didn't close an xdg_popup on a click outside.
PanelWindow {
    id: popup
    property var handle: null   // the tray item's menu
    property var stack: []      // submenus opened, innermost last
    readonly property var current: stack.length ? stack[stack.length - 1] : handle
    readonly property bool barTop: Settings.barPosition !== "bottom"
    property bool right: true   // the icon is on the screen's right half: grow leftwards
    property int side: 0        // from the screen edge it grows away from to the icon's near side
    property var openScreen: null

    // open(item, menu): hang one gap below the bar (like every other popup), lined up with the
    // icon and growing towards the screen's middle. The bar's surface is fullscreen, so its
    // coordinates are the screen's.
    function open(item, menu) {
        const win = item.QsWindow.window;
        const p = item.mapToItem(null, 0, 0);
        right = p.x > win.width / 2;
        side = Math.max(Theme.popupSide, Math.round(right ? win.width - p.x - item.width : p.x));
        openScreen = win.screen;
        handle = menu;
        stack = [];
        visible = true;
    }
    function close() { visible = false; handle = null; stack = []; }

    visible: false
    screen: openScreen
    anchors { top: popup.barTop; bottom: !popup.barTop; left: !popup.right; right: popup.right }
    margins { top: Theme.popupTop; bottom: Theme.popupTop; left: popup.side; right: popup.side }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "fledge-traymenu"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    color: "transparent"
    implicitWidth: panel.width
    implicitHeight: panel.height

    HyprlandFocusGrab { active: popup.visible; windows: [popup]; onCleared: popup.close() }

    QsMenuOpener { id: opener; menu: popup.current }
    readonly property var entries: opener.children ? opener.children.values : []

    // The widest label sets the menu's width (within limits), so rows don't reflow per hover.
    Column {
        id: measure
        visible: false
        Repeater { model: popup.entries; Glyph { required property var modelData; text: modelData.text ?? ""; font.pixelSize: Theme.fontSmall } }
    }

    Pill {
        id: panel
        color: Theme.panelSolid
        width: Math.min(320, Math.max(140, measure.width + 60))
        height: list.implicitHeight + 8
        focus: popup.visible
        Keys.onEscapePressed: popup.stack.length ? popup.stack = popup.stack.slice(0, -1) : popup.close()

        Column {
            id: list
            x: 4; y: 4
            width: parent.width - 8

            Row {
                id: back
                visible: popup.stack.length > 0
                height: 24
                Rectangle {
                    width: list.width; height: 24; radius: 6
                    color: backMa.containsMouse ? Theme.surface : "transparent"
                    Glyph { anchors.verticalCenter: parent.verticalCenter; x: 6; text: "󰁍  Back"; color: Theme.fgDim; font.pixelSize: Theme.fontSmall }
                    MouseArea { id: backMa; anchors.fill: parent; hoverEnabled: true; onClicked: popup.stack = popup.stack.slice(0, -1) }
                }
            }
            Rectangle { visible: back.visible; width: list.width; height: 7; color: "transparent"
                        Rectangle { anchors.centerIn: parent; width: parent.width - 12; height: 1; color: Theme.surface } }

            Repeater {
                model: popup.entries
                delegate: Item {
                    id: row
                    required property var modelData
                    readonly property bool sep: modelData.isSeparator
                    readonly property bool check: modelData.buttonType !== QsMenuButtonType.None
                    width: list.width
                    height: sep ? 7 : 24

                    Rectangle {
                        visible: row.sep
                        anchors.centerIn: parent
                        width: parent.width - 12; height: 1
                        color: Theme.surface
                    }
                    Rectangle {
                        visible: !row.sep
                        anchors.fill: parent
                        radius: 6
                        color: ma.containsMouse && row.modelData.enabled ? Theme.surface : "transparent"

                        // Check/radio state, else the app's icon, in one fixed column so labels line up.
                        Item {
                            id: lead
                            x: 6; width: 14; height: parent.height
                            Glyph {
                                anchors.centerIn: parent
                                visible: row.check
                                color: Theme.accent
                                font.pixelSize: Theme.fontSmall
                                text: row.modelData.checkState === Qt.Unchecked ? ""
                                    : row.modelData.buttonType === QsMenuButtonType.RadioButton ? "󰄯" : "󰄬"
                            }
                            IconImage {
                                anchors.centerIn: parent
                                visible: !row.check && row.modelData.icon !== ""
                                implicitSize: 14
                                source: row.modelData.icon
                            }
                        }
                        Glyph {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: lead.right; anchors.leftMargin: 6
                            anchors.right: arrow.left; anchors.rightMargin: 6
                            elide: Text.ElideRight
                            font.pixelSize: Theme.fontSmall
                            text: row.modelData.text
                            color: row.modelData.enabled ? Theme.fg : Theme.muted
                        }
                        Glyph {
                            id: arrow
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right; anchors.rightMargin: 6
                            text: row.modelData.hasChildren ? "󰅂" : ""
                            font.pixelSize: Theme.fontSmall
                            color: Theme.fgDim
                        }
                        MouseArea {
                            id: ma
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: row.modelData.enabled
                            onClicked: {
                                if (row.modelData.hasChildren) { popup.stack = popup.stack.concat([row.modelData]); return; }
                                row.modelData.triggered();
                                popup.close();
                            }
                        }
                    }
                }
            }
        }
    }
}
