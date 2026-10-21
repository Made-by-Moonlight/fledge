pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Read side: the merged state file written by `fledge settings` (one merge, in the
// CLI). Write side: always through the CLI, so validation lives in one place.
// A file that can't be parsed is ignored and the last good value kept.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string fledge: home + "/.local/share/fledge/bin/fledge"
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
        console.warn("fledge settings: ignoring unreadable " + what);
        return fallback;
    }

    FileView {
        path: root.home + "/.local/share/fledge/defaults/settings.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.defaults = root.parse(text(), root.defaults, path)
    }
    FileView {
        path: root.home + "/.local/state/fledge/settings.json"
        printErrors: false  // missing on a first boot before `apply`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.merged = root.parse(text(), root.merged, path)
    }
    FileView {
        path: root.home + "/.config/fledge/settings.json"
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
    // Out-of-range or non-integer values (a hand-edited file `settings check` would reject) keep the default.
    readonly property int barHeight: { const h = get("bar", "height", 32); return Number.isInteger(h) && h >= 20 && h <= 48 ? h : 32; }
    readonly property int clockFormat: get("bar", "clockFormat", 0)
    readonly property var barLeft: get("bar", "left", ["workspaces", "title"])
    readonly property var barCentre: get("bar", "centre", ["clock", "media"])
    readonly property var barRight: get("bar", "right", ["tray", "glyphs", "cog"])
    readonly property var barGlyphs: get("bar", "glyphs", ["network", "battery"])
    // Monitor keys (Layout.js keyFor): the main monitor, and the monitors whose bar is off.
    readonly property string barMain: { const m = get("bar", "main", ""); return typeof m === "string" ? m : ""; }
    readonly property var barHidden: { const h = get("bar", "hidden", []); return Array.isArray(h) ? h.filter(k => typeof k === "string") : []; }
    readonly property string launcherPosition: get("launcher", "position", "centre")
    readonly property string notifCorner: get("notifications", "corner", "top-right")
    readonly property int notifTimeout: get("notifications", "timeoutMs", 5000)
    readonly property int idleDim: get("idle", "dimSec", 0)
    readonly property int idleLock: get("idle", "lockSec", 0)
    readonly property int idleScreenOff: get("idle", "screenOffSec", 0)
    readonly property int idleSuspend: get("idle", "suspendSec", 0)
    readonly property bool lockOnSleep: get("idle", "lockOnSleep", true)
    readonly property string wallpaperImage: get("wallpaper", "image", "")
    readonly property var wallpaperMonitors: get("wallpaper", "monitors", ({}))
    // The image for one screen: its own entry (by connector or desc:<description>), else the
    // shared one; "" is the shipped Moonrise art. A monitor entry of "moonrise" means Moonrise
    // on that monitor even when the shared image is something else (no entry = follow the shared one).
    // A leading ~/ is the home directory.
    function wallpaperFor(name, description) {
        const m = wallpaperMonitors ?? {};
        const p = m[name] ?? (description ? m["desc:" + description] : undefined) ?? wallpaperImage;
        if (typeof p !== "string" || p === "moonrise") return "";
        return p.startsWith("~/") ? home + p.slice(1) : p;
    }

    // `id` is the job id set()/reset() returned, so a caller can tell its own write from the others queued.
    signal writeFinished(bool ok, string error, int id)
    property int lastId: 0

    function set(pairs, apply) {
        const args = [root.fledge, "settings", "set"];
        for (const p of pairs) args.push(p[0], JSON.stringify(p[1]));
        return run(args, apply);
    }
    function reset(paths, apply) { return run([root.fledge, "settings", "reset", ...paths], apply); }
    // set, then reset, then apply as ONE job (one writeFinished): a page that
    // saves some keys and drops others must not see a half-written file between
    // two jobs. An empty paths list is a plain set.
    function setReset(pairs, paths, apply) {
        const set = [];
        for (const p of pairs) set.push(p[0], JSON.stringify(p[1]));
        if (paths.length === 0) return run([root.fledge, "settings", "set", ...set], apply);
        // sh -c with $0 = the CLI; arguments are single-quoted into the script.
        const q = a => "'" + String(a).replace(/'/g, "'\\''") + "'";
        // `set` with no pairs is a usage error, so it is left out then.
        let script = (set.length ? '"$0" settings set ' + set.map(q).join(" ") + ' && ' : '') + '"$0" settings reset ' + paths.map(q).join(" ");
        if (apply) script += ' && "$0" settings apply';
        const id = ++root.lastId;
        root.queue = [...root.queue, { id: id, command: ["sh", "-c", script, root.fledge] }];
        next();
        return id;
    }
    // FIFO: every call is one job, run one at a time, each ends in exactly one
    // writeFinished. A rapid second toggle must not be lost.
    function run(args, apply) {
        const id = ++root.lastId;
        root.queue = [...root.queue, { id: id, command: apply ? ["sh", "-c", '"$@" && "$0" settings apply', root.fledge, ...args] : args }];
        next();
        return id;
    }
    function next() {
        if (writer.running || root.queue.length === 0) return;
        const job = root.queue[0];
        writer.command = job.command;
        root.inflight = true;
        writer.running = true;
    }
    function finish(ok, error) {
        const id = root.queue[0]?.id ?? 0;
        root.inflight = false;
        root.queue = root.queue.slice(1);
        root.lastError = ok ? "" : error;
        root.writeFinished(ok, root.lastError, id);
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
