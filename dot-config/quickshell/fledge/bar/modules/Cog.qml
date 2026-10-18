import QtQuick
import "../../theme"
import "../../services"
import "../../components"

Glyph {
    text: "󰒓"
    color: Theme.accent
    font.pixelSize: Theme.barFontLarge
    MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: ShellState.toggleQuickSettings() }
}
