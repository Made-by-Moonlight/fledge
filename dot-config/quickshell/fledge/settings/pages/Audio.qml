import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "../../components"

// Output and input devices: pick the default, set its volume and mute. Live PipeWire state, not
// settings JSON, so nothing to apply. Per-app volume is on the Apps page.
Flickable {
    id: page
    contentHeight: col.implicitHeight; clip: true

    ColumnLayout {
        id: col
        width: page.width; spacing: 18

        Repeater {
            model: [
                { title: "Output", empty: "No output devices", nodes: Audio.sinks, current: Audio.sink,
                  volume: Audio.volume, muted: Audio.muted, ready: Audio.sink?.audio != null,
                  pick: n => Audio.setDefaultSink(n), set: v => Audio.setVolume(v),
                  step: d => Audio.stepVolume(d), mute: () => Audio.toggleMute(), on: "󰕾", off: "󰝟" },
                { title: "Input", empty: "No input devices", nodes: Audio.sources, current: Audio.source,
                  volume: Audio.micVolume, muted: Audio.micMuted, ready: Audio.source?.audio != null,
                  pick: n => Audio.setDefaultSource(n), set: v => Audio.setMicVolume(v),
                  step: d => Audio.stepMicVolume(d), mute: () => Audio.toggleMicMute(), on: "󰍬", off: "󰍭" }
            ]
            delegate: ColumnLayout {
                id: sec
                required property var modelData
                Layout.fillWidth: true
                spacing: 6
                Glyph { text: sec.modelData.title; color: Theme.muted; font.pixelSize: Theme.fontSmall }
                RowLayout {
                    Layout.fillWidth: true; spacing: 10; visible: sec.modelData.ready
                    Glyph {
                        Layout.preferredWidth: 18; horizontalAlignment: Text.AlignHCenter
                        text: sec.modelData.muted ? sec.modelData.off : sec.modelData.on
                        color: sec.modelData.muted ? Theme.muted : Theme.fg
                        Accessible.role: Accessible.Button
                        Accessible.name: (sec.modelData.muted ? "Unmute " : "Mute ") + sec.modelData.title.toLowerCase()
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sec.modelData.mute() }
                    }
                    Slider { Layout.fillWidth: true; value: sec.modelData.volume
                             onMoved: v => sec.modelData.set(v); onStepped: d => sec.modelData.step(d * 0.05) }
                    Glyph { text: Math.round(sec.modelData.volume * 100); color: Theme.muted; Layout.preferredWidth: 32 }
                }
                Glyph { visible: sec.modelData.nodes.length === 0; text: sec.modelData.empty; color: Theme.muted; leftPadding: 8 }
                Repeater {
                    model: sec.modelData.nodes
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        readonly property bool current: modelData === sec.modelData.current
                        Layout.fillWidth: true; implicitHeight: 34; radius: 7
                        color: current ? Theme.accentSoft : (ma.containsMouse ? Theme.surface : "transparent")
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: label.text
                        Accessible.checked: current
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 8
                            Glyph { id: label; Layout.fillWidth: true; elide: Text.ElideRight
                                    text: row.modelData.description || row.modelData.nickname || row.modelData.name
                                    color: row.current ? Theme.accent : Theme.fg }
                            Glyph { visible: row.current; text: "default"; color: Theme.accent; font.pixelSize: Theme.fontSmall }
                        }
                        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: sec.modelData.pick(row.modelData) }
                    }
                }
            }
        }
    }
}
