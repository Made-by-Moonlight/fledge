import QtQuick
import Quickshell.Networking
import "../../theme"
import "../../services"
import "../../components"

// Per-network state machine (keyed by SSID in `failed`, fed by the watchers below):
//   idle --click--> Connecting (network.state) --> Connected   (row shows "Connected")
//                                              \-> connectionFailed => "Failed"
// Only an authentication failure (NoSecrets, WifiClientFailed, WifiAuthTimeout) on a *known* network
// reopens the password box; other dropouts (network lost, client disconnected, unknown) show "Failed"
// for a few seconds, nothing more. Submitting calls connectWithPsk alone: on a known network it
// rewrites the saved PSK in place (never forget() first, that races the update and loses the profile).
// Unknown secured networks open the password box straight away. Known rows also get a Forget action.
// `tried` lives in this picker, so closing the panel drops it: a later autoconnect failure can't prompt.
Column {
    id: p
    spacing: 4
    property var pending: null       // network waiting for a password
    property var failed: ({})        // ssid -> true after a failed connect, cleared on the next attempt
    property var tried: ({})         // ssid -> true while a connect we started is in flight
    signal releaseFocus()
    Component.onCompleted: Net.scan(true)
    Component.onDestruction: Net.scan(false)
    onPendingChanged: if (pending === null) releaseFocus()

    function mark(map, name, on) {
        const m = Object.assign({}, p[map]);
        if (on) m[name] = true; else delete m[name];
        p[map] = m;
    }

    // One watcher per network of the device's own (stable) model, so a failure signal is never
    // lost when the sorted row list below is rebuilt.
    Instantiator {
        model: Net.wifi ? Net.wifi.networks : null
        delegate: QtObject {
            id: w
            required property var modelData
            property Timer fade: Timer { interval: 4000; onTriggered: p.mark("failed", w.modelData.name, false) }
            property Connections c: Connections {
                target: w.modelData
                function onConnectionFailed(reason) {
                    if (!p.tried[w.modelData.name]) return;
                    p.mark("tried", w.modelData.name, false);
                    p.mark("failed", w.modelData.name, true);
                    const auth = reason === ConnectionFailReason.NoSecrets || reason === ConnectionFailReason.WifiClientFailed
                              || reason === ConnectionFailReason.WifiAuthTimeout;
                    // Saved password wrong or missing: ask again. Anything else just flashes "Failed".
                    if (auth && w.modelData.known) p.pending = w.modelData;
                    else w.fade.restart();
                }
                function onStateChanged() {
                    const st = w.modelData.state;
                    if (st === ConnectionState.Connecting) p.mark("failed", w.modelData.name, false);
                    if (st === ConnectionState.Connected) { p.mark("tried", w.modelData.name, false); p.mark("failed", w.modelData.name, false); }
                }
            }
        }
    }

    function connectTo(n) {
        mark("failed", n.name, false);
        mark("tried", n.name, true);
        n.connect();
    }
    function submit(psk) {
        const n = pending;
        pending = null;
        if (!n || !psk) return;
        mark("failed", n.name, false);
        mark("tried", n.name, true);
        n.connectWithPsk(psk);     // replaces the saved PSK of a known network; D-Bus only, never in a command line or a log
    }

    Glyph {
        text: !Net.available ? "Wi-Fi unavailable (NetworkManager not running)" : !Net.wifi ? "No Wi-Fi adapter" : !Net.wifiEnabled ? "Wi-Fi is off" : Net.networks.length === 0 ? "Searching…" : "Wi-Fi networks"
        color: Theme.muted; font.pixelSize: Theme.fontSmall
    }
    Repeater {
        model: Net.wifiEnabled ? Net.networks.slice(0, 12) : []
        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property bool connecting: modelData.state === ConnectionState.Connecting
            readonly property bool didFail: p.failed[modelData.name] === true
            width: p.width; height: 32; radius: 7
            color: modelData.connected ? Theme.accentSoft : (ma.containsMouse ? Theme.surface : "transparent")
            // In the Tab chain like the other controls: Space/Return do what a click does, Delete forgets.
            objectName: modelData.name
            activeFocusOnTab: true
            FocusRing { shown: row.activeFocus }
            Keys.onPressed: ev => {
                if ([Qt.Key_Space, Qt.Key_Return, Qt.Key_Enter].includes(ev.key)) { ev.accepted = true; if (!ev.isAutoRepeat) row.activate(); }
                else if (ev.key === Qt.Key_Delete && row.modelData.known) { ev.accepted = true; row.modelData.forget(); }
            }
            function activate() {
                const n = row.modelData;
                if (row.connecting) { p.mark("tried", n.name, false); n.disconnect(); }   // cancel: a late failure must not prompt
                else if (n.connected) n.disconnect();
                else if (n.known || n.security === WifiSecurityType.Open) p.connectTo(n);
                else p.pending = n;
            }
            Row {
                anchors.fill: parent; anchors.leftMargin: 8; spacing: 8
                Glyph { text: Net.strengthGlyph(row.modelData.signalStrength); anchors.verticalCenter: parent.verticalCenter }
                Glyph { text: row.modelData.name; color: row.modelData.connected ? Theme.accent : Theme.fg; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; width: p.width - 190 }
                Glyph {
                    anchors.verticalCenter: parent.verticalCenter; font.pixelSize: Theme.fontSmall
                    text: row.connecting ? "Connecting…" : row.didFail ? "Failed" : row.modelData.connected ? "Connected" : ""
                    color: row.didFail ? Theme.error : Theme.muted
                }
                Glyph { text: row.modelData.security !== WifiSecurityType.Open ? "󰌾" : ""; color: Theme.muted; anchors.verticalCenter: parent.verticalCenter }
                Glyph {
                    visible: row.modelData.known; text: "󰆴"; color: Theme.muted; anchors.verticalCenter: parent.verticalCenter
                    MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: row.modelData.forget() }
                }
            }
            MouseArea {
                id: ma; anchors.fill: parent; hoverEnabled: true; z: -1
                onClicked: row.activate()
            }
        }
    }
    Rectangle {
        visible: p.pending !== null
        width: p.width; height: 34; radius: 7; color: "transparent"; border.color: Theme.accent
        TextInput {
            id: psk
            anchors.fill: parent; anchors.margins: 8
            echoMode: TextInput.Password; color: Theme.fg; font.family: Theme.font; font.pixelSize: Theme.fontSize
            Glyph { visible: !psk.text; text: "Password for " + (p.pending?.name ?? ""); color: Theme.muted }
            Keys.onReturnPressed: { const t = text; text = ""; p.submit(t); }
            Keys.onEscapePressed: ev => { text = ""; p.pending = null; ev.accepted = true; }
        }
        onVisibleChanged: if (visible) psk.forceActiveFocus()
    }
}
