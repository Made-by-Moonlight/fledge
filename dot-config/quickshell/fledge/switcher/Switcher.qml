import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../theme"
import "../services"
import "../components"

// The Alt+Tab window switcher. Hyprland drives it: the bind sends a custom event
// (hl.dsp.event "fledge-switcher next|prev") and enters the fledge-switcher submap
// (gen-binds.jq), whose binds step on, and on letting go of the modifier send "commit"
// and leave the submap themselves. Nothing here holds the keyboard or polls, and a quick
// tap commits before the panel is shown, so it captures no previews at all.
// Previews are one frame per visible tile (live: false), taken when the panel shows.
Scope {
    id: root

    property var mru: []          // window addresses (bare hex, as Hyprland's events give them), most recent first
    property var items: []        // the HyprlandToplevels in MRU order, fixed while the switcher is up
    property int index: 0
    property bool active: false   // between the first next/prev and commit/cancel
    property bool shown: false    // the panel is up (only once the tap delay has passed)

    // Seed the order from Hyprland's focus history once; focus events keep it after that.
    Process {
        running: true
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const seen = JSON.parse(text).sort((a, b) => a.focusHistoryID - b.focusHistoryID)
                        .map(c => c.address.replace(/^0x/, ""));
                    root.mru = [...root.mru, ...seen.filter(a => !root.mru.includes(a))];
                } catch (e) { console.warn("Switcher: can't read hyprctl clients: " + e); }
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            switch (event.name) {
            case "activewindowv2":
                if (event.data) root.mru = [event.data, ...root.mru.filter(a => a !== event.data)];
                break;
            case "closewindow":
                root.mru = root.mru.filter(a => a !== event.data);
                if (root.active) root.drop(event.data);
                break;
            case "custom":
                if (event.data.startsWith("fledge-switcher ")) root.handle(event.data.slice(16));
                break;
            case "submap":
                // Left some other way (a reload, a stale reset): don't stay up with nothing to end it.
                if (root.active && event.data !== "fledge-switcher") root.close();
                break;
            }
        }
    }

    function handle(cmd) {
        if (cmd === "next" || cmd === "prev") {
            if (!active && !open()) return;
            if (items.length) index = (index + (cmd === "next" ? 1 : -1) + items.length) % items.length;
        } else if (cmd === "commit") {
            if (active) pick(index, false);
        } else if (cmd === "cancel") {
            close();
        }
    }

    function open() {
        // The bind's submap is left on release whatever happens here.
        if (ShellState.locked || ShellState.dialogOpen) return false;
        ShellState.closePopups();
        const rank = a => { const i = mru.indexOf(a); return i < 0 ? mru.length : i; };
        items = Hyprland.toplevels.values.slice().sort((a, b) => rank(a.address) - rank(b.address));
        index = 0;
        active = true;
        win.openScreen = ShellState.focusedScreen();
        showDelay.restart();
        return true;
    }
    function close() {
        showDelay.stop();
        active = false;
        shown = false;
        items = [];
    }
    function drop(address) {
        const i = items.findIndex(t => t.address === address);
        if (i < 0) return;
        items = items.filter((_, j) => j !== i);
        if (i < index || index >= items.length) index = Math.max(0, index - 1);
    }
    // fromPointer: a click, while the bind's modifier is still held, so the submap is still on.
    function pick(i, fromPointer) {
        const t = items[i];
        close();
        if (fromPointer) Hypr.dispatch('hl.dsp.submap("reset")');
        if (!t) return;
        // Focusing a window on another workspace (or monitor) switches to it there.
        Hypr.evalLua("hl.dispatch(hl.dsp.focus({ window = " + Hypr.lit("address:0x" + t.address) + " })) "
            + "hl.dispatch(hl.dsp.window.bring_to_top())");
    }

    function iconOf(t) {
        const icon = DesktopEntries.heuristicLookup(t?.wayland?.appId ?? "")?.icon ?? "";
        return icon ? Quickshell.iconPath(icon, true) : "";
    }

    Timer { id: showDelay; interval: 120; onTriggered: root.shown = true }

    PanelWindow {
        id: win
        // Fixed when the switcher opens, like the launcher: a live binding would recreate the surface.
        property var openScreen: ShellState.focusedScreen()
        readonly property int tileW: 232
        readonly property int thumbH: 132
        visible: root.shown
        screen: openScreen
        // No anchors: layer shell centres it. Only as big as the strip, not a full-screen dim.
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fledge-switcher"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        implicitWidth: Math.max(win.tileW, Math.min(root.items.length * (win.tileW + Theme.gap) - Theme.gap,
                                                    (openScreen?.width ?? 1920) - 160)) + 32
        implicitHeight: win.thumbH + 70 + 32

        Pill {
            anchors.fill: parent
            radius: Theme.radiusLarge
            color: Theme.panelSolid

            Glyph {
                anchors.centerIn: parent
                visible: root.items.length === 0
                text: "No windows"
                color: Theme.muted
            }

            ListView {
                id: list
                anchors { fill: parent; margins: 16 }
                orientation: ListView.Horizontal
                spacing: Theme.gap
                interactive: false
                // Only the tiles in view exist, so only they capture a preview.
                cacheBuffer: 0
                model: root.shown ? root.items : []
                currentIndex: root.index
                highlightFollowsCurrentItem: false
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property bool current: index === root.index
                    readonly property bool elsewhere: modelData.workspace !== null && modelData.workspace !== Hyprland.focusedWorkspace
                    width: win.tileW; height: list.height
                    radius: Theme.radius
                    color: current ? Theme.accentSoft : (ma.containsMouse ? Theme.surface : "transparent")
                    border.color: current ? Theme.accent : "transparent"
                    border.width: 2

                    Item {
                        id: thumb
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                        height: win.thumbH
                        // A frame: many windows are as dark as the panel.
                        Rectangle {
                            anchors.centerIn: parent
                            visible: shot.hasContent
                            width: shot.width + 2; height: shot.height + 2
                            color: "transparent"
                            border.color: Theme.surface
                        }
                        ScreencopyView {
                            id: shot
                            anchors.centerIn: parent
                            width: implicitWidth; height: implicitHeight
                            captureSource: tile.modelData.wayland
                            live: false
                            constraintSize: Qt.size(thumb.width - 2, thumb.height - 2)
                        }
                        IconImage {
                            anchors.centerIn: parent
                            visible: !shot.hasContent
                            implicitSize: 48
                            source: root.iconOf(tile.modelData)
                        }
                        // Where it lives, when that isn't here: picking it switches there.
                        Rectangle {
                            visible: tile.elsewhere
                            anchors { right: parent.right; bottom: parent.bottom; margins: 4 }
                            width: ws.implicitWidth + 12; height: ws.implicitHeight + 4
                            radius: height / 2
                            color: Theme.surface
                            Glyph {
                                id: ws
                                anchors.centerIn: parent
                                text: tile.modelData.workspace?.name ?? ""
                                font.pixelSize: Theme.fontSmall
                                color: Theme.fgDim
                            }
                        }
                    }
                    RowLayout {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
                        spacing: 6
                        IconImage {
                            Layout.preferredWidth: 16; Layout.preferredHeight: 16
                            source: root.iconOf(tile.modelData)
                            visible: source != ""
                        }
                        Glyph {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: tile.modelData.title || (tile.modelData.wayland?.appId ?? "")
                            color: tile.current ? Theme.accent : Theme.fg
                        }
                    }
                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.pick(tile.index, true)
                    }
                }
            }
        }
    }
}
