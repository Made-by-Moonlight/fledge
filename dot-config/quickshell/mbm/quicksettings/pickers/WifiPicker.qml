import QtQuick
import Quickshell.Networking
import "../../theme"
import "../../services"
import "../../components"

Column {
    id: p
    spacing: 4
    property var pending: null       // network waiting for a password
    Component.onCompleted: Net.scan(true)
    Component.onDestruction: Net.scan(false)

    Glyph {
        text: !Net.available ? "Wi-Fi unavailable (NetworkManager not running)" : !Net.wifi ? "No Wi-Fi adapter" : !Net.wifiEnabled ? "Wi-Fi is off" : Net.networks.length === 0 ? "Searching…" : "Wi-Fi networks"
        color: Theme.muted; font.pixelSize: Theme.fontSmall
    }
    Repeater {
        model: Net.wifiEnabled ? Net.networks.slice(0, 12) : []
        delegate: Rectangle {
            id: row
            required property var modelData
            width: p.width; height: 32; radius: 7
            color: modelData.connected ? Theme.accentSoft : (ma.containsMouse ? Theme.surface : "transparent")
            Row {
                anchors.fill: parent; anchors.leftMargin: 8; spacing: 8
                Glyph { text: Net.strengthGlyph(row.modelData.signalStrength); anchors.verticalCenter: parent.verticalCenter }
                Glyph { text: row.modelData.name; color: row.modelData.connected ? Theme.accent : Theme.fg; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; width: p.width - 90 }
                Glyph { text: row.modelData.security !== WifiSecurityType.Open ? "󰌾" : ""; color: Theme.muted; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea {
                id: ma; anchors.fill: parent; hoverEnabled: true
                onClicked: {
                    const n = row.modelData;
                    if (n.connected) n.disconnect();
                    else if (n.known || n.security === WifiSecurityType.Open) n.connect();
                    else p.pending = n;
                }
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
            // The password goes straight to NetworkManager over D-Bus; it is never logged or put in a command line.
            Keys.onReturnPressed: { const n = p.pending; p.pending = null; if (n && text) n.connectWithPsk(text); text = ""; }
            Keys.onEscapePressed: ev => { text = ""; p.pending = null; ev.accepted = true; }
        }
        onVisibleChanged: if (visible) psk.forceActiveFocus()
    }
}
