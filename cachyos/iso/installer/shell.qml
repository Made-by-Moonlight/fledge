//@ pragma UseQApplication
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "services"
import "theme"
import "ui"

// The fledge installer (made by moonlight): one full-screen layer per monitor; the
// monitor Hyprland has focused at startup gets the installer, the others the
// owl. Run by the live ISO's Hyprland (/etc/fledge-installer/hyprland.lua); dev:
// dev/run.sh.
ShellRoot {
    id: shell
    settings.watchFiles: Installer.dev
    // Taken once, from the first focused monitor Hyprland reports (it fills in
    // after startup), so the installer doesn't follow the pointer between
    // monitors. Unplugged, or never reported: the first screen.
    property string mainName: ""
    readonly property ShellScreen mainScreen: {
        const all = Quickshell.screens;
        for (let i = 0; i < all.length; i++) if (all[i].name === mainName) return all[i];
        return all.length > 0 ? all[0] : null;
    }
    // The main window's focused item, for the IPC focused().
    property Item focusItem: null
    function latchMain() { if (mainName === "" && Hyprland.focusedMonitor) mainName = Hyprland.focusedMonitor.name; }
    Component.onCompleted: latchMain()
    Connections { target: Hyprland; function onFocusedMonitorChanged() { shell.latchMain(); } }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property ShellScreen modelData
            readonly property bool main: modelData === shell.mainScreen
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            // Below windows while the terminal is open, so it shows and takes the keyboard.
            WlrLayershell.layer: Installer.terminal ? WlrLayer.Bottom : WlrLayer.Overlay
            WlrLayershell.keyboardFocus: main && !Installer.terminal && !refocus.running ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            WlrLayershell.namespace: "fledge-installer"
            color: Theme.bg
            Loader { id: content; anchors.fill: parent; active: win.main; focus: true; sourceComponent: Component { Frame {} } }
            Binding { when: win.main; target: shell; property: "focusItem"; value: content.Window.activeFocusItem }
            // The owl's visual centre (between the eyes) is 61.7% across: shift it onto the axis (as the lock does).
            Image {
                visible: !win.main
                anchors { horizontalCenter: parent.horizontalCenter; horizontalCenterOffset: -19; verticalCenter: parent.verticalCenter }
                source: Installer.owl
                width: 160; height: 160; sourceSize.width: 160; fillMode: Image.PreserveAspectFit
                opacity: 0.6
            }
            Shortcut { sequence: "Ctrl+Q"; enabled: Installer.dev; onActivated: Qt.quit() }
            // Back from another VT (Ctrl+Alt+F2 is the root console), Hyprland 0.56
            // re-adds the keyboards but no longer sends their keys to this layer,
            // and may stop showing new frames. Dropping exclusive focus for a
            // moment and taking it again makes it focus the layer anew; a renderer
            // reload brings the picture back. Re-added keyboards announce
            // themselves with "activelayout" (so does Xkb.apply(), skipped here).
            // Qt re-binds its keyboard only after that, and taking focus before
            // then is lost too, so wait a second (nobody types that fast after a
            // VT switch). Qt can come back with no active focus item as well;
            // forcing focus on the scope chain restores the field that had it.
            // A keyboard plugged in also says "activelayout": the same, harmlessly.
            Timer {
                id: settle; interval: 1000
                onTriggered: { Hypr.dispatch('hl.dsp.force_renderer_reload()'); refocus.restart(); }
            }
            Timer { id: refocus; interval: 100; onTriggered: content.forceActiveFocus() }
            Connections {
                target: Hyprland
                function onRawEvent(event) {
                    if (event.name === "activelayout" && win.main && !Installer.dev && Date.now() - Xkb.appliedAt > 3000) settle.restart();
                }
            }
        }
    }
    // Lets tests jump to a step and set answers without a mouse:
    //   qs -p <config> ipc call installer go review
    //   qs -p <config> ipc call installer set username ethan
    IpcHandler {
        target: "installer"
        function go(id: string): void { Installer.step = Installer.indexOf(id); }
        // Only the plain answers: not the passwords (typed, never scripted), not the
        // step state (go, setDisk) and not the internals (terminal, mounts, shown).
        function set(key: string, value: string): string {
            const answers = ["layout", "variant", "timezone", "username", "hostname", "sameLuks", "disk"];
            if (!answers.includes(key)) return "refused: " + key;
            Installer[key] = typeof Installer[key] === "boolean" ? value === "true" : value;
            return "ok";
        }
        function setDisk(path: string): void { Installer.disk = path; Installer.diskConfirmed = true; }
        function next(): void { Installer.next(); }
        function current(): string { return Installer.current; }
        // Not the passwords: any process of this user can call IPC.
        function get(key: string): string {
            return ["password", "password2", "luks", "luks2"].includes(key) ? "refused: secret" : String(Installer[key]);
        }
        // What has the keyboard: the focused item's objectName, or its nearest named
        // ancestor's (an Input's TextInput answers with the Input's label).
        function focused(): string {
            for (let i = shell.focusItem; i; i = i.parent) if (i.objectName !== "") return i.objectName;
            return "";
        }
    }
}
