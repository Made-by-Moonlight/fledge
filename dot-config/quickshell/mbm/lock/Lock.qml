import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import QtQuick
import "../services"

// Session lock (ext-session-lock via WlSessionLock) with PAM service mbm-lock.
// Fail-safe by construction: the only path to unlock is finishUnlock(), and the only
// caller of that is PamContext reporting Success. Errors, aborts, a hung conversation
// or a crash all leave the session locked (the compositor keeps it locked when the
// client dies; with misc:allow_session_lock_restore a restarted shell re-locks from the flag).
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
    // Our own flag, not a binding to wl.locked: Quickshell 0.3.2 doesn't emit lockStateChanged
    // when a lock is released, so a binding stays true after unlocking (direct reads are right).
    property bool locked: false
    readonly property bool secure: wl.secure
    readonly property string flagDir: Quickshell.env("HOME") + "/.local/state/mbm"
    readonly property string flagPath: flagDir + "/locked"
    readonly property string instance: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? ""
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
        if (wl.locked) return;
        ShellState.closePopups();               // popups give up the keyboard; a waiting dmenu gets "cancel"
        wipe(); status = ""; note = ""; attempts = 0;
        wl.locked = true;
        locked = wl.locked;
        if (!locked) { console.warn("mbm lock: the compositor refused the session lock"); return; }
        // A restarted shell re-locks from this, in the same Hyprland session only.
        if (instance !== "") flag.setText(instance);
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "0"]);
        Quickshell.execDetached(["sh", "-c", "pgrep -x 1password >/dev/null && exec 1password --lock"]);
        if (!fromSleep) displayOff.restart();
    }
    function submit() {
        if (!wl.locked || pam.active || secret.text === "") return;
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
        wl.locked = false;
        locked = wl.locked;
        status = ""; note = ""; attempts = 0;
        Quickshell.execDetached(["hyprctl", "dispatch", "dpms", "on"]);
        // Removed only after unlocking: a crash in between re-locks, which is the safe side.
        Quickshell.execDetached(["rm", "-f", flagPath]);
        unlockedNow();
    }

    // Like slievr-system-lock: screens off shortly after a manual lock (any key wakes them: misc:key_press_enables_dpms).
    Timer { id: displayOff; interval: 3000; onTriggered: if (wl.locked) Quickshell.execDetached(["hyprctl", "dispatch", "dpms", "off"]) }
    // A PAM module that never answers would otherwise block every retry.
    Timer { id: watchdog; interval: 30000; onTriggered: if (pam.active) { pam.abort(); root.fail("authentication timed out"); } }

    FileView {
        id: flag
        path: root.flagPath
        atomicWrites: true
        printErrors: false      // no flag is the normal state
        onLoaded: {
            if (root.locked) return;
            const sig = text().trim();
            if (sig !== "" && sig === root.instance) root.lock(true);
            // Left by another (ended) Hyprland session: it must not lock this one, now or later.
            else Quickshell.execDetached(["rm", "-f", root.flagPath]);
        }
    }
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", flagDir])

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
                root.note = message;
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
        // Picks up a lock the compositor ends or refuses (secure drops); see `locked` above.
        onSecureChanged: root.locked = locked
        // One surface per screen, including screens added while locked.
        LockSurface { lockRoot: root }
    }
}
