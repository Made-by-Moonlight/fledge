import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import QtQuick
import "../services"

// Session lock (ext-session-lock via WlSessionLock) with PAM service mbm-lock.
// Fail-safe by construction: the only thing that ever sets the lock target to unlocked is
// finishUnlock(), and its only caller is PamContext reporting Success. No timer, error or
// takeover drives it there. Errors, aborts, a hung conversation
// or a crash all leave the session locked (the compositor keeps it locked when the
// client dies; with misc:allow_session_lock_restore a restarted shell re-locks from the flag).
// The lock target lives in PersistentProperties, so a Quickshell reload while locked builds
// the new WlSessionLock already locked: the old lock object is dropped without unlocking
// (Hyprland keeps the session locked) and the new one re-locks, which needs
// misc:allow_session_lock_restore. shell.qml also turns file-watch reloads off.
Scope {
    id: root
    // The typed password lives only in `secret.text`. It is a field of a plain JS object,
    // so writing it emits no change signal and nothing (surfaces, IPC) can bind to it;
    // the surfaces see only `typed`, its length. It is handed to PAM once and wiped
    // straight after, and on every failure, lock and unlock. Never log it.
    readonly property var secret: ({ text: "" })
    property int typed: 0
    property string status: ""        // "", "checking", "failed"
    property string note: ""          // PAM's own info/error text (e.g. faillock's lockout notice)
    property int attempts: 0
    property bool answered: false     // this attempt's password prompt has been answered
    readonly property bool secure: wl.secure
    // `held`: the current lock object has been granted. Hyprland lets another locker replace
    // ours (allow_session_lock_restore) and tells the replaced client nothing: secure stays
    // true. So a granted lock is never trusted to still be ours: an explicit lock() while held
    // re-acquires (see lock()). `lost` covers a compositor that does report it (secure drops
    // while we hold the lock).
    property bool held: false
    property bool lost: false
    // Not a binding to wl.locked: Quickshell 0.3.2 doesn't emit lockStateChanged on release.
    readonly property bool locked: persist.locked && !lost
    readonly property string flagDir: Quickshell.env("HOME") + "/.local/state/mbm"
    readonly property string flagPath: flagDir + "/locked"
    readonly property string instance: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? ""
    // Set by mbm-shell.service. Not INVOCATION_ID: Hyprland runs as a uwsm unit, so a qs it
    // execs (the dev loop) inherits Hyprland's INVOCATION_ID without being supervised.
    readonly property bool supervised: Quickshell.env("MBM_SHELL_SUPERVISED") === "1"
    signal unlockedNow()

    Binding { target: ShellState; property: "locked"; value: root.locked }

    function wipe() { secret.text = ""; typed = 0; }
    function type(ch) {
        if (pam.active) return;           // no typing into an attempt in flight
        secret.text += ch;
        typed = secret.text.length;
        if (status === "failed") status = "";
    }
    function backspace() { if (!pam.active) { secret.text = secret.text.slice(0, -1); typed = secret.text.length; } }
    function clear() { if (!pam.active) wipe(); }

    function lock(fromSleep) {
        if (persist.locked && !held && !lost) return;   // the grant is still in flight
        ShellState.closePopups();               // popups give up the keyboard; a waiting dmenu gets "cancel"
        wipe(); status = ""; note = ""; attempts = 0;
        if (persist.locked) {
            // Re-acquire without ever asking for an unlock. Quickshell 0.3.2 can't do it in
            // process: the old lock object can only be released by unlocking it, a second
            // WlSessionLock is refused ("Failed to acquire session lock") while it exists, and a
            // reload hands the old object to the new generation. So restart the process: its
            // lock object dies with it (if it is still the session's lock, Hyprland keeps the
            // session locked), and the new shell locks from the relock flag, rewritten here
            // (blockWrites: it is on disk before exit). Under mbm-shell.service, exit 1 makes
            // systemd restart it (and a spare would race that restart, then die with the cgroup).
            // Unsupervised (the dev loop), a spare start takes its place; -n stops a duplicate.
            writeFlag();
            console.warn("mbm lock: re-acquiring the session lock by restarting the shell");
            if (!root.supervised)
                Quickshell.execDetached(["setsid", "-f", "sh", "-c", "sleep 1; exec qs -c mbm -n"]);
            Qt.exit(1);
            return;
        }
        persist.locked = true;                  // wl.locked follows
        writeFlag();
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "0"]);
        Quickshell.execDetached(["sh", "-c", "pgrep -x 1password >/dev/null && exec 1password --lock"]);
        if (!fromSleep) displayOff.restart();
    }
    function submit() {
        if (!persist.locked || pam.active || secret.text === "") return;
        status = "checking"; note = ""; answered = false;
        watchdog.restart();
        if (!pam.start()) fail("could not start authentication");
    }
    function fail(message) {
        watchdog.stop();
        wipe();
        if (status === "checking") attempts++;
        status = "failed";
        if (message) note = message;
    }
    function finishUnlock() {
        watchdog.stop();
        displayOff.stop();
        wipe();
        held = false; lost = false;
        persist.locked = false;                 // wl.locked follows: the lock is released here and only here
        status = ""; note = ""; attempts = 0;
        Quickshell.execDetached(["hyprctl", "dispatch", "dpms", "on"]);
        // Cleared only after unlocking: a crash in between re-locks, which is the safe side.
        writeFlag();
        unlockedNow();
    }
    function trackSecure(s) {
        if (s) { held = true; lost = false; }
        else if (held && persist.locked) {
            held = false; lost = true;
            console.warn("mbm lock: another locker took over the session lock; the next lock() re-acquires");
        }
    }

    // The relock flag holds the Hyprland instance signature while locked and is empty otherwise.
    // Every write goes through FileView (atomic, in order, and its cached text stays true), so a
    // clear can never land after a newer lock's write. Writes wait for the state dir.
    function writeFlag() {
        if (!dirReady || instance === "") return;
        flag.setText(persist.locked ? instance + "\n" : "");
    }

    // Like slievr-system-lock: screens off shortly after a manual lock (any key wakes them: misc:key_press_enables_dpms).
    Timer { id: displayOff; interval: 3000; onTriggered: if (persist.locked) Quickshell.execDetached(["hyprctl", "dispatch", "dpms", "off"]) }
    // A PAM module that never answers would otherwise block every retry.
    Timer { id: watchdog; interval: 30000; onTriggered: if (pam.active) { pam.abort(); root.fail("authentication timed out"); } }

    PersistentProperties {
        id: persist
        reloadableId: "mbm-lock-state"
        property bool locked: false
    }

    property bool dirReady: false
    property bool flagChecked: false
    Process {
        running: true
        command: ["mkdir", "-p", root.flagDir]
        onExited: { root.dirReady = true; if (root.flagChecked) root.writeFlag(); }
    }
    FileView {
        id: flag
        path: root.flagPath
        atomicWrites: true
        blockWrites: true
        printErrors: false      // no flag is the normal state
        // Only the first load decides: later loads are our own writes coming back.
        onLoaded: {
            if (root.flagChecked) return;
            root.flagChecked = true;
            const sig = text().trim();
            if (sig !== "" && sig === root.instance) root.lock(true);
            // Empty, or left by another (ended) Hyprland session: it must not lock this one.
            else root.writeFlag();
        }
        onLoadFailed: { root.flagChecked = true; root.writeFlag(); }
    }

    PamContext {
        id: pam
        config: "mbm-lock"
        onPamMessage: {
            if (responseRequired) {
                // One prompt per attempt. A second one (e.g. "new password" for an expired
                // account) can't be answered from here: give up the attempt, stay locked.
                if (root.answered) { abort(); root.fail("unsupported authentication prompt"); return; }
                root.answered = true;
                respond(root.secret.text);
                root.wipe();
            } else if (message !== "") {
                // Modules may send several lines (faillock: reason, then time left): keep them all.
                root.note = root.note ? root.note + "\n" + message : message;
            }
        }
        onCompleted: result => {
            if (result === PamResult.Success) root.finishUnlock();
            else root.fail(result === PamResult.MaxTries ? "too many attempts" : "");
        }
        onError: error => root.fail("authentication error")
    }

    WlSessionLock {
        id: wl
        reloadableId: "mbm-session-lock"
        locked: persist.locked
        onSecureChanged: root.trackSecure(secure)
        // One surface per screen, including screens added while locked.
        LockSurface { lockRoot: root }
    }
}
