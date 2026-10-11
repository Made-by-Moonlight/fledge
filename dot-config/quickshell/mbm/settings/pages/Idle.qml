import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "../../components"

// Read live by Idle, so these write without apply. `check` refuses lock < dim; the window's banner says why.
ColumnLayout {
    spacing: 16
    Glyph { text: "Minutes of no input before each step. 0 turns a step off."; color: Theme.muted }
    Repeater {
        model: [["dimSec", "Dim the screen"], ["lockSec", "Lock"], ["screenOffSec", "Turn screens off"], ["suspendSec", "Suspend"]]
        delegate: Stepper {
            required property var modelData
            label: modelData[1]; value: Settings.get("idle", modelData[0], 0) / 60; from: 0; to: 240; suffix: " min"
            onChanged: v => Settings.set([[".idle." + modelData[0], Math.round(v * 60)]], false)
        }
    }
    Toggle { label: "Lock before sleep"; checked: Settings.lockOnSleep; onToggled: c => Settings.set([[".idle.lockOnSleep", c]], false) }
    // Idle honours Wayland idle inhibitors only; not every app takes one.
    Glyph { text: "Video in browsers and mpv keeps the screen on; some apps may not."; color: Theme.muted; font.pixelSize: Theme.fontSmall }
    Item { Layout.fillHeight: true }
}
