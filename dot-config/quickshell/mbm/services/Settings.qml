pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Read side: the merged state file written by `mbm settings` (one merge, in the
// CLI). Write side: always through the CLI, so validation lives in one place.
// A file that can't be parsed is ignored and the last good value kept.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string mbm: home + "/.local/share/mbm/bin/mbm"
    property var defaults: ({})
    property var merged: ({})
    property var user: ({})
    property string lastError: ""
    property var queue: []
    property bool inflight: false
    readonly property bool busy: writer.running || queue.length > 0

    function parse(text, fallback, what) {
        try {
            const v = JSON.parse(text);
            if (v && typeof v === "object" && !Array.isArray(v)) return v;
        } catch (e) {}
        console.warn("mbm settings: ignoring unreadable " + what);
        return fallback;
    }

    FileView {
        path: root.home + "/.local/share/mbm/defaults/settings.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.defaults = root.parse(text(), root.defaults, path)
    }
    FileView {
        path: root.home + "/.local/state/mbm/settings.json"
        printErrors: false  // missing on a first boot before `apply`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.merged = root.parse(text(), root.merged, path)
    }
    FileView {
        path: root.home + "/.config/mbm/settings.json"
        printErrors: false  // no user file is the normal state
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.user = root.parse(text(), root.user, path)
        onLoadFailed: root.user = ({})
    }

    // merged → defaults → fallback (merged is empty on a first boot before `apply`).
    function get(section, key, fallback) {
        const m = merged?.[section]?.[key];
        if (m !== undefined) return m;
        const d = defaults?.[section]?.[key];
        return d !== undefined ? d : fallback;
    }

    readonly property var binds: merged.binds ?? defaults.binds ?? ({})
    readonly property string barPosition: get("bar", "position", "top")
    readonly property var barLeft: get("bar", "left", ["workspaces", "title"])
    readonly property var barCentre: get("bar", "centre", ["clock", "media"])
    readonly property var barRight: get("bar", "right", ["tray", "glyphs", "cog"])
    readonly property var barGlyphs: get("bar", "glyphs", ["network", "battery"])
    readonly property string launcherPosition: get("launcher", "position", "centre")
    readonly property string notifCorner: get("notifications", "corner", "top-right")
    readonly property int notifTimeout: get("notifications", "timeoutMs", 5000)
    readonly property int idleDim: get("idle", "dimSec", 0)
    readonly property int idleLock: get("idle", "lockSec", 0)
    readonly property int idleScreenOff: get("idle", "screenOffSec", 0)
    readonly property int idleSuspend: get("idle", "suspendSec", 0)
    readonly property bool lockOnSleep: get("idle", "lockOnSleep", true)

    signal writeFinished(bool ok, string error)

    function set(pairs, apply) {
        const args = [root.mbm, "settings", "set"];
        for (const p of pairs) args.push(p[0], JSON.stringify(p[1]));
        run(args, apply);
    }
    function reset(paths, apply) { run([root.mbm, "settings", "reset", ...paths], apply); }
    // FIFO: every call is one job, run one at a time, each ends in exactly one
    // writeFinished. A rapid second toggle must not be lost.
    function run(args, apply) {
        root.queue = [...root.queue, { command: apply ? ["sh", "-c", '"$@" && "$0" settings apply', root.mbm, ...args] : args }];
        next();
    }
    function next() {
        if (writer.running || root.queue.length === 0) return;
        const job = root.queue[0];
        writer.command = job.command;
        root.inflight = true;
        writer.running = true;
    }
    function finish(ok, error) {
        root.inflight = false;
        root.queue = root.queue.slice(1);
        root.lastError = ok ? "" : error;
        root.writeFinished(ok, root.lastError);
        next();
    }

    Process {
        id: writer
        stderr: StdioCollector { id: writerErr }
        onExited: code => root.finish(code === 0, writerErr.text.trim())
        // A binary that can't start never emits exited, it just drops `running`.
        onRunningChanged: if (!running) Qt.callLater(() => {
            if (root.inflight && !writer.running) root.finish(false, "could not start " + writer.command[0]);
        })
    }
}
