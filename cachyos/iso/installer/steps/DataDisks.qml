import QtQuick
import "../theme"
import "../components"
import "../services"
import "../ui"
import "../lib/Format.js" as Fmt
import "../lib/Drives.js" as D

// A card per drive besides the target: Leave alone, Mount (its filesystems'
// rows) or Wipe (erased into fresh storage once its button is pressed). Each
// card's choice is in the Tab chain, Left/Right pick; the fields of the picked
// choice follow it. Scrolls: a machine can have more drives than fit above the
// footer, and the focused field is kept in view.
Flickable {
    id: page
    clip: true
    contentHeight: content.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    // lsblk's TYPE (probe.jq's busy), as the card says it.
    readonly property var busyAs: ({ lvm: "LVM", raid: "RAID", crypt: "an open LUKS volume", swap: "swap", mounted: "a mounted filesystem" })
    function reveal(item) {
        let i = item;
        while (i && i !== content) i = i.parent;
        if (!i) return;
        const y = item.mapToItem(content, 0, 0).y;
        const max = Math.max(0, contentHeight - height);
        if (y < contentY) contentY = Math.max(0, y - 14);
        else if (y + item.height > contentY + height) contentY = Math.min(max, y + item.height - height + 14);
    }
    Connections {
        target: page.Window.window
        function onActiveFocusItemChanged() { page.reveal(page.Window.activeFocusItem); }
    }
    Column {
        id: content
        spacing: 14
        Title {
            text: "Data disks"
            sub: "Mounted drives are left as they are. Wiped drives are erased when the install starts."
        }
        Repeater {
            model: Installer.dataDrives
            delegate: Rectangle {
                id: card
                required property var modelData
                readonly property string path: modelData.path
                readonly property string name: D.name(modelData)
                readonly property string pick: Installer.choice(path)
                readonly property var w: Installer.wipes[path] ?? { on: false, path: "", label: "", confirmed: false }
                // From facts, not dataRows: a wiped drive's rows leave dataRows, and
                // Mount has to stay on offer to go back to.
                readonly property bool mountable: (Installer.facts?.datafs ?? []).some(f => f.disk === path)
                width: 680; height: col.implicitHeight + 24; radius: Theme.radius
                color: Theme.bgRaised
                border.color: pick === "wipe" ? Theme.error : "transparent"
                Column {
                    id: col
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 10
                    Column {
                        width: parent.width
                        spacing: 4
                        Row {
                            spacing: 12
                            Glyph { id: head; font.bold: true; text: [card.name, Fmt.size(card.modelData.size), D.kindName(card.modelData.kind)].join("   ") }
                            Glyph { text: card.path; color: Theme.muted; anchors.baseline: head.baseline }
                        }
                        Glyph {
                            width: parent.width; wrapMode: Text.WordWrap; color: Theme.muted; font.pixelSize: Theme.fontSmall
                            text: card.modelData.parts.length === 0 ? "Empty" : card.modelData.parts.map(p =>
                                p.path.split("/").pop() + " " + (p.fstype || "unknown") + (p.label ? " “" + p.label + "”" : "") + " " + Fmt.size(p.size)).join("    ")
                        }
                    }
                    Choice {
                        // Named after the drive, not by its (empty) label: tests ask what has the focus.
                        objectName: card.name + " choice"
                        options: [["leave", "Leave alone"]]
                            .concat(card.mountable ? [["mount", "Mount"]] : [])
                            .concat(card.modelData.busy ? [] : [["wipe", "Wipe"]])
                        value: card.pick
                        onPicked: v => Installer.setChoice(card.path, v)
                    }
                    Glyph {
                        visible: !!card.modelData.busy
                        text: "In use as " + (page.busyAs[card.modelData.busy] ?? card.modelData.busy) + " here, can't be wiped"
                        color: Theme.muted; font.pixelSize: Theme.fontSmall
                    }
                    // Mount: the drive's filesystems, ticked by hand (or by profile.sh).
                    Repeater {
                        model: card.pick === "mount" ? Installer.dataRows.filter(r => r.disk === card.path) : []
                        delegate: Row {
                            id: row
                            required property var modelData
                            readonly property string rowName: row.modelData.label || row.modelData.uuid.slice(0, 13)
                            readonly property var m: Installer.mounts[modelData.uuid] ?? { on: false, path: "" }
                            spacing: 16
                            Toggle {
                                objectName: "Mount " + row.rowName
                                anchors.verticalCenter: parent.verticalCenter
                                checked: row.m.on
                                onToggled: c => Installer.setMount(row.modelData.uuid, c, row.m.path)
                            }
                            Column {
                                width: 240; anchors.verticalCenter: parent.verticalCenter
                                Glyph { text: row.rowName + "   " + row.modelData.fstype + "   " + Fmt.size(row.modelData.size) }
                            }
                            Input {
                                width: 320; label: "Mount at"; opacity: row.m.on ? 1 : 0.5
                                error: Installer.err("data", row.modelData.uuid)
                                // Bound to the stored path, so a Probe refresh shows here;
                                // only typing (edited) marks it as the person's.
                                text: row.m.path
                                onEdited: t => Installer.setMount(row.modelData.uuid, row.m.on, t, true)
                                onAccepted: Installer.next()
                            }
                        }
                    }
                    // Wipe: where the fresh storage goes, its label, and the erase to confirm.
                    Column {
                        visible: card.pick === "wipe"
                        width: parent.width
                        spacing: 10
                        Glyph { text: "Everything on " + card.name + " will be erased."; color: Theme.error; font.bold: true }
                        Row {
                            spacing: 16
                            // Bound to the suggestion until typed; writing back the same text is
                            // a no-op (setWipePath), and the label follows the folder until typed.
                            Input {
                                width: 320; label: "Mount at"
                                error: Installer.err("data", "wipe:" + card.path)
                                text: card.w.path
                                onEdited: t => Installer.setWipePath(card.path, t)
                                onAccepted: Installer.next()
                            }
                            Input {
                                width: 200; label: "Label"
                                error: Installer.err("data", "label:" + card.path)
                                text: card.w.label
                                onEdited: t => Installer.setWipeLabel(card.path, t)
                                onAccepted: Installer.next()
                            }
                        }
                        Row {
                            spacing: 14
                            // Button takes Space and Return itself (held repeats ignored), so
                            // Return here confirms rather than trying the next step.
                            Button { primary: true; text: "Erase this drive"; onClicked: Installer.confirmWipe(card.path) }
                            Glyph {
                                text: card.w.confirmed ? "Confirmed" : "Return to confirm"
                                color: Theme.muted; font.pixelSize: Theme.fontSmall; anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        Glyph { text: Installer.err("data", "confirm:" + card.path); color: Theme.error; font.pixelSize: Theme.fontSmall; visible: text !== "" }
                    }
                }
            }
        }
    }
}
