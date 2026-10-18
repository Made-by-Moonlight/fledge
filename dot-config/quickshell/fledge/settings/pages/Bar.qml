import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "../../components"

// Bar layout, launcher and notifications. All read live by the shell, so no apply.
Flickable {
    id: page
    contentHeight: col.implicitHeight; clip: true
    readonly property var allModules: ["workspaces", "title", "clock", "media", "tray", "glyphs", "cog"]
    readonly property var sides: [["left", "Left section"], ["centre", "Centre section"], ["right", "Right section"]]
    function list(side) { return side === "left" ? Settings.barLeft : side === "centre" ? Settings.barCentre : Settings.barRight; }
    function save(side, mods) { Settings.set([[".bar." + side, mods]], false); }
    function setHeight(h) { if (h !== Settings.barHeight) Settings.set([[".bar.height", h]], false); }
    function move(side, i, to) {
        const from = list(side).slice(), m = from.splice(i, 1)[0];
        if (to === side) return;
        const dest = list(to).slice(); dest.push(m);
        Settings.set([[".bar." + side, from], [".bar." + to, dest]], false);
    }
    readonly property var unused: allModules.filter(m => ![...Settings.barLeft, ...Settings.barCentre, ...Settings.barRight].includes(m))

    ColumnLayout {
        id: col
        width: page.width; spacing: 14

        Repeater {
            model: page.sides
            delegate: Column {
                id: sec
                required property var modelData
                Layout.fillWidth: true
                spacing: 6
                Glyph { text: sec.modelData[1]; color: Theme.muted; font.pixelSize: Theme.fontSmall }
                Flow {
                    width: sec.width; spacing: 6
                    Repeater {
                        model: page.list(sec.modelData[0])
                        delegate: Pill {
                            id: chip
                            required property string modelData
                            required property int index
                            readonly property string side: sec.modelData[0]
                            color: Theme.surface; height: 30; width: r.implicitWidth + 16
                            Row {
                                id: r; anchors.centerIn: parent; spacing: 8
                                Glyph { text: "‹"; visible: chip.side !== "left"; MouseArea { anchors.fill: parent; onClicked: page.move(chip.side, chip.index, chip.side === "right" ? "centre" : "left") } }
                                Glyph { text: chip.modelData + (chip.modelData === "cog" ? " (quick settings)" : "") }
                                Glyph { text: "›"; visible: chip.side !== "right"; MouseArea { anchors.fill: parent; onClicked: page.move(chip.side, chip.index, chip.side === "left" ? "centre" : "right") } }
                                Glyph { text: "✕"; color: Theme.muted; MouseArea { anchors.fill: parent; onClicked: { const l = page.list(chip.side).slice(); l.splice(chip.index, 1); page.save(chip.side, l); } } }
                            }
                        }
                    }
                }
            }
        }
        Column {
            spacing: 6; visible: page.unused.length > 0
            Glyph { text: "Add to the right section"; color: Theme.muted; font.pixelSize: Theme.fontSmall }
            Flow { width: col.width; spacing: 6
                Repeater { model: page.unused
                    delegate: Button { required property string modelData; text: "+ " + modelData; onClicked: page.save("right", [...Settings.barRight, modelData]) } } }
        }
        Column {
            spacing: 6
            Glyph { text: "Status glyphs"; color: Theme.muted; font.pixelSize: Theme.fontSmall }
            Flow {
                width: col.width; spacing: 20
                Repeater {
                    model: [["network", "Network"], ["bluetooth", "Bluetooth"], ["volume", "Volume"], ["battery", "Battery"]]
                    delegate: Toggle {
                        required property var modelData
                        label: modelData[1]; checked: Settings.barGlyphs.includes(modelData[0])
                        onToggled: c => Settings.set([[".bar.glyphs", c ? [...Settings.barGlyphs, modelData[0]] : Settings.barGlyphs.filter(g => g !== modelData[0])]], false)
                    }
                }
            }
        }
        Flow {
            Layout.fillWidth: true; spacing: 24
            Choice { label: "Bar position"; value: Settings.barPosition; options: [["top", "Top"], ["bottom", "Bottom"]]
                     onPicked: v => Settings.set([[".bar.position", v]], false) }
            Choice { label: "Clock format (click the clock to cycle)"; value: Settings.clockFormat
                     readonly property var now: new Date()
                     options: [[0, Qt.formatDateTime(now, "HH:mm  ddd d MMM").toLowerCase()], [1, Qt.formatDateTime(now, "HH:mm")],
                               [2, Qt.formatDateTime(now, "HH:mm:ss  dddd d MMMM yyyy").toLowerCase()], [3, Qt.formatDateTime(now, "hh:mm ap  ddd d MMM").toLowerCase()]]
                     onPicked: v => Settings.set([[".bar.clockFormat", v]], false) }
            Choice { label: "Launcher position"; value: Settings.launcherPosition; options: [["centre", "Centre"], ["anchored", "Under the bar's left section"]]
                     onPicked: v => Settings.set([[".launcher.position", v]], false) }
            Choice { label: "Notifications"; value: Settings.notifCorner
                     options: [["top-right", "Top right"], ["top-left", "Top left"], ["bottom-right", "Bottom right"], ["bottom-left", "Bottom left"]]
                     onPicked: v => Settings.set([[".notifications.corner", v]], false) }
            Column {
                spacing: 6
                Glyph { text: "Bar height"; color: Theme.muted; font.pixelSize: Theme.fontSmall }
                Row {
                    spacing: 12
                    Slider {
                        width: 200; anchors.verticalCenter: parent.verticalCenter
                        value: (Settings.barHeight - 20) / 28
                        onMoved: v => page.setHeight(Math.round(20 + v * 28))
                        onStepped: d => page.setHeight(Math.max(20, Math.min(48, Settings.barHeight + d)))
                    }
                    Glyph { text: Settings.barHeight + " px"; anchors.verticalCenter: parent.verticalCenter }
                }
            }
            Stepper { label: "Notification timeout"; value: Settings.notifTimeout / 1000; from: 1; to: 60; suffix: " s"
                      onChanged: v => Settings.set([[".notifications.timeoutMs", Math.round(v * 1000)]], false) }
        }
    }
}
