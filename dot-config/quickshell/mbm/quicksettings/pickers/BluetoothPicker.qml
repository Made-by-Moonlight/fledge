import QtQuick
import Quickshell.Bluetooth
import "../../theme"
import "../../services"
import "../../components"

// Per-device state machine (`attempt` = what we started, `failed`, both keyed by address, fed by
// the watchers below from the adapter's own stable model):
//   unpaired --click--> pair() : device.pairing => "Pairing…"
//        paired becomes true  => trusted = true (so it reconnects later), then connect()
//        pairing ends unpaired => "Failed" + hint (no BlueZ agent here, so PIN/confirm pairing fails)
//   paired --click--> connect() : state Connecting => "Connecting…" --> Connected
//        Connecting ends Disconnected => "Failed"
Column {
    id: p
    spacing: 4
    property var attempt: ({})   // address -> "pair" | "connect"
    property var failed: ({})    // address -> "pair" | "connect"
    function mark(map, addr, v) {
        const m = Object.assign({}, p[map]);
        if (v) m[addr] = v; else delete m[addr];
        p[map] = m;
    }
    Component.onCompleted: Bt.discover(true)
    Component.onDestruction: Bt.discover(false)
    // Discovery can only run on a powered adapter: restart it when Bluetooth is switched on.
    Connections { target: Bt; function onEnabledChanged() { if (Bt.enabled) Bt.discover(true); } }

    Instantiator {
        model: Bt.adapter ? Bt.adapter.devices : null
        delegate: QtObject {
            id: w
            required property var modelData
            readonly property string addr: modelData.address
            property Connections c: Connections {
                target: w.modelData
                function onPairedChanged() {
                    if (w.modelData.paired && p.attempt[w.addr] === "pair") {
                        w.modelData.trusted = true;
                        p.mark("failed", w.addr, false);
                        p.mark("attempt", w.addr, "connect");
                        w.modelData.connect();
                    }
                }
                function onPairingChanged() {
                    if (!w.modelData.pairing && !w.modelData.paired && p.attempt[w.addr] === "pair") {
                        p.mark("attempt", w.addr, false);
                        p.mark("failed", w.addr, "pair");
                    }
                }
                function onStateChanged() {
                    const st = w.modelData.state;
                    if (st === BluetoothDeviceState.Connected) { p.mark("attempt", w.addr, false); p.mark("failed", w.addr, false); }
                    else if (st === BluetoothDeviceState.Disconnected && p.attempt[w.addr] === "connect") {
                        p.mark("attempt", w.addr, false);
                        p.mark("failed", w.addr, "connect");
                    }
                }
            }
        }
    }
    function activate(d) {
        mark("failed", d.address, false);
        if (d.connected) d.disconnect();
        else if (d.paired) { mark("attempt", d.address, "connect"); d.connect(); }
        else { mark("attempt", d.address, "pair"); d.pair(); }
    }
    readonly property bool pairFailed: Object.values(failed).includes("pair")

    Glyph { text: !Bt.available ? "No Bluetooth adapter" : !Bt.enabled ? "Bluetooth is off" : Bt.devices.length === 0 ? "No devices yet" : "Devices"; color: Theme.muted; font.pixelSize: Theme.fontSmall }
    Repeater {
        model: Bt.enabled ? Bt.devices.slice(0, 12) : []
        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property string fail: p.failed[modelData.address] ?? ""
            width: p.width; height: 32; radius: 7
            color: modelData.connected ? Theme.accentSoft : (ma.containsMouse ? Theme.surface : "transparent")
            Row {
                anchors.fill: parent; anchors.leftMargin: 8; spacing: 8
                Glyph { text: row.modelData.connected ? "󰂱" : "󰂯"; anchors.verticalCenter: parent.verticalCenter }
                Glyph { text: row.modelData.name || row.modelData.address; color: row.modelData.connected ? Theme.accent : Theme.fg; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; width: p.width - 130 }
                Glyph {
                    anchors.verticalCenter: parent.verticalCenter; font.pixelSize: Theme.fontSmall
                    text: row.modelData.pairing ? "Pairing…" : row.modelData.state === BluetoothDeviceState.Connecting ? "Connecting…" : row.fail ? "Failed"
                          : row.modelData.batteryAvailable ? Math.round(row.modelData.battery * 100) + "%" : (row.modelData.paired ? "" : "pair")
                    color: row.fail ? Theme.error : Theme.muted
                }
            }
            MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: p.activate(row.modelData) }
        }
    }
    Glyph { visible: p.pairFailed; width: p.width; wrapMode: Text.Wrap; text: "Needs a PIN — pair with bluetoothctl"; color: Theme.error; font.pixelSize: Theme.fontSmall }
}
