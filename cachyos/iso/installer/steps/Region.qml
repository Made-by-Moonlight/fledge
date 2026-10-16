import QtQuick
import "../theme"
import "../components"
import "../services"
import "../ui"

Column {
    spacing: 16
    Title { text: "Region"; sub: "Sets the clock. Type a city or region." }
    SearchList {
        id: z
        items: Zones.zones.map(s => ({ value: s, label: s.replace(/_/g, " ") }))
        value: Installer.timezone; placeholder: "e.g. London"
        onPicked: v => Installer.timezone = v
        onAccepted: Installer.next()
    }
    Glyph { text: Zones.preview ? "Local time there: " + Zones.preview : ""; color: Theme.muted }
    Component.onCompleted: z.focusInput()
}
