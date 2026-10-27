import Quickshell
import Quickshell.Io
import QtQuick
import "../services"

// IPC targets for binds and scripts: qs -c fledge ipc call <target> <fn> [args].
// Later tasks add their targets here.
Scope {
    property var osd
    property var lockScreen
    property var sharePicker
    property var switcher

    IpcHandler {
        target: "shell"
        function ping(): string { return "pong"; }
        function setting(section: string, key: string): string { return JSON.stringify(Settings.get(section, key, null)); }
        function state(): string {
            return JSON.stringify({ launcher: ShellState.launcherOpen, mode: ShellState.launcherMode,
                qs: ShellState.qsOpen, picker: ShellState.qsPicker, settings: ShellState.settingsOpen,
                page: ShellState.settingsPage, bar: ShellState.barVisible, dmenu: ShellState.dmenu !== null,
                locked: ShellState.locked, polkit: ShellState.polkitOpen,
                screenshare: ShellState.shareOpen });
        }
        // The audio picker's app rows, as they read: name, volume (0-1), muted, and the Settings › Apps
        // class the stream maps to ("" for none, null while that is still being worked out).
        function streams(): string {
            return JSON.stringify(Audio.streams.map(n => ({ name: Audio.appName(n), volume: n.audio?.volume ?? null,
                muted: n.audio?.muted ?? null, app: Audio.classOf(n) ?? null })));
        }
        // The bar's updates module: the last `fledge update check`, and asking for a new one
        // (`fledge update` does when it finishes).
        function updates(): string { return JSON.stringify({ count: Updates.count, summary: Updates.summary, checking: Updates.checking }); }
        function recheck(): void { Updates.recheck(); }
    }
    // Booted into a snapshot (services/Recovery.qml): the dialog, and what it knows.
    IpcHandler {
        target: "recovery"
        function state(): string { return JSON.stringify({ snapshot: Recovery.snapshot, open: ShellState.recoveryOpen, run: Recovery.run, when: Recovery.when }); }
        function open(): void { Recovery.show(); }
        function close(): void { Recovery.dismiss(); }
    }
    // `fledge screenshare pick` (lib/screenshare.sh): list is xdph's XDPH_WINDOW_SHARING_LIST,
    // result the FIFO it waits on. "ok", or "busy" while another request is up.
    IpcHandler {
        target: "screenshare"
        function open(list: string, result: string, allowToken: string): string { return sharePicker.open(list, result, allowToken); }
        function close(): void { sharePicker.dismiss(); }
        // Whether the dialog still waits on this FIFO (a restarted shell has lost it).
        function waiting(result: string): bool { return sharePicker.request?.result === result; }
    }
    // The window switcher (switcher/Switcher.qml) is driven by Hyprland's events; this only reports.
    IpcHandler {
        target: "switcher"
        function state(): string {
            return JSON.stringify({ active: switcher.active, shown: switcher.shown, index: switcher.index,
                items: switcher.items.map(t => t.address), mru: switcher.mru });
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
            // keyboard mic-mute LED on laptops (a no-op where there is none)
            Quickshell.execDetached(["fledge", "brightness", "keyboard", "mute", m ? "on" : "off"]);
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
    IpcHandler {
        target: "notifications"
        function dismiss(): void { Notifs.dismissLast(); }
        function dismissAll(): void { Notifs.dismissAll(); }
        function dndToggle(): void { Notifs.toggleDnd(); }
        function invokeLast(): void { Notifs.invokeLast(); }
        function restoreLast(): void { Notifs.restoreLast(); }
        function dismissSummary(summary: string): void { Notifs.dismissSummary(summary); }
        function count(): int { return Notifs.history.length; }
        function popups(): int { return Notifs.popups.length; }
        function dnd(): bool { return Notifs.dnd; }
    }
    IpcHandler {
        target: "launcher"
        function toggle(): void { ShellState.toggleLauncher(""); }
        // Unknown modes (and "dmenu", which only `fledge dmenu` may open) fall back to Apps.
        function open(mode: string): void { ShellState.openLauncher(["apps", "clipboard", "emoji", "system"].includes(mode) ? mode : ""); }
        function close(): void { ShellState.closePopups(); }
    }
    IpcHandler {
        target: "dmenu"
        function open(prompt: string, optionsFile: string, resultFile: string, select: int, inputOnly: bool): void {
            ShellState.dmenuOpen({ prompt, optionsFile, resultFile, select, inputOnly });
        }
        function close(): void { ShellState.dmenuCancel(); }
    }
    IpcHandler {
        target: "quicksettings"
        function toggle(): void { ShellState.toggleQuickSettings(); }
        function open(picker: string): void { ShellState.openQuickSettings(["wifi", "bluetooth", "audio"].includes(picker) ? picker : ""); }
        function close(): void { ShellState.qsOpen = false; }
    }
    IpcHandler {
        target: "lock"
        function lock(): void { lockScreen.lock(false); }
        function status(): string { return lockScreen.locked ? "locked" : "unlocked"; }
    }
    IpcHandler {
        target: "idle"
        function toggle(): void { Idle.toggle(); }
        function status(): string { return Idle.enabled ? "on" : "off"; }
    }
    IpcHandler {
        target: "settings"
        function open(page: string): void { ShellState.openSettings(page); }
        function close(): void { ShellState.settingsOpen = false; }
        // Settings › Apps with this window class's row open (a bind can pass the focused window's).
        function app(cls: string): void {
            ShellState.openSettings("apps");
            if (ShellState.settingsOpen) ShellState.appsExpand = cls;
        }
        function record(id: string): void {
            ShellState.openSettings("keybinds");
            if (ShellState.settingsOpen) ShellState.recordRequest = id;   // refused open (locked, polkit): no silent recording later
        }
    }
}
