import QtQuick
import "../theme"
import "../components"
import "../services"
import "../ui"
import "../lib/Format.js" as Fmt

// Scrolls: a machine can have more filesystems than fit above the footer.
Flickable {
    clip: true
    contentHeight: content.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    Column {
        id: content
        spacing: 14
        Title {
            text: "Data disks"
            sub: "Tick the disks to mount. They're mounted by UUID at every boot, and a missing disk won't stop the computer starting. Nothing on them is changed."
        }
        Repeater {
            model: Installer.dataRows
            delegate: Row {
                id: row
                required property var modelData
                readonly property var m: Installer.mounts[modelData.uuid] ?? { on: false, path: "" }
                spacing: 16
                Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: row.m.on
                    onToggled: c => Installer.setMount(row.modelData.uuid, c, row.m.path)
                }
                Column {
                    width: 300; anchors.verticalCenter: parent.verticalCenter
                    Glyph { text: (row.modelData.label || row.modelData.uuid.slice(0, 13)) + "   " + row.modelData.fstype + "   " + Fmt.size(row.modelData.size) }
                    Glyph { text: row.modelData.disk; color: Theme.muted; font.pixelSize: Theme.fontSmall }
                }
                Input {
                    width: 320; label: "Mount at"; opacity: row.m.on ? 1 : 0.5
                    error: Installer.err("data", row.modelData.uuid)
                    // Bound both ways, like Account: a Probe refresh that changes the stored
                    // path shows here; writing back the same text is a no-op for TextInput.
                    text: row.m.path
                    onTextChanged: Installer.setMount(row.modelData.uuid, row.m.on, text)
                    onAccepted: Installer.next()
                }
            }
        }
    }
}
