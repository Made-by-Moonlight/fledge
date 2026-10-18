import Quickshell.Hyprland
import QtQuick
import "../../theme"
import "../../components"

Glyph {
    readonly property string title: Hyprland.activeToplevel?.title ?? ""
    visible: title !== ""
    text: title
    color: Theme.muted
    font.pixelSize: Theme.barFont
    elide: Text.ElideRight
    width: Math.min(implicitWidth, 360)
}
