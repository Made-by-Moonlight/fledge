import Quickshell
import Quickshell.Io
import QtQuick
import "../services"

// IPC targets for binds and scripts: qs -c mbm ipc call <target> <fn> [args].
// Later tasks add their targets here.
Scope {
    IpcHandler {
        target: "shell"
        function ping(): string { return "pong"; }
        function setting(section: string, key: string): string { return JSON.stringify(Settings.get(section, key, null)); }
        function state(): string {
            return JSON.stringify({ launcher: ShellState.launcherOpen, mode: ShellState.launcherMode,
                qs: ShellState.qsOpen, picker: ShellState.qsPicker, settings: ShellState.settingsOpen,
                page: ShellState.settingsPage, bar: ShellState.barVisible, dmenu: ShellState.dmenu !== null,
                locked: ShellState.locked });
        }
    }
    IpcHandler {
        target: "bar"
        function toggle(): void { ShellState.barVisible = !ShellState.barVisible; }
    }
}
