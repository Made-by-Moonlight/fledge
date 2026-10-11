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
    readonly property bool busy: writer.running

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
    readonly property var barCentre: get("bar", "centre", ["clock"])
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
    function run(args, apply) {
        if (writer.running) return;
        writer.command = apply ? ["sh", "-c", '"$@" && "$0" settings apply', root.mbm, ...args] : args;
        writer.running = true;
    }

    Process {
        id: writer
        stderr: StdioCollector { id: writerErr }
        onExited: code => {
            root.lastError = code === 0 ? "" : writerErr.text.trim();
            root.writeFinished(code === 0, root.lastError);
        }
    }
}
