pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../lib/Progress.js" as P

// Runs mbm-install (or dev/replay.sh), reads its @@mbm markers into stage
// state, keeps the log. Exit 3 = only the Desktop stage failed.
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
                                     : ["sudo", "-n", "/usr/local/bin/mbm-install"];
        proc.running = true;
    }
    function retryDesktop() {
        // current is still the failed "desktop": cleared, so the retry's first
        // stage marker doesn't mark it done before it has run.
        state = "running"; failedStage = ""; current = ""; n = 0; m = 0; pending = "";
        proc.command = Installer.dev ? ["bash", Installer.repo + "/cachyos/iso/installer/dev/replay.sh", "--desktop-only"]
                                     : ["sudo", "-n", "/usr/local/bin/mbm-install", "--desktop-only", Installer.username];
        proc.running = true;
    }
    property var afterCleanup: null
    function cleanup(after) {
        afterCleanup = after ?? null;
        cleanProc.running = true;
    }
    function reboot() {
        if (Installer.dev) { Qt.quit(); return; }
        Quickshell.execDetached(["sudo", "-n", "/usr/bin/reboot"]);
    }

    Process {
        id: proc
        stdinEnabled: true
        onStarted: if (r.pending !== "") { write(r.pending); r.pending = ""; }
        stdout: SplitParser { onRead: line => r.handle(line) }
        stderr: SplitParser { onRead: line => r.push(line) }
        onExited: code => {
            r.state = code === 0 ? "done" : code === 3 ? "desktopFailed" : "failed";
            if (code !== 0 && r.failedStage === "") r.failedStage = r.current || "prepare";
        }
    }
    Process {
        id: cleanProc
        command: Installer.dev ? ["true"] : ["sudo", "-n", "/usr/local/bin/mbm-cleanup"]
        stderr: SplitParser { onRead: line => r.push(line) }
        onExited: code => {
            if (code !== 0) { r.push("mbm-cleanup failed (exit " + code + ")"); return; }
            r.state = "idle";
            const f = r.afterCleanup; r.afterCleanup = null;
            if (f) f();
        }
    }
}
