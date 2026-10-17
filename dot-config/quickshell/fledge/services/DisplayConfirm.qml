pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Confirm-or-revert for a display change. Lives here, not in the Displays page: the page is
// destroyed when the settings window closes or another page is picked, and a countdown that
// died with it would leave an unconfirmed (possibly unusable) layout in place. The timer keeps
// running with the window closed and reverts at zero; only "Keep" in the window stops it.
// The pending revert is also written to disk before the change, so a shell that crashes or is
// killed mid-countdown reverts it at its next start (shell.qml touches `active` at startup).
Singleton {
    id: root
    property var previous: null          // {name, old}: old is the user's entry, or undefined if there was none
    property int awaiting: 0             // id of the queued apply job; the countdown starts when it lands
    property int countdown: 0
    property int revertJob: 0
    property string refusal: ""          // why the change failed, shown again once its revert is done
    readonly property bool active: previous !== null
    readonly property string pendingFile: Settings.home + "/.local/state/fledge/display-pending.json"

    function path(name) { return '.displays["' + name + '"]'; }

    // A shell job (queued with the settings writes, so it keeps their order). `sh -c` gets the
    // file as $1 and the text as $2; the write is atomic (temp + mv).
    function savePending(p) {
        Settings.run(["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf %s "$2" >"$1.tmp" && mv "$1.tmp" "$1"', "sh", pendingFile,
                      JSON.stringify({ name: p.name, old: p.old, deadline: Date.now() + 15000 })], false);
    }
    function clearPending() { return Settings.run(["rm", "-f", pendingFile], false); }

    // value: the full entry to write for `name`, or undefined to remove the user's entry (Reset).
    // Refused while another change waits for its answer.
    function begin(name, value) {
        if (active) return false;
        previous = { name: name, old: Settings.user?.displays?.[name] };
        savePending(previous);
        awaiting = value === undefined ? Settings.reset([path(name)], true) : Settings.set([[path(name), value]], true);
        return true;
    }
    function keep() { tick.stop(); previous = null; awaiting = 0; clearPending(); }
    function revert() { undo(previous); }
    function undo(p) {
        tick.stop();
        previous = null; awaiting = 0;
        if (!p) return;
        // set replaces the whole entry (setpath), so no key of the unconfirmed change survives.
        if (p.old === undefined) Settings.reset([path(p.name)], true); else Settings.set([[path(p.name), p.old]], true);
        revertJob = clearPending();   // the last job queued: when it lands the revert is done
    }

    Connections {
        target: Settings
        function onWriteFinished(ok, error, id) {
            if (root.revertJob !== 0 && id === root.revertJob) {
                root.revertJob = 0;
                // The revert's own success cleared the error that explains why the change was refused.
                if (root.refusal !== "") { Settings.lastError = root.refusal; root.refusal = ""; }
                return;
            }
            if (root.awaiting === 0 || id !== root.awaiting) return;
            root.awaiting = 0;
            if (ok) { root.countdown = 15; tick.start(); return; }
            // `set` writes the user file before `apply` runs, so a failed apply (or a hung reload)
            // can leave the change on disk. Revert always: it does nothing harmful if `set` was refused.
            root.refusal = error !== "" ? error : "Applying the display change failed, so it was reverted.";
            root.revert();
        }
    }
    Timer {
        id: tick
        interval: 1000; repeat: true
        onTriggered: { root.countdown--; if (root.countdown <= 0) root.revert(); }
    }

    // A pending file at startup means the shell died before the change was kept: revert now.
    FileView {
        path: root.pendingFile
        printErrors: false
        onLoaded: {
            try {
                const p = JSON.parse(text());
                if (p?.name) root.undo({ name: p.name, old: p.old });
            } catch (e) { root.clearPending(); }
        }
    }
}
