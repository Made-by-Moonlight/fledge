import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../theme"
import "../services"
import "../components"
import "modes"

// Mode contract (Tasks 11-12): a mode is an Item with `name`, `label`, `placeholder`,
// results(query) -> [{ key, text, sub, icon, glyph, run }], and optionally activated(),
// keepOpen, initialIndex, submit(item, text), remove(item) and a `changed()` signal
// (emit it when results(query) would now differ, e.g. an async source filled in).
PanelWindow {
    id: win
    readonly property bool anchored: Settings.launcherPosition === "anchored"
    readonly property bool barTop: Settings.barPosition !== "bottom"
    readonly property var modes: [apps, clipboard, emoji, system]
    readonly property var mode: ShellState.launcherMode === "dmenu" ? dmenu : (modes.find(m => m.name === ShellState.launcherMode) ?? apps)
    property var items: []
    property string query: ""

    // The screen is fixed when the launcher opens: a live binding to the focused monitor would
    // recreate the surface (moving it, or dropping the grab) when the pointer crosses monitors.
    property var openScreen: ShellState.focusedScreen()
    property bool opened: false
    Connections {
        target: ShellState
        function onLauncherOpenChanged() {
            if (ShellState.launcherOpen) win.openScreen = ShellState.focusedScreen();
            win.opened = ShellState.launcherOpen;
        }
    }
    visible: opened
    screen: openScreen
    // Anchored drops from the bar's left tab, so it follows the bar to the bottom edge too.
    anchors { top: !win.anchored || win.barTop; bottom: win.anchored && !win.barTop; left: win.anchored }
    margins {
        top: win.anchored ? Theme.popupTop : Math.round((screen?.height ?? 1080) * 0.2)
        bottom: Theme.popupTop
        left: Theme.popupSide
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "fledge-launcher"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    color: "transparent"
    implicitWidth: 620
    implicitHeight: 420

    AppsMode { id: apps }
    ClipboardMode { id: clipboard }
    EmojiMode { id: emoji }
    SystemMode { id: system }
    property alias systemMode: system
    DmenuMode { id: dmenu }

    // Prefixes switch mode from the search box: ">" system, ":" emoji, "v " clipboard.
    function parse(text) {
        if (ShellState.launcherMode === "dmenu") return text;
        const p = [[">", "system"], [":", "emoji"], ["v ", "clipboard"]].find(([pre]) => text.startsWith(pre));
        if (p && ShellState.launcherMode !== p[1]) { ShellState.launcherMode = p[1]; field.text = text.slice(p[0].length); return field.text; }
        return text;
    }
    function refresh() {
        items = mode.results(query);
        // initialIndex (dmenu --select) only applies to the unfiltered list; once typing, the best match leads.
        list.currentIndex = items.length ? Math.min(Math.max(query ? 0 : (mode.initialIndex ?? 0), 0), items.length - 1) : -1;
    }
    function runCurrent() {
        const it = items[list.currentIndex];
        if (mode.submit) { mode.submit(it, field.text); return; }
        if (!it) return;
        if (!mode.keepOpen) ShellState.closePopups();
        it.run();
    }
    // Icon name or absolute path; "" when the theme lacks it, and the row shows a glyph instead.
    function iconSource(icon) {
        if (!icon) return "";
        if (icon.startsWith("/")) return "file://" + icon;
        return Quickshell.iconPath(icon, true);
    }
    function cycle(step) {
        if (ShellState.launcherMode === "dmenu") return;
        const i = modes.indexOf(mode);
        ShellState.launcherMode = modes[(i + step + modes.length) % modes.length].name;
    }

    onVisibleChanged: if (visible) { field.text = ""; query = ""; if (mode.activated) mode.activated(); refresh(); field.forceActiveFocus(); }
    onModeChanged: if (visible) { if (mode.activated) mode.activated(); refresh(); }
    Connections { target: win.mode; ignoreUnknownSignals: true; function onChanged() { if (win.visible) win.refresh(); } }

    // Click outside closes (Hyprland focus grab).
    HyprlandFocusGrab { active: win.visible; windows: [win]; onCleared: ShellState.closePopups() }

    Pill {
        anchors.fill: parent
        radius: Theme.radiusLarge
        color: Theme.panelSolid

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: Theme.radius; color: "transparent"; border.color: Theme.accent; border.width: 1
                Row {
                    anchors.fill: parent; anchors.leftMargin: 12; spacing: 8
                    Glyph { text: ShellState.dmenu?.prompt ? ShellState.dmenu.prompt : "›"; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                    TextInput {
                        id: field
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 60
                        color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.bg
                        font.family: Theme.font; font.pixelSize: Theme.fontSize
                        onTextChanged: { win.query = win.parse(text); if (win.visible) win.refresh(); }
                        Text { visible: !parent.text; text: win.mode.placeholder; textFormat: Text.PlainText; color: Theme.muted; font: parent.font }
                        Keys.onPressed: e => {
                            if (e.key === Qt.Key_Escape) { ShellState.closePopups(); e.accepted = true; }
                            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { win.runCurrent(); e.accepted = true; }
                            else if (e.key === Qt.Key_Down || (e.key === Qt.Key_J && e.modifiers & Qt.ControlModifier)) { list.incrementCurrentIndex(); e.accepted = true; }
                            else if (e.key === Qt.Key_Up || (e.key === Qt.Key_K && e.modifiers & Qt.ControlModifier)) { list.decrementCurrentIndex(); e.accepted = true; }
                            else if (e.key === Qt.Key_Tab) { win.cycle(1); e.accepted = true; }
                            else if (e.key === Qt.Key_Backtab) { win.cycle(-1); e.accepted = true; }
                            else if (e.key === Qt.Key_Delete && e.modifiers & Qt.ShiftModifier && win.mode.remove) { win.mode.remove(win.items[list.currentIndex]); e.accepted = true; }
                        }
                    }
                }
            }

            Row {
                visible: ShellState.launcherMode !== "dmenu"
                spacing: 4
                Repeater {
                    model: win.modes
                    delegate: Rectangle {
                        id: tab
                        required property var modelData
                        readonly property bool on: win.mode === modelData
                        height: 22; width: t.implicitWidth + 14; radius: 6
                        color: on ? Theme.accent : "transparent"
                        Glyph { id: t; anchors.centerIn: parent; text: tab.modelData.label; font.pixelSize: Theme.fontSmall; font.bold: tab.on; color: tab.on ? Theme.bg : Theme.muted }
                        MouseArea { anchors.fill: parent; onClicked: { ShellState.launcherMode = tab.modelData.name; field.forceActiveFocus(); } }
                    }
                }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: win.items
                highlightMoveDuration: 0
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width: list.width; height: 38; radius: 7
                    color: ListView.isCurrentItem ? Theme.surface : "transparent"
                    Row {
                        anchors.fill: parent; anchors.leftMargin: 8; spacing: 10
                        Item {
                            width: 22; height: 22; anchors.verticalCenter: parent.verticalCenter
                            IconImage { anchors.fill: parent; visible: source != ""; source: win.iconSource(row.modelData.icon) }
                            Glyph { anchors.centerIn: parent; visible: win.iconSource(row.modelData.icon) == ""; text: row.modelData.glyph ?? "󰀻"; font.pixelSize: Theme.fontLarge }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Glyph { text: row.modelData.text; elide: Text.ElideRight; width: list.width - 60 }
                            Glyph { visible: !!row.modelData.sub; text: row.modelData.sub ?? ""; color: Theme.muted; font.pixelSize: Theme.fontSmall; elide: Text.ElideRight; width: list.width - 60 }
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: { list.currentIndex = row.index; win.runCurrent(); } }
                }
            }
        }
    }
}
