import QtQuick
import "../theme"
import "../components"
import "../services"
import "../ui"
import "../lib/Format.js" as Fmt
import "../lib/Drives.js" as D

// Scrolls: many data disks make the list taller than the space above the footer.
Flickable {
    id: review
    clip: true
    contentHeight: content.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    readonly property var f: Installer.facts
    // The data drives to be erased too, each on its own red row after the target's.
    readonly property var erased: Installer.dataDrives.filter(d => Installer.wiped.split("\n").includes(d.path))
    readonly property var ticked: Installer.dataRows.filter(r => Installer.mounts[r.uuid]?.on)
    // The installer logs in automatically when the two match, ticked or typed twice.
    readonly property bool sameSecret: Installer.sameLuks || (Installer.luks !== "" && Installer.luks === Installer.password)
    readonly property var rows: [
        ["Keyboard", Installer.layout + (Installer.variant ? " (" + Installer.variant + ")" : ""), "keyboard"],
        ["Timezone", Installer.timezone, "region"],
        ["Account", Installer.username + "  ·  root locked", "account"],
        ["Computer name", Installer.hostname, "account"],
        ["Disk unlock", sameSecret ? "Same as your password, then straight to the desktop" : "Its own passphrase, then the login screen", "account"],
        ["Erase", Installer.confirmWord + "  ·  " + (Installer.diskInfo ? Fmt.size(Installer.diskInfo.size) : "") + "  ·  " + Installer.disk, "disk"]
    ].concat(erased.map(d => ["Erase", D.name(d) + "  ·  " + Fmt.size(d.size) + "  ·  " + d.path + "  →  " + Installer.wipes[d.path].path, "data"]), [
        ["Data disks", ticked.length === 0 ? "None" : ticked.map(r => (r.label || r.uuid.slice(0, 13)) + "  →  " + Installer.mounts[r.uuid].path).join("\n"),
         Installer.dataDrives.length > 0 ? "data" : ""],
        ["Microcode", f?.ucode ?? "", ""],
        ["Graphics", f?.gpu || "generic (Mesa)", ""],
        ["Memory", f ? f.memMiB + " MiB  ·  zram " + f.zramMiB + " MiB  ·  hibernate swap " + f.swapMiB + " MiB" : "", ""]
    ])
    Column {
        id: content
        spacing: 14
        Title { text: "Review"; sub: "Nothing has changed yet. Erase and install starts the install." }
        Repeater {
            model: review.rows
            delegate: Row {
                required property var modelData
                spacing: 16
                Glyph { width: 160; text: modelData[0]; color: Theme.muted }
                Glyph { width: 480; text: modelData[1]; wrapMode: Text.WordWrap; color: modelData[0] === "Erase" ? Theme.error : Theme.fg }
                Glyph {
                    visible: modelData[2] !== ""; text: "Edit"; color: Theme.accent
                    MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: Installer.edit(modelData[2]) }
                }
            }
        }
    }
}
