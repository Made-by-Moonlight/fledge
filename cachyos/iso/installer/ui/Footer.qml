import QtQuick
import "../theme"
import "../components"
import "../services"

Item {
    height: 44
    visible: Installer.current !== "install"
    Row {
        anchors.right: parent.right
        spacing: 10
        Button { text: "Back"; visible: Installer.step > 0; onClicked: Installer.back() }
        Button {
            primary: true
            text: Installer.current === "welcome" ? "Install" : Installer.current === "review" ? "Erase and install" : "Next"
            enabled: Installer.valid(Installer.current) || !Installer.shown[Installer.current]
            onClicked: Installer.next()
        }
    }
}
