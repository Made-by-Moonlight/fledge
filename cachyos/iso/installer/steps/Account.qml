import QtQuick
import "../theme"
import "../components"
import "../services"
import "../ui"

// Fields are bound to Installer both ways (state set elsewhere, e.g. over IPC,
// shows here); writing back the same text is a no-op for TextInput.
Column {
    spacing: 14
    Title { text: "Account"; sub: "Your login. The root account stays locked; you'll use sudo." }
    Row {
        spacing: 16
        Input {
            id: user; width: 300; label: "Username"; placeholder: "e.g. ethan"
            error: Installer.err("account", "username")
            onTextChanged: Installer.username = text
            onAccepted: host.focusInput()
            text: Installer.username
        }
        Input {
            id: host; width: 300; label: "Computer name"; placeholder: "e.g. glaux"
            error: Installer.err("account", "hostname")
            onTextChanged: Installer.hostname = text
            onAccepted: pw.focusInput()
            text: Installer.hostname
        }
    }
    Row {
        spacing: 16
        Input {
            id: pw; width: 300; label: "Password"; secret: true
            error: Installer.err("account", "password")
            onTextChanged: Installer.password = text
            onAccepted: pw2.focusInput()
            text: Installer.password
        }
        Input {
            id: pw2; width: 300; label: "Password again"; secret: true
            error: Installer.err("account", "password2")
            onTextChanged: Installer.password2 = text
            onAccepted: Installer.sameLuks ? Installer.next() : luks.focusInput()
            text: Installer.password2
        }
    }
    Toggle {
        label: "Same password for the disk; log in automatically after unlocking it"
        checked: Installer.sameLuks
        onToggled: c => Installer.sameLuks = c
    }
    Row {
        spacing: 16
        visible: !Installer.sameLuks
        Input {
            id: luks; width: 300; label: "Disk passphrase"; secret: true
            error: Installer.err("account", "luks")
            onTextChanged: Installer.luks = text
            onAccepted: luks2.focusInput()
            text: Installer.luks
        }
        Input {
            id: luks2; width: 300; label: "Disk passphrase again"; secret: true
            error: Installer.err("account", "luks2")
            onTextChanged: Installer.luks2 = text
            onAccepted: Installer.next()
            text: Installer.luks2
        }
    }
    Component.onCompleted: user.focusInput()
}
