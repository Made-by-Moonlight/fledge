import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick
import "../../components"

Row {
    id: root
    property var screen: null
    spacing: 8
    Repeater {
        model: SystemTray.items.values
        delegate: Item {
            id: entry
            required property var modelData
            width: 16; height: 16
            anchors.verticalCenter: parent.verticalCenter
            // Themed names no installed theme provides (fcitx5's input-keyboard-symbolic) draw
            // Qt's magenta checkerboard and report status Ready, so ask the theme first: try the
            // name, then without "-symbolic", else show a Nerd Font glyph. Other URLs pass through.
            readonly property string raw: "" + entry.modelData.icon
            readonly property bool themed: raw.startsWith("image://icon/")
            readonly property string name: raw.replace("image://icon/", "").split("?")[0]
            readonly property string resolved: !themed ? raw
                : Quickshell.iconPath(name, true) !== "" ? raw
                : Quickshell.iconPath(name.replace(/-symbolic$/, ""), true) !== "" ? "image://icon/" + name.replace(/-symbolic$/, "")
                : ""
            IconImage { anchors.fill: parent; visible: entry.resolved !== ""; source: entry.resolved }
            Glyph {
                anchors.centerIn: parent
                visible: entry.resolved === ""
                text: /keyboard|input/.test(entry.name + " " + entry.modelData.id) ? "󰌌" : "󰀻"
            }
            QsMenuAnchor {
                id: menu
                menu: entry.modelData.menu
                anchor.item: entry
                anchor.edges: Edges.Bottom
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: mouse => {
                    if (mouse.button === Qt.MiddleButton) entry.modelData.secondaryActivate();
                    else if (mouse.button === Qt.RightButton || entry.modelData.onlyMenu) { if (entry.modelData.hasMenu) menu.open(); }
                    else entry.modelData.activate();
                }
            }
        }
    }
}
