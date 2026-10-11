import QtQuick
import "../../theme"
import "../../services"
import "../../components"

Column {
    id: p
    spacing: 4
    Component.onCompleted: Bt.discover(true)
    Component.onDestruction: Bt.discover(false)

    Glyph { text: !Bt.available ? "No Bluetooth adapter" : !Bt.enabled ? "Bluetooth is off" : Bt.devices.length === 0 ? "No devices yet" : "Devices"; color: Theme.muted; font.pixelSize: Theme.fontSmall }
    Repeater {
        model: Bt.enabled ? Bt.devices.slice(0, 12) : []
        delegate: Rectangle {
            id: row
            required property var modelData
            width: p.width; height: 32; radius: 7
            color: modelData.connected ? Theme.accentSoft : (ma.containsMouse ? Theme.surface : "transparent")
            Row {
                anchors.fill: parent; anchors.leftMargin: 8; spacing: 8
                Glyph { text: row.modelData.connected ? "󰂱" : "󰂯"; anchors.verticalCenter: parent.verticalCenter }
                Glyph { text: row.modelData.name || row.modelData.address; color: row.modelData.connected ? Theme.accent : Theme.fg; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; width: p.width - 110 }
                Glyph { text: row.modelData.batteryAvailable ? Math.round(row.modelData.battery * 100) + "%" : (row.modelData.paired ? "" : "pair"); color: Theme.muted; font.pixelSize: Theme.fontSmall; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea {
                id: ma; anchors.fill: parent; hoverEnabled: true
                onClicked: row.modelData.connected ? row.modelData.disconnect() : (row.modelData.paired ? row.modelData.connect() : row.modelData.pair())
            }
        }
    }
}
