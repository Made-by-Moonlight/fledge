import QtQuick
import "../theme"
import "../components"
import "../services"

Column {
    spacing: 18
    Image {
        source: Installer.owl
        width: 150; height: 150; sourceSize.width: 150; fillMode: Image.PreserveAspectFit
    }
    Column {
        spacing: 6
        Glyph { text: "f l e d g e"; font.pixelSize: 30; font.bold: true }
        Glyph { text: "made by moonlight"; color: Theme.muted }
    }
    Glyph { text: "CachyOS · Hyprland · encrypted btrfs"; color: Theme.muted }
    Glyph {
        width: 600; wrapMode: Text.WordWrap; color: Theme.fgDim
        text: "This installs fledge on one disk of this computer and erases that disk. Nothing changes until you confirm on the Review page."
    }
    Glyph { visible: !Probe.facts; text: "Looking at this machine…"; color: Theme.muted }
    Rectangle {
        visible: Probe.facts?.leftover ?? false
        width: 600; height: leftCol.implicitHeight + 28; radius: Theme.radius
        color: Theme.bgRaised; border.color: Theme.error
        Column {
            id: leftCol
            anchors { fill: parent; margins: 14 }
            spacing: 10
            Glyph { width: parent.width; wrapMode: Text.WordWrap; text: "A previous install attempt is still open: its disk is mounted or unlocked." }
            Button { text: "Clean up"; onClicked: Run.cleanup(() => Probe.refresh()) }
        }
    }
}
