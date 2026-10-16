import QtQuick
import "../theme"
import "../components"
import "../services"
import "../ui"

Column {
    spacing: 16
    Title { text: "Keyboard"; sub: "Changes right away, so the passwords you type later use it." }
    Row {
        spacing: 16
        SearchList {
            id: layouts
            items: Xkb.layouts; value: Installer.layout; placeholder: "Layout, e.g. gb or German"
            onPicked: v => { Installer.variant = ""; Installer.layout = v; }
            onAccepted: Installer.next()
        }
        SearchList {
            width: 380
            items: [{ value: "", label: "Default" }].concat(Xkb.variants[Installer.layout] ?? [])
            value: Installer.variant; placeholder: "Variant"
            onPicked: v => Installer.variant = v
            onAccepted: Installer.next()
        }
    }
    Input { label: "Try it here"; width: 520; onAccepted: Installer.next() }
    Component.onCompleted: layouts.focusInput()
}
