pragma Singleton
import Quickshell
import Quickshell.Wayland
import QtQuick

// Idle timeouts from mbm settings (seconds, 0 = off; they apply live). Replaces hypridle.
// `enabled` is the session-only "idle lock" toggle (Super+Ctrl+I / System menu): off, no
// timeout fires. Every monitor respects idle inhibitors (a playing video keeps the screen on).
// The lock itself is shell.qml's call (lockRequested): it knows whether we already hold it.
Singleton {
    id: root
    property bool enabled: true
    signal lockRequested()

    // One idle timeout. Quickshell 0.3.2's IdleMonitor ignores a timeout change while it is
    // enabled (it then never reports idle at all), so every change goes: disable, set the
    // timeout, enable. Plain bindings can't promise that order. Disabling while idle reports
    // isIdle false, so a dim or screens-off is undone when its timeout is turned off.
    component Timeout: IdleMonitor {
        property int seconds: 0
        property bool allowed: false    // the toggle (an inline component can't see `root`)
        readonly property bool wanted: allowed && seconds > 0
        enabled: false
        timeout: 0
        respectInhibitors: true
        function sync() { enabled = false; timeout = seconds; enabled = wanted; }
        onSecondsChanged: sync()
        onWantedChanged: sync()
        Component.onCompleted: sync()
    }

    function toggle() {
        enabled = !enabled;
        Quickshell.execDetached(["notify-send", "-u", "low", enabled ? "󱫖    Now locking computer when idle" : "󱫖    Stop locking computer when idle"]);
    }

    // Dim to 10% and restore the exact previous level on activity (no backlight: nothing happens).
    // Brightness.undim() is also called when the monitor is switched off mid-dim, since
    // isIdle drops then too.
    Timeout {
        seconds: Settings.idleDim; allowed: root.enabled
        onIsIdleChanged: if (isIdle) Brightness.dim(10); else Brightness.undim()
    }
    Timeout {
        seconds: Settings.idleLock; allowed: root.enabled
        onIsIdleChanged: if (isIdle) root.lockRequested()
    }
    // Screens off; any input wakes them (and the lock, resume and unlock turn them on too).
    Timeout {
        seconds: Settings.idleScreenOff; allowed: root.enabled
        onIsIdleChanged: Quickshell.execDetached(["hyprctl", "dispatch", "dpms", isIdle ? "off" : "on"])
    }
    // Lock-before-sleep is Sleep's job (logind PrepareForSleep), not this one's.
    Timeout {
        seconds: Settings.idleSuspend; allowed: root.enabled
        onIsIdleChanged: if (isIdle) Quickshell.execDetached(["systemctl", "suspend"])
    }
}
