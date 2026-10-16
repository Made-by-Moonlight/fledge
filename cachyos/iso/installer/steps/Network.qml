import QtQuick
import "../theme"
import "../components"
import "../services"
import "../ui"
import "../quicksettings/pickers"

Column {
    spacing: 16
    Title { text: "Network"; sub: "The install downloads packages, so it needs the internet." }
    Glyph { text: Probe.online ? "󰄬  Connected" : "Not connected yet"; color: Probe.online ? Theme.ok : Theme.muted }
    Glyph { text: Net.wired ? "󰈀  Wired: connected" : "󰈂  No wired connection"; color: Theme.fgDim }
    Rectangle {
        width: 560; height: 440; radius: Theme.radius; color: Theme.bgRaised
        WifiPicker { anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 } }
    }
}
