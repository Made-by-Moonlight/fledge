pragma Singleton
import Quickshell
import QtQuick

// made by moonlight palette (dot-config/omarchy/current/theme/colors.toml until project C).
Singleton {
    readonly property color bg: "#171e28"
    readonly property color bgRaised: "#212a33"
    readonly property color surface: "#2f3640"
    readonly property color fg: "#ffffff"
    readonly property color fgDim: "#c8ced8"
    readonly property color muted: "#6c7787"
    readonly property color accent: "#f4af03"
    readonly property color error: "#e5626a"
    readonly property color ok: "#8fcf8a"
    readonly property color panel: Qt.rgba(0.090, 0.118, 0.157, 0.94)

    readonly property string font: "JetBrainsMono Nerd Font"
    readonly property int fontSmall: 11
    readonly property int fontSize: 13
    readonly property int fontLarge: 16

    readonly property int radius: 10
    readonly property int radiusLarge: 14
    readonly property int gap: 8
    readonly property int barHeight: 32
    readonly property int anim: 140

    readonly property string assets: Quickshell.env("HOME") + "/.local/share/mbm/assets"
}
