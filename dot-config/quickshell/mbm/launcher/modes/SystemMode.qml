import Quickshell
import QtQuick
import "../Fuzzy.js" as Fuzzy
import "../../services"

Item {
    readonly property string name: "system"
    readonly property string label: "System"
    readonly property string placeholder: "Power, settings, menus…"
    function sh(cmd) { return () => Quickshell.execDetached(["sh", "-c", cmd]); }
    readonly property var actions: [
        { text: "Lock", glyph: "󰌾", run: () => lockRequested() },
        { text: "Suspend", glyph: "󰒲", run: sh("systemctl suspend") },
        { text: "Reboot", glyph: "󰜉", run: sh("systemctl reboot") },
        { text: "Shut down", glyph: "󰐥", run: sh("systemctl poweroff") },
        { text: "Log out", glyph: "󰍃", run: sh("uwsm stop") },
        { text: "Settings", glyph: "", run: () => ShellState.openSettings("") },
        { text: "Quick settings", glyph: "󰒓", run: () => ShellState.openQuickSettings("") },
        { text: "Toggle do not disturb", glyph: "󰂛", run: () => Notifs.toggleDnd() },
        { text: "Toggle idle lock", glyph: "󱫖", run: () => idleToggleRequested() },
        // Omarchy-era menus, kept reachable until project B replaces them.
        { text: "Capture…", glyph: "󰄀", sub: "screenshot, recording, colour", run: sh("slievr-menu capture") },
        { text: "Toggle…", glyph: "󰔡", sub: "toggles", run: sh("slievr-menu toggle") },
        { text: "Hardware…", glyph: "󰍹", run: sh("slievr-menu hardware") },
        { text: "Share…", glyph: "󰒖", run: sh("slievr-menu share") },
        { text: "Setup…", glyph: "󰒓", run: sh("slievr-menu setup") }
    ]
    // Connected from shell.qml once the lock (Task 14) and idle (Task 15) exist.
    signal lockRequested()
    signal idleToggleRequested()
    function results(query) {
        // Index tie-break: the engine's sort isn't stable, and the menu order is deliberate.
        return actions.map((a, i) => Object.assign({ key: "sys:" + a.text, score: Fuzzy.score(query, a.text), i }, a))
                      .filter(a => a.score > 0)
                      .sort((a, b) => (query ? b.score - a.score : 0) || a.i - b.i);
    }
}
