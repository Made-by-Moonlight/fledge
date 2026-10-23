import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../theme"
import "../services"
import "../components"
import "Share.js" as Share

// The screen-share picker. xdg-desktop-portal-hyprland runs `fledge screenshare pick`
// (lib/screenshare.sh), which opens this over IPC and waits on a FIFO for the answer:
// "1\n<flags>/<target>\n" (flags "r": the app may keep a restore token) or "0\n\n".
// One request at a time: open() answers "busy" while one is up. Under the lock, and while
// the polkit dialog is up, it stays hidden and the request waits (the helper's timeout runs).
Scope {
    id: root

    property var request: null          // { windows, result }; windows parsed from xdph's list
    property string tab: "windows"
    property int index: 0
    property bool remember: false
    readonly property bool shown: request !== null && !ShellState.locked && !ShellState.polkitOpen
    readonly property var items: tab === "windows" ? (request?.windows ?? []) : Quickshell.screens

    Binding { target: ShellState; property: "shareOpen"; value: root.shown }
    onShownChanged: {
        if (!shown) return;
        // Only one surface holds the keyboard: popups close (a waiting dmenu gets "cancel").
        ShellState.closePopups();
        win.openScreen = ShellState.focusedScreen();
    }

    function toplevelOf(w) { return Hyprland.toplevels.values.find(t => Share.sameWindow(t.address, w.address)) ?? null; }
    function iconOf(cls) {
        const icon = DesktopEntries.heuristicLookup(cls)?.icon ?? "";
        return icon ? Quickshell.iconPath(icon, true) : "";
    }

    function open(list, result, allowToken) {
        if (request) return "busy";
        const windows = Share.parse(list);
        // Hyprland's toplevel list fills lazily; the thumbnails need it current.
        Hyprland.refreshToplevels();
        request = { windows, result };
        remember = allowToken === "true";
        tab = windows.length ? "windows" : "screens";
        index = 0;
        return "ok";
    }
    function finish(ok, value) {
        const r = request;
        request = null;
        if (!r) return;
        // Bounded: if the helper died, nothing reads the FIFO and a bare redirect would block forever.
        Quickshell.execDetached(["timeout", "2", "sh", "-c", 'printf "%s\\n%s\\n" "$1" "$2" > "$3"', "sh", ok ? "1" : "0", value, r.result]);
    }
    function pick(i) {
        const it = items[i];
        if (!it) return;
        finish(true, tab === "windows" ? Share.answer("window", it.handle, remember) : Share.answer("screen", it.name, remember));
    }
    function cancel() { finish(false, ""); }
    // The helper gave up (timeout, signal): drop the dialog, nobody is reading any more.
    function dismiss() { request = null; }
    function switchTab() { tab = tab === "windows" ? "screens" : "windows"; index = 0; }

    PanelWindow {
        id: win
        // Fixed when the dialog opens, like the polkit dialog: a live binding would recreate the surface.
        property var openScreen: ShellState.focusedScreen()
        visible: root.shown
        screen: openScreen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fledge-screenshare"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.6)

        MouseArea { anchors.fill: parent; onClicked: root.cancel() }

        Pill {
            id: card
            anchors.centerIn: parent
            width: Math.min(820, win.width - 80); height: Math.min(col.implicitHeight + 40, win.height - 80)
            radius: Theme.radiusLarge
            color: Theme.panelSolid
            // Clicks on the card don't fall through to the cancelling backdrop.
            MouseArea { anchors.fill: parent }

            focus: root.shown
            Keys.onEscapePressed: root.cancel()
            Keys.onTabPressed: root.switchTab()
            Keys.onBacktabPressed: root.switchTab()
            Keys.onReturnPressed: root.pick(root.index)
            Keys.onEnterPressed: root.pick(root.index)
            Keys.onLeftPressed: root.index = Math.max(0, root.index - 1)
            Keys.onRightPressed: root.index = Math.min(root.items.length - 1, root.index + 1)
            Keys.onUpPressed: root.index = Math.max(0, root.index - grid.columns)
            Keys.onDownPressed: root.index = Math.min(root.items.length - 1, root.index + grid.columns)

            ColumnLayout {
                id: col
                anchors { fill: parent; margins: 20 }
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    Glyph { text: "󰹑  Share your screen"; font.bold: true; font.pixelSize: Theme.fontLarge; color: Theme.accent; Layout.fillWidth: true }
                    Repeater {
                        model: [{ key: "windows", label: "Windows" }, { key: "screens", label: "Screens" }]
                        delegate: Button {
                            required property var modelData
                            text: modelData.label
                            primary: root.tab === modelData.key
                            onClicked: { root.tab = modelData.key; root.index = 0; }
                        }
                    }
                }

                Glyph {
                    visible: root.items.length === 0
                    text: root.tab === "windows" ? "No windows to share" : "No screens"
                    color: Theme.muted
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: grid.implicitHeight
                    contentHeight: grid.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Grid {
                        id: grid
                        width: parent.width
                        columns: 3
                        spacing: 12
                        readonly property real cell: (width - spacing * (columns - 1)) / columns
                        Repeater {
                            model: root.items
                            delegate: Rectangle {
                                id: tile
                                required property var modelData
                                required property int index
                                readonly property bool isWindow: root.tab === "windows"
                                readonly property var source: isWindow ? (root.toplevelOf(modelData)?.wayland ?? null) : modelData
                                readonly property bool current: index === root.index
                                width: grid.cell; height: width * 9 / 16 + 40
                                radius: Theme.radius
                                color: current ? Theme.accentSoft : (ma.containsMouse ? Theme.surface : Theme.bgRaised)
                                border.color: current ? Theme.accent : "transparent"
                                border.width: 2

                                Rectangle {
                                    id: thumb
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                                    height: width * 9 / 16 - 8
                                    radius: Theme.radius - 4
                                    color: Theme.bg
                                    clip: true
                                    ScreencopyView {
                                        anchors.fill: parent
                                        visible: tile.source !== null
                                        captureSource: root.shown ? tile.source : null
                                        live: true
                                        constraintSize: Qt.size(width, height)
                                    }
                                    Glyph {
                                        anchors.centerIn: parent
                                        visible: tile.source === null
                                        text: tile.isWindow ? "󰖯" : "󰍹"
                                        font.pixelSize: 28; color: Theme.muted
                                    }
                                }
                                RowLayout {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
                                    spacing: 6
                                    IconImage {
                                        Layout.preferredWidth: 16; Layout.preferredHeight: 16
                                        source: tile.isWindow ? root.iconOf(tile.modelData.cls) : ""
                                        visible: source != ""
                                    }
                                    Glyph {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        textFormat: Text.PlainText
                                        text: tile.isWindow ? (tile.modelData.title || tile.modelData.cls) : tile.modelData.name
                                        color: tile.current ? Theme.accent : Theme.fg
                                    }
                                }
                                MouseArea {
                                    id: ma
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.pick(tile.index)
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.gap
                    Toggle {
                        label: "Remember this choice"
                        checked: root.remember
                        onToggled: c => root.remember = c
                        Layout.fillWidth: true
                    }
                    Button { text: "Cancel"; onClicked: root.cancel() }
                    Button { text: "Share"; primary: true; enabled: root.items.length > 0; onClicked: root.pick(root.index) }
                }
            }
        }
    }
}
