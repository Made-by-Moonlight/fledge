//@ pragma UseQApplication
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "components"
import "services"
import "theme"
import "ui"

// The fledge installer (made by moonlight): one full-screen layer per monitor; the
// monitor Hyprland has focused at startup gets the installer, the others the
// owl and a button to move it there (Ctrl+M: to the next screen). Run by the live ISO's Hyprland (/etc/fledge-installer/hyprland.lua); dev:
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
    // A monitor mounted on its side still reports a landscape mode, so the live ISO
    // shows it sideways, and nothing tells us which way up a screen sits: when
    // Hyprland's first pick is the sideways one, the person moves the installer.
    function useScreen(name) {
        if (Quickshell.screens.some(s => s.name === name)) mainName = name;
    }
    function nextScreen() {
        const all = Quickshell.screens;
        if (all.length < 2) return;
        useScreen(all[(all.indexOf(mainScreen) + 1) % all.length].name);
    }
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
                id: owl
                visible: !win.main
                anchors { horizontalCenter: parent.horizontalCenter; horizontalCenterOffset: -19; verticalCenter: parent.verticalCenter }
                source: Installer.owl
                width: 160; height: 160; sourceSize.width: 160; fillMode: Image.PreserveAspectFit
                opacity: 0.6
            }
            Column {
                visible: !win.main
                anchors { horizontalCenter: parent.horizontalCenter; top: owl.bottom; topMargin: 4 * Theme.gap }
                spacing: 1.5 * Theme.gap
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Install on this screen"; primary: true
                    onClicked: shell.useScreen(win.modelData.name)
                }
                Glyph {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "or press Ctrl+M to move the installer to the next screen"
                    color: Theme.muted; font.pixelSize: Theme.fontSmall
                }
            }
            Shortcut { sequence: "Ctrl+Q"; enabled: Installer.dev; onActivated: Qt.quit() }
            Shortcut { sequence: "Ctrl+M"; enabled: win.main; onActivated: shell.nextScreen() }
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
        // The screen the installer is on, and the owl screen's button.
        function screen(): string { return shell.mainScreen ? shell.mainScreen.name : ""; }
        function useScreen(name: string): string { shell.useScreen(name); return shell.mainName; }
        // What has the keyboard: the focused item's objectName, or its nearest named
        // ancestor's (an Input's TextInput answers with the Input's label).
        function focused(): string {
            for (let i = shell.focusItem; i; i = i.parent) if (i.objectName !== "") return i.objectName;
            return "";
        }
    }
}
