pragma Singleton
import Quickshell
import Quickshell.Bluetooth
import QtQuick

Singleton {
    id: root
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
    readonly property bool enabled: adapter?.enabled ?? false
    readonly property var devices: adapter ? [...adapter.devices.values].sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name)) : []
    readonly property var connected: devices.filter(d => d.connected)
    readonly property string glyph: !available ? "" : !enabled ? "󰂲" : connected.length ? "󰂱" : "󰂯"
    readonly property string summary: !available ? "Unavailable" : !enabled ? "Off" : connected.length ? connected[0].name : "On"

    function setEnabled(on) { if (adapter) adapter.enabled = on; }
    function discover(on) { if (adapter && adapter.enabled) adapter.discovering = on; }
}
