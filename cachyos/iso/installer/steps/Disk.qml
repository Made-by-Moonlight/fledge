import QtQuick
import "../theme"
import "../components"
import "../services"
import "../ui"
import "../lib/Format.js" as Fmt

// Up/Down pick a disk; Return (or the button) confirms the erase and moves on.
// Picking another disk un-confirms (Installer.onDiskChanged).
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
    function pick(path) {
        Installer.disk = path;
        list.forceActiveFocus();
    }
    function confirm() {
        Installer.diskConfirmed = true;
        Installer.next();
    }
    Keys.onUpPressed: move(-1)
    Keys.onDownPressed: move(1)
    // Handled here so it runs before Frame's Return (plain next(), which would only show the error).
    // A held Return's repeats are swallowed: confirming the erase takes its own press.
    function returnKey(ev) {
        if (ev.isAutoRepeat) return;
        if (Installer.diskInfo) confirm(); else ev.accepted = false;
    }
    Keys.onReturnPressed: ev => returnKey(ev)
    Keys.onEnterPressed: ev => returnKey(ev)
    Column {
        spacing: 14
        Title { text: "Disk"; sub: "The disk you pick is erased completely. USB drives and this installer's own stick aren't listed. ↑ ↓ to choose." }
        // The list takes the focus (its keys reach the page above), and is in the Tab chain so
        // Shift+Tab from the button comes back to the arrow keys. Not the page itself: Qt's
        // Shift+Tab never lands on an ancestor of the item it starts from.
        Column {
            id: list
            spacing: 14
            focus: true
            activeFocusOnTab: true
            objectName: "Disk list"
            Repeater {
                model: page.disks
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool sel: Installer.disk === modelData.path
                    width: 680; height: col.implicitHeight + 24; radius: Theme.radius
                    color: sel ? Theme.accentSoft : Theme.bgRaised
                    border.color: sel ? Theme.accent : "transparent"
                    FocusRing { shown: parent.sel && list.activeFocus }
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
                Row {
                    spacing: 14
                    Button { primary: true; text: "Erase this disk"; onClicked: page.confirm() }
                    Glyph { text: "Return to confirm"; color: Theme.muted; font.pixelSize: Theme.fontSmall; anchors.verticalCenter: parent.verticalCenter }
                }
                Glyph { text: Installer.err("disk", "confirm"); color: Theme.error; font.pixelSize: Theme.fontSmall; visible: text !== "" }
            }
        }
    }
    Component.onCompleted: page.forceActiveFocus()
}
