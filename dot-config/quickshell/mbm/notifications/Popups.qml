import Quickshell
import Quickshell.Wayland
import QtQuick
import "../theme"
import "../services"

PanelWindow {
    id: win
    readonly property string corner: Settings.notifCorner
    readonly property bool topSide: corner.startsWith("top")
    // The bar's tab hangs off one edge; only a pop-up on that edge needs to clear it.
    readonly property bool belowTab: ShellState.barVisible && (Settings.barPosition !== "bottom") === win.topSide
    readonly property int edgeMargin: win.belowTab ? Theme.popupTop : Theme.popupSide
    screen: ShellState.focusedScreen()
    // Hidden while quick settings is open: its history shows the same items.
    visible: Notifs.popups.length > 0 && !ShellState.qsOpen && !ShellState.locked
    anchors { top: win.topSide; bottom: !win.topSide; right: corner.endsWith("right"); left: corner.endsWith("left") }
    margins { top: win.edgeMargin; bottom: win.edgeMargin; left: Theme.popupSide; right: Theme.popupSide }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "mbm-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    implicitWidth: 360
    implicitHeight: column.implicitHeight

    Column {
        id: column
        spacing: Theme.gap
        Repeater {
            model: Notifs.popups
            delegate: NotificationCard { required property var modelData; notification: modelData; popup: true }
        }
    }
}
