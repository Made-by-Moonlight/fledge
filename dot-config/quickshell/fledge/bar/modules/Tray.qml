import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick
import "../../theme"
import "../../components"

Row {
    id: root
    property var screen: null
    spacing: 8

    // The icon source to draw for a tray icon string, or "" for the glyph fallback.
    function resolve(raw) {
        if (!raw.startsWith("image://icon/") || raw.includes("?path=")) return raw;
        const name = raw.replace("image://icon/", "").split("?")[0];
        if (name.startsWith("/")) return raw;
        if (Quickshell.iconPath(name, true) !== "") return raw;
        const bare = name.replace(/-symbolic$/, "");
        return Quickshell.iconPath(bare, true) !== "" ? "image://icon/" + bare : "";
    }
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
            readonly property string name: raw.replace("image://icon/", "").split("?")[0]
            readonly property string resolved: root.resolve(raw)
            IconImage { anchors.fill: parent; visible: entry.resolved !== ""; source: entry.resolved }
            Glyph {
                anchors.centerIn: parent
                visible: entry.resolved === ""
                font.pixelSize: Theme.barFont
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
