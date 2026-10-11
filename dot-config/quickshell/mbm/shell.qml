//@ pragma UseQApplication
import Quickshell
import QtQuick
import "wallpaper"
import "ipc"
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
        }
    }
    Ipc {}
}
