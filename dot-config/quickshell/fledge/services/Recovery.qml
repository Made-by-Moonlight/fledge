pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Booted into a snapper snapshot (Limine › Snapshots, after an update went wrong): which one,
// from /proc/cmdline, and what fledge update recorded about it (~/.local/state/fledge/update.json,
// in /home, so the snapshot still sees it). The dialog (recovery/RecoveryDialog.qml) opens once
// per boot; "Not now" is remembered in $XDG_RUNTIME_DIR until the next one. Restoring is
// `fledge update recover` in a terminal: limine-snapper-restore needs root and asks on a tty.
// FLEDGE_CMDLINE stands in for /proc/cmdline (tests: the service's environment).
Singleton {
    id: root

    readonly property string stateFile: Settings.home + "/.local/state/fledge/update.json"
    readonly property string seenFile: Quickshell.env("XDG_RUNTIME_DIR") + "/fledge-snapshot-seen"
    property string cmdline: ""
    property var runs: []
    property bool seen: false
    property bool open: false

    // The snapshot number, or -1 on a normal boot.
    readonly property int snapshot: {
        const m = cmdline.match(/subvol=\/?@\/\.snapshots\/(\d+)\/snapshot/);
        return m ? parseInt(m[1]) : -1;
    }
    readonly property var run: runs.find(r => r.snapshot === snapshot) ?? null
    // How that update ended, as `fledge update` words it (update_how).
    readonly property string how: {
        const r = run?.result ?? "";
        if (r === "running") return "didn't finish";
        if (r.startsWith("failed: ")) return "failed (" + r.slice(8) + ")";
        if (r.startsWith("interrupted: ")) return "was stopped (" + r.slice(13) + ")";
        return r === "ok" ? "finished" : r;
    }
    // "23 Oct at 21:24", from snapper's "2026-10-23 21:24:26".
    readonly property string when: {
        const m = (run?.date ?? "").match(/^(\d+)-(\d+)-(\d+) (\d+:\d+)/);
        if (!m) return "";
        const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        return parseInt(m[3]) + " " + months[parseInt(m[2]) - 1] + " at " + m[4];
    }

    function show() { if (snapshot >= 0) open = true; }
    function dismiss() {
        open = false;
        Quickshell.execDetached(["touch", seenFile]);
        seen = true;
    }
    function restore() {
        open = false;
        Quickshell.execDetached(["fledge", "launch", "floating", "terminal", "with", "presentation", "fledge update recover"]);
    }

    FileView {
        path: Quickshell.env("FLEDGE_CMDLINE") || "/proc/cmdline"
        onLoaded: root.cmdline = text()
    }
    FileView {
        path: root.stateFile
        printErrors: false  // no update has run yet
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.runs = JSON.parse(text()).runs ?? []; } catch (e) { root.runs = []; } }
    }
    FileView {
        path: root.seenFile
        printErrors: false
        onLoaded: root.seen = true
    }
    // Once the files are in: a moment after start, so the session is up behind it.
    Timer {
        interval: 3000; running: true
        onTriggered: if (root.snapshot >= 0 && !root.seen) root.show()
    }
}
