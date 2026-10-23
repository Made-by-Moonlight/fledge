import QtQuick
import "../../theme"
import "../../services"
import "../../components"

// Pending updates: " N", hidden when there are none. Hovering spells out what's pending;
// clicking runs `fledge update` in a floating terminal.
Glyph {
    id: root
    visible: Updates.count > 0
    text: "󰚰 " + (mouse.containsMouse ? Updates.summary : Updates.count)
    color: Theme.accent
    font.pixelSize: Theme.barFont
    MouseArea { id: mouse; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; onClicked: Updates.update() }
}
