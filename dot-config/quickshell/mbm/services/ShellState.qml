pragma Singleton
import Quickshell
import Quickshell.Hyprland
import QtQuick

// Which popups are open. Every opener goes through here so only one popup
// holds the keyboard at a time and a pending dmenu is always answered.
Singleton {
    id: root

    property bool barVisible: true
    property bool launcherOpen: false
    property string launcherMode: "apps"
    property bool qsOpen: false
    property string qsPicker: ""
    // A picker only lives while the panel is open: destroying it stops its Wi-Fi scan / BT discovery.
    onQsOpenChanged: if (!qsOpen) qsPicker = ""
    property bool settingsOpen: false
    property string settingsPage: "keybinds"
    property bool recording: false      // the Keybinds page is capturing keys (Escape then cancels, not closes)
    property string recordRequest: ""   // test hook: settings.record(id) asks the Keybinds page to record this bind
    property var dmenu: null
    property bool locked: false
    property bool polkitOpen: false     // the polkit dialog holds the keyboard

    function focusedScreen() {
        const name = Hyprland.focusedMonitor?.name;
        return Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0];
    }

    function closePopups() {
        if (dmenu) dmenuCancel();
        launcherOpen = false;
        qsOpen = false;
    }
    // Nothing opens under the lock: it would sit unseen behind it (and a dmenu caller would wait).
    // Nor over the polkit dialog: a popup would take the keyboard and the password could land in it.
    function openLauncher(mode) {
        if (locked || polkitOpen) return;
        closePopups();
        launcherMode = mode || "apps";
        launcherOpen = true;
    }
    function toggleLauncher(mode) {
        if (launcherOpen && (!mode || mode === launcherMode)) closePopups();
        else openLauncher(mode);
    }
    function openQuickSettings(picker) {
        if (locked || polkitOpen) return;
        closePopups();
        qsPicker = picker || "";
        qsOpen = true;
    }
    function toggleQuickSettings() {
        if (qsOpen) qsOpen = false;
        else openQuickSettings("");
    }
    function openSettings(page) {
        if (locked || polkitOpen) return;
        closePopups();
        settingsPage = page || "keybinds";
        settingsOpen = true;
    }

    // dmenu: `mbm dmenu` waits on resultFile (a FIFO) for "1\n<choice>\n" or "0\n\n".
    function dmenuOpen(req) {
        closePopups();
        dmenu = req;
        if (locked || polkitOpen) { dmenuCancel(); return; }
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
