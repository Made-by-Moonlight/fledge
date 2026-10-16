import QtQuick
import "../theme"
import "../components"
import "../services"

Rectangle {
    color: Theme.bgRaised
    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 36 }
        spacing: 26
        Image {
            source: Installer.owl
            width: 72; height: 72; sourceSize.width: 72; fillMode: Image.PreserveAspectFit
        }
        Column {
            spacing: 2
            Glyph { text: "fledge"; font.pixelSize: Theme.fontLarge; font.bold: true }
            Glyph { text: "made by moonlight"; color: Theme.muted; font.pixelSize: Theme.fontSmall }
        }
        Column {
            spacing: 12
            Repeater {
                model: Installer.steps
                delegate: Row {
                    required property var modelData
                    required property int index
                    readonly property bool cur: index === Installer.step
                    readonly property bool done: index < Installer.step
                    spacing: 12
                    Glyph { width: 16; text: parent.done ? "󰄬" : parent.cur ? "󰧞" : "·"; color: parent.cur || parent.done ? Theme.accent : Theme.muted }
                    Glyph { text: parent.modelData.title; color: parent.cur ? Theme.accent : parent.done ? Theme.fg : Theme.muted; font.bold: parent.cur }
                }
            }
        }
    }
    Button {
        anchors { left: parent.left; bottom: parent.bottom; margins: 36 }
        text: "󰆍  Terminal"
        onClicked: Installer.openTerminal()
    }
}
