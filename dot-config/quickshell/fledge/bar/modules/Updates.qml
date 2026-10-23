import QtQuick
import "../../theme"
import "../../services"
import "../../components"

// Pending updates: "󰚰 N", hidden when there are none. Hovering spells out what's pending;
// clicking runs `fledge update` in a floating terminal. Booted into a snapshot it says so
// instead, the whole time, and clicking brings the recovery dialog back.
Glyph {
    id: root
    readonly property bool onSnapshot: Recovery.snapshot >= 0
    visible: onSnapshot || Updates.count > 0
    text: onSnapshot ? "󰁯 snapshot " + Recovery.snapshot
        : "󰚰 " + (mouse.containsMouse ? Updates.summary : Updates.count)
    color: onSnapshot ? Theme.error : Theme.accent
    font.pixelSize: Theme.barFont
    MouseArea {
        id: mouse
        anchors.fill: parent; anchors.margins: -6; hoverEnabled: true
        onClicked: root.onSnapshot ? Recovery.show() : Updates.update()
    }
}
