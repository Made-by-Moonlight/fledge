import Quickshell
import QtQuick
import "../../theme"
import "../../services"
import "../../components"

// Status glyphs chosen on the Bar settings page; clicking any opens quick settings.
Item {
    id: root
    readonly property var show: Settings.barGlyphs
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    width: implicitWidth
    height: implicitHeight

    Row {
        id: row
        spacing: 10
        Glyph { visible: root.show.includes("network") && Net.available && Net.present; text: Net.glyph }
        Glyph { visible: root.show.includes("bluetooth") && Bt.available; text: Bt.glyph }
        Glyph { visible: root.show.includes("volume") && Audio.ready; text: Audio.muted ? "󰝟" : Audio.volume > 0.5 ? "󰕾" : "󰖀" }
        Glyph { visible: root.show.includes("battery") && Power.battery; text: Power.glyph + " " + Power.percent + "%"; color: Power.percent <= 15 && !Power.charging ? Theme.error : Theme.fg }
    }
    MouseArea { anchors.fill: parent; onClicked: ShellState.toggleQuickSettings() }
}
