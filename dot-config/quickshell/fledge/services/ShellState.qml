pragma Singleton
import Quickshell
import Quickshell.Hyprland
import QtQuick
import "../settings/Layout.js" as Geom
import "Main.js" as Main

// Which popups are open. Every opener goes through here so only one popup
// holds the keyboard at a time and a pending dmenu is always answered.
Singleton {
    id: root

    property bool barVisible: true
    property bool launcherOpen: false
    property string launcherMode: "apps"
    property bool qsOpen: false
    property string qsPicker: ""
    property var qsScreen: null         // where quick settings opens: the clicked bar's screen
    // A picker only lives while the panel is open: destroying it stops its Wi-Fi scan / BT discovery.
    onQsOpenChanged: if (!qsOpen) qsPicker = ""
    property bool settingsOpen: false
    property string settingsPage: "keybinds"
    property bool recording: false      // the Keybinds page is capturing keys (Escape then cancels, not closes)
    property string recordRequest: ""   // test hook: settings.record(id) asks the Keybinds page to record this bind
    property string appsExpand: ""      // settings.app(class) asks the Apps page to open that app's row
    property var dmenu: null
    property bool locked: false
    property bool polkitOpen: false     // the polkit dialog holds the keyboard
    property bool shareOpen: false      // so does the screen-share picker
    property bool recoveryOpen: false   // and the "running a snapshot" dialog
    readonly property bool dialogOpen: polkitOpen || shareOpen || recoveryOpen

    function focusedScreen() {
        const name = Hyprland.focusedMonitor?.name;
        return Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0];
    }

    // The main monitor (bar.main, else the top-left one) and which monitors show a bar.
    // Keys as Displays writes them: Layout.js keyFor, the connector when that has a quote or backslash.
    readonly property var monitors: Hyprland.monitors.values.map(m => {
        const v = Geom.keyFor(m, Hyprland.monitors.values);
        return { key: /["\\]/.test(v) ? m.name : v, name: m.name, x: m.x, y: m.y };
    })
    readonly property string mainKey: Main.pick(monitors, Settings.barMain)
    readonly property var mainScreen: {
        const name = monitors.find(m => m.key === mainKey)?.name;
        return Quickshell.screens.find(s => s.name === name) ?? focusedScreen();
    }
    function keyOfScreen(screen) { return monitors.find(m => m.name === screen?.name)?.key ?? ""; }
    // A screen Hyprland doesn't list yet keeps its bar until it does.
    function showsBar(screen) {
        const key = keyOfScreen(screen);
        return key === "" || Main.showsBar(key, monitors, Settings.barMain, Settings.barHidden);
    }

    function closePopups() {
        if (dmenu) dmenuCancel();
        launcherOpen = false;
        qsOpen = false;
    }
    // Nothing opens under the lock: it would sit unseen behind it (and a dmenu caller would wait).
    // Nor over the polkit dialog or the share picker: a popup would take the keyboard (and a
    // password could land in it).
    function openLauncher(mode) {
        if (locked || dialogOpen) return;
        closePopups();
        launcherMode = mode || "apps";
        launcherOpen = true;
    }
    function toggleLauncher(mode) {
        if (launcherOpen && (!mode || mode === launcherMode)) closePopups();
        else openLauncher(mode);
    }
    // screen: the bar clicked. Without one (a keybind, the launcher) the focused monitor
    // when it shows a bar, else the main one: quick settings hangs under a bar's cog.
    function openQuickSettings(picker, screen) {
        if (locked || dialogOpen) return;
        closePopups();
        qsScreen = screen ?? (showsBar(focusedScreen()) ? focusedScreen() : mainScreen);
        qsPicker = picker || "";
        qsOpen = true;
    }
    // Open on another bar's screen moves it there; on the same screen closes it.
    function toggleQuickSettings(screen) {
        if (qsOpen && (!screen || screen === qsScreen)) qsOpen = false;
        else openQuickSettings("", screen);
    }
    function openSettings(page) {
        if (locked || dialogOpen) return;
        closePopups();
        settingsPage = page || "keybinds";
        settingsOpen = true;
    }

    // dmenu: `fledge dmenu` waits on resultFile (a FIFO) for "1\n<choice>\n" or "0\n\n".
    function dmenuOpen(req) {
        closePopups();
        dmenu = req;
        if (locked || dialogOpen) { dmenuCancel(); return; }
        launcherMode = "dmenu";
        launcherOpen = true;
    }
    function dmenuFinish(ok, value) {
        const req = dmenu;
        dmenu = null;
        launcherOpen = false;
        if (!req) return;
        // Bounded: if the caller died, nothing reads the FIFO and a bare redirect would block forever.
        Quickshell.execDetached(["timeout", "2", "sh", "-c", 'printf "%s\\n%s\\n" "$1" "$2" > "$3"', "sh", ok ? "1" : "0", value ?? "", req.resultFile]);
    }
    function dmenuCancel() { dmenuFinish(false, ""); }
}
