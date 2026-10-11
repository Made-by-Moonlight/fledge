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
    // The backlight is re-read after each write; show what it really is.
    Connections {
        target: Brightness
        function onApplied() { osd.show("󰃠", "", Brightness.value); }
    }
    IpcHandler {
        target: "osd"
        function volume(arg: string): void {
            if (arg === "mute") {
                const m = Audio.toggleMute();
                if (m === null) return;
                osd.show(m ? "󰝟" : "󰕾", "", m ? 0 : Audio.volume);
            } else if (/^[+-][0-9]+$/.test(arg)) {
                const t = Audio.stepVolume(parseInt(arg) / 100);
                if (t >= 0) osd.show("󰕾", "", t);
            }
        }
        function mic(arg: string): void {
            const m = Audio.toggleMicMute();
            if (m === null) { osd.show("󰍭", "No microphone", -1); return; }
            // keyboard mic-mute LED on laptops; script is vendored until project B
            Quickshell.execDetached(["sh", "-c", 'command -v slievr-brightness-keyboard-mute >/dev/null && slievr-brightness-keyboard-mute "$1"', "sh", m ? "on" : "off"]);
            osd.show(m ? "󰍭" : "󰍬", m ? "Microphone muted" : "Microphone on", -1);
        }
        function brightness(arg: string): void {
            if (Brightness.available && /^([+-][0-9]+|[0-9]+)$/.test(arg)) Brightness.adjust(arg);
        }
        function popup(icon: string, text: string, value: real): void { osd.show(icon, text, value); }
    }
    IpcHandler {
        target: "media"
        function next(): void { Media.next(); }
        function previous(): void { Media.previous(); }
        function playPause(): void { Media.playPause(); }
    }
}
