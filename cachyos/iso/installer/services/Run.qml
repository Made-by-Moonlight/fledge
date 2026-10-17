pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../lib/Progress.js" as P

// Runs fledge-install (or dev/replay.sh), reads its @@fledge markers into stage
// state, keeps the log. Exit 3 = only the Desktop stage failed.
// state: idle, running, done, desktopFailed, failed, rebooting.
Singleton {
    id: r
    readonly property var stages: [["prepare", "Prepare"], ["disk", "Partition & encrypt"], ["base", "Base system"],
        ["config", "Configure"], ["boot", "Bootloader"], ["desktop", "Desktop"], ["finish", "Finish"]]
    property string state: "idle"
    property string current: ""
    property var doneStages: ({})
    property string failedStage: ""
    property int n: 0
    property int m: 0
    property var log: []
    readonly property real progress: P.fraction(stages.map(s => s[0]), doneStages, current, n, m)
    property string pending: ""          // answers, written once the process has started

    function stageState(id) {
        if (doneStages[id]) return "done";
        if (failedStage === id) return "failed";
        if (current === id && state === "running") return "running";
        return "waiting";
    }
    function mark(id) { if (!id) return; const d = Object.assign({}, doneStages); d[id] = true; doneStages = d; }
    function push(line) { const l = log.concat([line]); log = l.length > 500 ? l.slice(-500) : l; }
    function handle(line) {
        const k = P.parse(line);
        if (!k) { push(line); return; }
        if (k.kind === "stage") { mark(current); current = k.id; n = 0; m = 0; }
        else if (k.kind === "count") { n = k.n; m = k.m; }
        // The installer can only name the stage it set itself; a failure inside the
        // chroot's Bootloader stage arrives as "config", which already looks done.
        else if (k.kind === "fail") failedStage = doneStages[k.id] ? current : k.id;
        else if (k.kind === "done") { mark(current); current = ""; }
    }

    function start(text) {
        state = "running"; current = ""; doneStages = ({}); failedStage = ""; n = 0; m = 0; log = [];
        pending = text;
        proc.command = Installer.dev ? ["bash", Installer.repo + "/cachyos/iso/installer/dev/replay.sh"]
                                     : ["sudo", "-n", "/usr/local/bin/fledge-install"];
        proc.running = true;
    }
    function retryDesktop() {
        // current is still the failed "desktop": cleared, so the retry's first
        // stage marker doesn't mark it done before it has run.
        state = "running"; failedStage = ""; current = ""; n = 0; m = 0; pending = "";
        proc.command = Installer.dev ? ["bash", Installer.repo + "/cachyos/iso/installer/dev/replay.sh", "--desktop-only"]
                                     : ["sudo", "-n", "/usr/local/bin/fledge-install", "--desktop-only", Installer.username];
        proc.running = true;
    }
    property var afterCleanup: null
    property bool cleanupForce: false   // run afterCleanup even if fledge-cleanup fails
    property string cleanupError: ""    // shown by Welcome and Installing
    function cleanup(after, force) {
        afterCleanup = after ?? null;
        cleanupForce = force ?? false;
        cleanupError = "";
        cleanProc.running = true;
    }
    // Once only: the countdown, Return and the button can all ask.
    property bool rebootSent: false
    function reboot() {
        if (rebootSent) return;
        rebootSent = true;
        state = "rebooting";
        if (Installer.dev) { Qt.quit(); return; }
        Quickshell.execDetached(["sudo", "-n", "/usr/bin/reboot"]);
    }
    // After a Desktop failure the system is installed: tidy up if possible, but
    // reboot regardless (systemd unmounts and closes LUKS on the way down).
    function rebootAnyway() {
        state = "rebooting";
        cleanup(() => reboot(), true);
    }

    Process {
        id: proc
        stdinEnabled: true
        onStarted: if (r.pending !== "") { write(r.pending); r.pending = ""; }
        stdout: SplitParser { onRead: line => r.handle(line) }
        stderr: SplitParser { onRead: line => r.push(line) }
        // Exit codes only mean something on a normal exit. Killed by a signal
        // (QProcess::CrashExit, 1) is a failure whatever the code says.
        onExited: (code, status) => {
            const ok = status !== 1 && code === 0;
            r.state = ok ? "done" : status !== 1 && code === 3 ? "desktopFailed" : "failed";
            if (!ok && r.failedStage === "") r.failedStage = r.current || "prepare";
        }
    }
    Process {
        id: cleanProc
        command: Installer.dev ? ["true"] : ["sudo", "-n", "/usr/local/bin/fledge-cleanup"]
        stderr: SplitParser { onRead: line => r.push(line) }
        onExited: code => {
            const f = r.afterCleanup, force = r.cleanupForce;
            r.afterCleanup = null; r.cleanupForce = false;
            if (code !== 0) {
                r.cleanupError = "Cleaning up failed (fledge-cleanup exit " + code + "). Open a terminal to see what is still mounted or unlocked.";
                r.push("fledge-cleanup failed (exit " + code + ")");
                if (force && f) f();
                return;
            }
            if (r.state !== "rebooting") r.state = "idle";
            if (f) f();
        }
    }
}
