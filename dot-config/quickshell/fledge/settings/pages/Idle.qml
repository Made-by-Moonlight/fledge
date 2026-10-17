import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "../../components"

// Read live by Idle, so these write without apply.
ColumnLayout {
    id: page
    spacing: 16

    // `check` refuses a lock step before the dim step, so keep the pair valid here instead
    // of letting the write bounce: + on Lock from below dim jumps to the dim time, − below it
    // turns Lock off, and raising Dim past Lock carries Lock along (one write for both).
    function write(key, sec) {
        const dim = Settings.get("idle", "dimSec", 0), lock = Settings.get("idle", "lockSec", 0);
        if (key === "lockSec" && sec > 0 && dim > 0 && sec < dim)
            return Settings.set([[".idle.lockSec", sec > lock ? dim : 0]], false);
        if (key === "dimSec" && sec > 0 && lock > 0 && lock < sec)
            return Settings.set([[".idle.dimSec", sec], [".idle.lockSec", sec]], false);
        Settings.set([[".idle." + key, sec]], false);
    }

    Glyph { text: "Minutes of no input before each step. 0 turns a step off."; color: Theme.muted }
    Repeater {
        model: [["dimSec", "Dim the screen"], ["lockSec", "Lock"], ["screenOffSec", "Turn screens off"], ["suspendSec", "Suspend"]]
        delegate: Stepper {
            required property var modelData
            label: modelData[1]; value: Settings.get("idle", modelData[0], 0) / 60; from: 0; to: 240; suffix: " min"
            onChanged: v => page.write(modelData[0], Math.round(v * 60))
        }
    }
    Glyph { text: "Lock never comes before dim: it starts at the dim time, and goes off below it."; color: Theme.muted; font.pixelSize: Theme.fontSmall }
    Toggle { label: "Lock before sleep"; checked: Settings.lockOnSleep; onToggled: c => Settings.set([[".idle.lockOnSleep", c]], false) }
    // Idle honours Wayland idle inhibitors only; not every app takes one.
    Glyph { text: "Only apps that hold a Wayland idle inhibitor (browsers playing video, mpv) delay these steps; others don't."; color: Theme.muted; font.pixelSize: Theme.fontSmall }
    Item { Layout.fillHeight: true }
}
