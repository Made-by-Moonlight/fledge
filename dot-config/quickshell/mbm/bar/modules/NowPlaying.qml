import QtQuick
import "../../theme"
import "../../services"
import "../../components"

Glyph {
    visible: Media.player !== null
    text: (Media.playing ? "󰏤 " : "󰐊 ") + (Media.player?.trackTitle ?? "")
    color: Theme.fgDim
    elide: Text.ElideRight
    width: Math.min(implicitWidth, 260)
    MouseArea { anchors.fill: parent; onClicked: Media.playPause() }
}
