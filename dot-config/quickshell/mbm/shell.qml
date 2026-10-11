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

ShellRoot {
    // Singletons are lazy; touch Settings now so its files are loaded before the first IPC call or bar paint.
    Component.onCompleted: Settings.home

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
    Connections { target: launcher.systemMode; function onLockRequested() { lockScreen.lock(false); } }
    // Lock before sleep: Sleep holds the delay inhibitor until the lock is secure (or its failsafe fires).
    Connections {
        target: Sleep
        function onPreparingForSleep() {
            if (Settings.lockOnSleep && !lockScreen.secure) lockScreen.lock(true);
            else Sleep.release();
        }
        function onResumed() { Quickshell.execDetached(["hyprctl", "dispatch", "dpms", "on"]); Brightness.refresh(); }
    }
    Connections { target: lockScreen; function onSecureChanged() { if (lockScreen.secure && Sleep.pending) Sleep.release(); } }
    Ipc { osd: osd; lockScreen: lockScreen }
}
