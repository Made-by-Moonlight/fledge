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
// first screen gets the installer, the others the owl. Run by the live ISO's
// Hyprland (/etc/mbm-installer/hyprland.conf); dev: dev/run.sh.
ShellRoot {
    settings.watchFiles: Installer.dev
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property ShellScreen modelData
            readonly property bool main: modelData === Quickshell.screens[0]
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            // Below windows while the terminal is open, so it shows and takes the keyboard.
            WlrLayershell.layer: Installer.terminal ? WlrLayer.Bottom : WlrLayer.Overlay
            WlrLayershell.keyboardFocus: main && !Installer.terminal && !refocus.running ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            WlrLayershell.namespace: "mbm-installer"
            color: Theme.bg
            Loader { id: content; anchors.fill: parent; active: win.main; focus: true; sourceComponent: Component { Frame {} } }
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
            Timer {
                id: settle; interval: 1000
                onTriggered: { Hyprland.dispatch("forcerendererreload"); refocus.restart(); }
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
        function set(key: string, value: string): void {
            Installer[key] = value === "true" ? true : value === "false" ? false : value;
        }
        function setDisk(path: string): void { Installer.disk = path; Installer.diskConfirmed = true; }
        function next(): void { Installer.next(); }
        function current(): string { return Installer.current; }
    }
}
