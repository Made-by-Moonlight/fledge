//@ pragma UseQApplication
import Quickshell
import QtQuick
import "wallpaper"
import "ipc"
import "bar"
import "osd"
import "notifications"
import "launcher"
import "quicksettings"
import "services"
import "lock"
import "polkit"
import "settings"

ShellRoot {
    // No live reload when a QML file changes (a git pull or restow under a locked screen).
    // Restart the shell to pick up changes; the lock also survives a reload on its own (Lock.qml).
    settings.watchFiles: false
    // Singletons are lazy; touch Settings now so its files are loaded before the first IPC call or bar paint.
    // DisplayConfirm too: at startup it reverts a display change the last shell never got confirmed.
    // A shell that died while recording a key left Hyprland in the empty mbm-record submap,
    // where no bind fires: leave it.
    Component.onCompleted: {
        Settings.home; DisplayConfirm.active;
        Quickshell.execDetached(["sh", "-c", '[ "$(hyprctl submap 2>/dev/null)" = mbm-record ] && exec hyprctl dispatch submap reset']);
    }

    Variants {
        model: Quickshell.screens
        Scope {
            id: perScreen
            required property ShellScreen modelData
            Wallpaper { screen: perScreen.modelData }
            Bar { screen: perScreen.modelData }
        }
    }
    Osd { id: osd }
    Popups {}
    Lock { id: lockScreen }
    Launcher { id: launcher }
    QuickSettings {}
    PolkitDialog {}
    SettingsWindow {}
    Connections { target: launcher.systemMode; function onLockRequested() { lockScreen.lock(false); } }
    Connections { target: launcher.systemMode; function onIdleToggleRequested() { Idle.toggle(); } }
    // Idle lock only when nothing holds the lock (lock() while locked is a no-op anyway, and
    // while another locker has taken over (lost) the session is locked).
    // true: no forced screens-off after it; idle.screenOffSec decides that.
    Connections {
        target: Idle
        function onLockRequested() { if (!lockScreen.locked && !lockScreen.lost && !lockScreen.secure) lockScreen.lock(true); }
    }
    // Lock before sleep: Sleep holds the delay inhibitor until the lock is secure (or its failsafe fires).
    Connections {
        target: Sleep
        function onPreparingForSleep() {
            // A lock we already hold is trusted: release the inhibitor straight away.
            if (Settings.lockOnSleep && !lockScreen.secure) lockScreen.lock(true);
            else Sleep.release();
        }
        function onResumed() { Quickshell.execDetached(["hyprctl", "dispatch", "dpms", "on"]); Brightness.refresh(); }
    }
    Connections { target: lockScreen; function onSecureChanged() { if (lockScreen.secure && Sleep.pending) Sleep.release(); } }
    Ipc { osd: osd; lockScreen: lockScreen }
}
