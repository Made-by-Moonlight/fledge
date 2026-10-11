pragma Singleton
import Quickshell
import QtQuick

// Confirm-or-revert for a display change. Lives here, not in the Displays page: the page is
// destroyed when the settings window closes or another page is picked, and a countdown that
// died with it would leave an unconfirmed (possibly unusable) layout in place. The timer keeps
// running with the window closed and reverts at zero; only "Keep" in the window stops it.
Singleton {
    id: root
    property var previous: null          // {name, old}: old is the user's entry, or undefined if there was none
    property bool awaiting: false        // the apply write is still queued; the countdown starts when it lands
    property int countdown: 0
    readonly property bool active: previous !== null

    function path(name) { return '.displays["' + name + '"]'; }

    // value: the full entry to write for `name`. Refused while another change waits for its answer.
    function begin(name, value) {
        if (active) return false;
        previous = { name: name, old: Settings.user?.displays?.[name] };
        awaiting = true;
        Settings.set([[path(name), value]], true);
        return true;
    }
    function keep() { tick.stop(); previous = null; awaiting = false; }
    function revert() {
        tick.stop();
        const p = previous;
        previous = null; awaiting = false;
        if (!p) return;
        // set replaces the whole entry (setpath), so no key of the unconfirmed change survives.
        if (p.old === undefined) Settings.reset([path(p.name)], true);
        else Settings.set([[path(p.name), p.old]], true);
    }

    Connections {
        target: Settings
        function onWriteFinished(ok, error) {
            if (!root.awaiting) return;
            root.awaiting = false;
            // check refused it: nothing changed, so there is nothing to confirm or revert.
            if (!ok) root.previous = null;
            else { root.countdown = 15; tick.start(); }
        }
    }
    Timer {
        id: tick
        interval: 1000; repeat: true
        onTriggered: { root.countdown--; if (root.countdown <= 0) root.revert(); }
    }
}
