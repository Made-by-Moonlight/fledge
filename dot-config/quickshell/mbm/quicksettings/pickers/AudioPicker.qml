import QtQuick
import "../../theme"
import "../../services"
import "../../components"

Column {
    id: p
    spacing: 4
    Repeater {
        model: [{ title: "Output", nodes: Audio.sinks, current: Audio.sink, pick: n => Audio.setDefaultSink(n) },
                { title: "Input", nodes: Audio.sources, current: Audio.source, pick: n => Audio.setDefaultSource(n) }]
        delegate: Column {
            id: group
            required property var modelData
            width: p.width; spacing: 2
            Glyph { text: group.modelData.title; color: Theme.muted; font.pixelSize: Theme.fontSmall }
            Glyph { visible: group.modelData.nodes.length === 0; text: "None"; color: Theme.muted; leftPadding: 8 }
            Repeater {
                model: group.modelData.nodes
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool current: modelData === group.modelData.current
                    width: p.width; height: 30; radius: 7
                    color: current ? Theme.accentSoft : (ma.containsMouse ? Theme.surface : "transparent")
                    Glyph { anchors.verticalCenter: parent.verticalCenter; x: 8; width: p.width - 16; elide: Text.ElideRight
                            text: row.modelData.description || row.modelData.nickname || row.modelData.name; color: row.current ? Theme.accent : Theme.fg }
                    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: group.modelData.pick(row.modelData) }
                }
            }
        }
    }
}
