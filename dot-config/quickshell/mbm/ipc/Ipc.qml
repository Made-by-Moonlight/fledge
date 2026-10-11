import Quickshell
import Quickshell.Io
import QtQuick
import "../services"

// IPC targets for binds and scripts: qs -c mbm ipc call <target> <fn> [args].
// Later tasks add their targets here.
Scope {
    property var osd

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
    IpcHandler {
        target: "osd"
        function volume(arg: string): void {
            if (arg === "mute") Audio.toggleMute();
            else Audio.setVolume(Audio.volume + parseInt(arg) / 100);
            osd.show(Audio.muted ? "󰝟" : "󰕾", "", Audio.muted ? 0 : Audio.volume);
        }
        function mic(arg: string): void {
            Audio.toggleMicMute();
            // keyboard mic-mute LED on laptops; script is vendored until project B
            Quickshell.execDetached(["sh", "-c", 'command -v slievr-brightness-keyboard-mute >/dev/null && slievr-brightness-keyboard-mute "$1"', "sh", Audio.micMuted ? "on" : "off"]);
            osd.show(Audio.micMuted ? "󰍭" : "󰍬", Audio.micMuted ? "Microphone muted" : "Microphone on", -1);
        }
        function brightness(arg: string): void {
            if (!Brightness.available) return;
            if (/^[+-]/.test(arg)) Brightness.step(parseInt(arg)); else Brightness.set(parseInt(arg));
            osd.show("󰃠", "", Brightness.value);
        }
        function show(icon: string, text: string, value: real): void { osd.show(icon, text, value); }
    }
    IpcHandler {
        target: "media"
        function next(): void { Media.next(); }
        function previous(): void { Media.previous(); }
        function playPause(): void { Media.playPause(); }
    }
}
