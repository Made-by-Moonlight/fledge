import QtQuick
import "../../theme"
import "../../services"
import "../../components"

Glyph {
    text: "󰒓"
    color: Theme.accent
    font.pixelSize: Theme.fontLarge
    MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: ShellState.toggleQuickSettings() }
}
