//@ pragma UseQApplication
import Quickshell
import QtQuick
import "wallpaper"
import "ipc"
import "bar"
import "osd"
import "notifications"
import "launcher"
import "services"

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
    Launcher {}
    Ipc { osd: osd }
}
