import QtQuick
import "../theme"
import "../components"
import "../services"
import "../ui"
import "../lib/Format.js" as Fmt

// Up/Down pick a disk (they reach here from the confirm field, which doesn't use them).
FocusScope {
    id: page
    focus: true
    readonly property var disks: Installer.facts?.disks ?? []
    function move(d) {
        if (disks.length === 0) return;
        const i = disks.findIndex(x => x.path === Installer.disk);
        const j = i < 0 ? 0 : Math.max(0, Math.min(disks.length - 1, i + d));
        pick(disks[j].path);
    }
    // A new disk clears the confirm word (Installer.onDiskChanged); the field follows.
    function pick(path) {
        Installer.disk = path;
        confirm.focusInput();
    }
    Keys.onUpPressed: move(-1)
    Keys.onDownPressed: move(1)
    Column {
        spacing: 14
        Title { text: "Disk"; sub: "The disk you pick is erased completely. USB drives and this installer's own stick aren't listed. ↑ ↓ to choose." }
        Repeater {
            model: page.disks
            delegate: Rectangle {
                required property var modelData
                readonly property bool sel: Installer.disk === modelData.path
                width: 680; height: col.implicitHeight + 24; radius: Theme.radius
                color: sel ? Theme.accentSoft : Theme.bgRaised
                border.color: sel ? Theme.accent : "transparent"
                Column {
                    id: col
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 4
                    Glyph {
                        font.bold: true
                        // Model-less disks (virtio) lead with the path instead of repeating it.
                        text: [modelData.model || modelData.path, Fmt.size(modelData.size), modelData.tran,
                               modelData.model ? modelData.path : ""].filter(s => s).join("   ")
                    }
                    Glyph {
                        width: parent.width; wrapMode: Text.WordWrap; color: Theme.muted; font.pixelSize: Theme.fontSmall
                        text: modelData.parts.length === 0 ? "Empty" : modelData.parts.map(p =>
                            p.path.split("/").pop() + " " + (p.fstype || "unknown") + (p.label ? " “" + p.label + "”" : "") + " " + Fmt.size(p.size)).join("    ")
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: page.pick(modelData.path) }
            }
        }
        Glyph { text: Installer.err("disk", "disk"); color: Theme.error; visible: text !== "" }
        Rectangle {
            visible: Installer.diskInfo !== null
            width: 680; height: warn.implicitHeight + 28; radius: Theme.radius
            color: Theme.bgRaised; border.color: Theme.error
            Column {
                id: warn
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 10
                Glyph { text: "Everything on " + Installer.confirmWord + " will be erased."; color: Theme.error; font.bold: true }
                Input {
                    id: confirm; width: 420
                    label: "Type " + Installer.confirmWord + " to confirm"
                    error: Installer.err("disk", "confirm")
                    text: Installer.confirmText
                    onTextChanged: Installer.confirmText = text
                    onAccepted: Installer.next()
                }
            }
        }
    }
    Component.onCompleted: if (Installer.diskInfo) confirm.focusInput(); else page.forceActiveFocus()
}
