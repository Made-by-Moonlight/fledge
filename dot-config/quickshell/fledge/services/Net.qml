pragma Singleton
import Quickshell
import Quickshell.Networking
import QtQuick

Singleton {
    id: root
    readonly property var devices: Networking.devices.values
    readonly property bool available: Networking.backend === NetworkBackendType.NetworkManager
    readonly property var wifi: devices.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property bool present: devices.length > 0
    readonly property var wiredAny: devices.find(d => d.type === DeviceType.Wired) ?? null
    readonly property var wired: devices.find(d => d.type === DeviceType.Wired && d.connected) ?? null
    readonly property var activeWifi: wifi ? (wifi.networks.values.find(n => n.connected) ?? null) : null
    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property var networks: wifi ? [...wifi.networks.values].sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength)) : []

    function strengthGlyph(s) { return s > 0.75 ? "󰤨" : s > 0.5 ? "󰤥" : s > 0.25 ? "󰤢" : "󰤟"; }
    readonly property string glyph: !available ? "󰤫" : wired ? "󰈀" : !wifi ? (wiredAny ? "󰈂" : "󰤫") : activeWifi ? strengthGlyph(activeWifi.signalStrength) : wifiEnabled ? "󰤯" : "󰤮"
    readonly property string summary: !available ? "Unavailable" : wired ? "Wired" : !wifi ? (wiredAny ? "Disconnected" : "Unavailable") : activeWifi ? activeWifi.name : wifiEnabled ? "Not connected" : "Off"

    function setWifiEnabled(on) { Networking.wifiEnabled = on; }
    // A binding, not a one-off write: in the installer the picker is the first to use Net,
    // before Networking has listed the adapter, and a write to a null wifi was lost (stuck
    // on "Searching…"). Quickshell only lists networks while the scanner is on.
    property bool scanning: false
    function scan(on) { scanning = on; }
    Binding { target: root.wifi; property: "scannerEnabled"; value: root.scanning; when: root.wifi !== null }
}
