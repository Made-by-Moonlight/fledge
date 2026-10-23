import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
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
    // Per-app volume: one row per app playing audio, laid out like the volume row.
    Glyph { text: "Apps"; color: Theme.muted; font.pixelSize: Theme.fontSmall }
    Glyph { visible: Audio.streams.length === 0; text: "Nothing playing"; color: Theme.muted; leftPadding: 8 }
    Repeater {
        model: Audio.streams
        delegate: Column {
            id: app
            required property var modelData
            readonly property var audio: modelData.audio
            readonly property string name: Audio.appName(modelData)
            readonly property string media: modelData.properties["media.name"] ?? ""
            readonly property string icon: Audio.appIcon(modelData)
            width: p.width; leftPadding: 8; rightPadding: 8; spacing: 2
            RowLayout {
                width: p.width - 16; spacing: 8
                IconImage { Layout.preferredWidth: 16; Layout.preferredHeight: 16; visible: source != ""
                            source: app.icon ? Quickshell.iconPath(app.icon, true) : "" }
                Glyph { Layout.fillWidth: true; elide: Text.ElideRight; color: Theme.fg
                        text: app.media && app.media !== app.name ? app.name + " · " + app.media : app.name }
            }
            RowLayout {
                width: p.width - 16; spacing: 8
                Glyph { text: app.audio?.muted ? "󰝟" : "󰕾"; MouseArea { anchors.fill: parent; onClicked: Audio.toggleStreamMute(app.modelData) } }
                Slider { Layout.fillWidth: true; value: app.audio?.volume ?? 0
                         onMoved: v => Audio.setStreamVolume(app.modelData, v); onStepped: d => Audio.stepStreamVolume(app.modelData, d * 0.05) }
                Glyph { text: Math.round((app.audio?.volume ?? 0) * 100); color: Theme.muted; Layout.preferredWidth: 28 }
            }
        }
    }
}
