import QtQuick
import "../theme"
import "../components"

Pill {
    id: island
    property var modules: []
    property var screen
    visible: modules.length > 0
    height: Theme.barHeight
    width: row.implicitWidth + 24

    readonly property var sources: ({
        workspaces: "modules/Workspaces.qml", title: "modules/Title.qml", clock: "modules/Clock.qml",
        tray: "modules/Tray.qml", glyphs: "modules/Glyphs.qml", cog: "modules/Cog.qml", media: "modules/NowPlaying.qml"
    })

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 12
        Repeater {
            model: island.modules
            delegate: Loader {
                required property string modelData
                anchors.verticalCenter: parent.verticalCenter
                source: island.sources[modelData] ?? ""
                id: loader
                // A var property defaults to undefined, so bind rather than test it on load.
                Binding { target: loader.item; property: "screen"; value: island.screen; when: loader.item && "screen" in loader.item }
            }
        }
    }
}
