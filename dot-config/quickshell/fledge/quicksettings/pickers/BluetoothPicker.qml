import QtQuick
import Quickshell.Bluetooth
import "../../theme"
import "../../services"
import "../../components"

// Per-device state machine (`attempt` = what we started, `failed`, both keyed by address, fed by
// the watchers below from the adapter's own stable model):
//   unpaired --click--> pair() : device.pairing => "Pairing…"
//        Bt's agent handles prompts and trusts/connects after pairing succeeds.
//        pairing ends unpaired => "Failed" + the agent's error and a retry hint.
//   paired --click--> connect() : state Connecting => "Connecting…" --> Connected
//        Connecting ends Disconnected => "Failed"
Column {
    id: p
    spacing: 4
    property var attempt: ({})   // address -> "pair" | "connect"
    property var failed: ({})    // address -> "pair" | "connect"
    property bool showUnnamed: false
    readonly property var shownDevices: Bt.visibleDevices(showUnnamed)
    readonly property int unnamedCount: Bt.devices.length - Bt.visibleDevices(false).length
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
                function onPairingChanged() {
                    if (!w.modelData.pairing && !w.modelData.paired && p.attempt[w.addr] === "pair") {
                        p.mark("attempt", w.addr, false);
                        p.mark("failed", w.addr, "pair");
                    }
                }
                function onStateChanged() {
                    const st = w.modelData.state;
                    if (st === BluetoothDeviceState.Connected) { p.mark("attempt", w.addr, false); p.mark("failed", w.addr, false); }
                    else if (st === BluetoothDeviceState.Disconnected && (p.attempt[w.addr] === "connect" || (p.attempt[w.addr] === "pair" && w.modelData.paired))) {
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
        else if (Bt.pairingAddress === d.address) Bt.cancelPairing();
        else if (d.state === BluetoothDeviceState.Connecting) { mark("attempt", d.address, false); d.disconnect(); }   // cancel
        else if (d.paired) { mark("attempt", d.address, "connect"); d.connect(); }
        else if (Bt.agentReady && !Bt.pairingAddress) { mark("attempt", d.address, "pair"); Bt.pair(d); }
    }
    readonly property bool pairFailed: Object.values(failed).includes("pair")

    Glyph { text: !Bt.available ? "No Bluetooth adapter" : !Bt.enabled ? "Bluetooth is off" : Bt.devices.length === 0 ? "No devices yet" : "Devices"; color: Theme.muted; font.pixelSize: Theme.fontSmall }
    Repeater {
        model: Bt.enabled ? p.shownDevices : []
        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property string fail: p.failed[modelData.address] ?? ""
            width: p.width; height: Bt.hasName(modelData) ? 58 : 40; radius: 7
            color: modelData.connected ? Theme.accentSoft : (ma.containsMouse ? Theme.surface : "transparent")
            Item {
                anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 12
                Glyph { id: deviceIcon; text: row.modelData.connected ? "󰂱" : "󰂯"; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: deviceIcon.right; anchors.leftMargin: 8
                    anchors.right: deviceStatus.left; anchors.rightMargin: 12
                    spacing: 6
                    Glyph { text: Bt.deviceName(row.modelData); textFormat: Text.PlainText; color: row.modelData.connected ? Theme.accent : Theme.fg; elide: Text.ElideRight; width: parent.width }
                    Glyph { visible: Bt.hasName(row.modelData); text: row.modelData.address; color: Theme.muted; font.pixelSize: Theme.fontSmall }
                }
                Glyph {
                    id: deviceStatus
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter; font.pixelSize: Theme.fontSmall
                    text: row.modelData.pairing || Bt.pairingAddress === row.modelData.address ? "Pairing…" : row.modelData.state === BluetoothDeviceState.Connecting ? "Connecting…" : row.fail || Bt.errors[row.modelData.address] ? "Failed"
                          : row.modelData.batteryAvailable ? Math.round(row.modelData.battery * 100) + "%" : (row.modelData.paired ? "" : "pair")
                    color: row.fail ? Theme.error : Theme.muted
                }
            }
            MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: p.activate(row.modelData) }
        }
    }
    Glyph {
        visible: Bt.enabled && p.unnamedCount > 0
        width: p.width
        text: p.showUnnamed ? "Hide unnamed devices" : "Show unnamed devices (" + p.unnamedCount + ")"
        color: Theme.accent; font.pixelSize: Theme.fontSmall
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: p.showUnnamed = !p.showUnnamed }
    }
    Glyph {
        visible: Bt.enabled && p.shownDevices.length === 0
        width: p.width; wrapMode: Text.Wrap
        text: "Looking for devices… Put your device in pairing mode."
        color: Theme.muted; font.pixelSize: Theme.fontSmall
    }
    Glyph { visible: p.pairFailed || Object.keys(Bt.errors).length > 0; width: p.width; wrapMode: Text.Wrap; textFormat: Text.PlainText; text: Object.values(Bt.errors).join("\n") || "Connection failed. Put the device in pairing mode and select it to retry."; color: Theme.error; font.pixelSize: Theme.fontSmall }
    Glyph { visible: !Bt.agentReady; width: p.width; wrapMode: Text.Wrap; textFormat: Text.PlainText; text: Bt.agentError || "Waiting for Bluetooth pairing…"; color: Theme.error; font.pixelSize: Theme.fontSmall }
}
