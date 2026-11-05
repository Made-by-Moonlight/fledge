pragma Singleton
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick
import "Bluetooth.js" as Devices

Singleton {
    id: root
    property bool agentReady: false
    property string pairingAddress: ""
    property var prompt: null
    property var errors: ({})
    property string agentError: ""
    function deviceName(d) { return Devices.name(d); }
    function hasName(d) { return Devices.hasName(d); }
    function visibleDevices(showUnnamed) { return Devices.visible(devices, showUnnamed, pairingAddress); }
    function send(message) { if (agent.running) agent.write(JSON.stringify(message) + "\n"); }
    function pair(d) {
        if (!agentReady || pairingAddress) return;
        const next = Object.assign({}, errors); delete next[d.address]; errors = next;
        pairingAddress = d.address;
        send({command: "pair", address: d.address});
    }
    function respond(accept, value) {
        if (prompt) send({command: "respond", id: prompt.id, accept: accept, value: value || ""});
    }
    function cancelPairing() { send({command: "cancel"}); prompt = null; }
    Process {
        id: agent
        running: true
        stdinEnabled: true
        command: ["python3", decodeURIComponent(Qt.resolvedUrl("../bluetooth/agent.py").toString().replace(/^file:\/\//, ""))]
        stdout: SplitParser {
            onRead: line => {
                let event;
                try { event = JSON.parse(line); } catch (error) { return; }
                if (event.event === "ready") { root.agentReady = event.ready; if (event.ready) root.agentError = ""; else root.pairingAddress = ""; }
                else if (event.event === "prompt") root.prompt = event;
                else if (event.event === "clear") root.prompt = null;
                else if (event.event === "error") root.agentError = event.message;
                else if (event.event === "failed") {
                    root.errors = Object.assign({}, root.errors, {[event.address]: event.message});
                    root.pairingAddress = "";
                } else if (event.event === "paired") {
                    root.pairingAddress = "";
                    const d = root.devices.find(d => d.address === event.address);
                    if (d) { d.trusted = true; d.connect(); }
                }
            }
        }
        onExited: {
            root.agentReady = false; root.prompt = null; root.pairingAddress = "";
            root.agentError = "Bluetooth pairing helper unavailable. Update fledge and restart the shell.";
            retry.restart();
        }
    }
    Timer { id: retry; interval: 5000; onTriggered: agent.running = true }
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
    readonly property bool enabled: adapter?.enabled ?? false
    readonly property var devices: adapter ? [...adapter.devices.values].sort(Devices.compare) : []
    readonly property var connected: devices.filter(d => d.connected)
    readonly property string glyph: !available ? "" : !enabled ? "󰂲" : connected.length ? "󰂱" : "󰂯"
    readonly property string summary: !available ? "Unavailable" : !enabled ? "Off" : connected.length ? deviceName(connected[0]) : "On"

    function setEnabled(on) { if (adapter) adapter.enabled = on; }
    function discover(on) { if (adapter && adapter.enabled) adapter.discovering = on; }
}
