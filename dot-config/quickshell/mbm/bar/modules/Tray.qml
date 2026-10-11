import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick

Row {
    id: root
    property var screen
    spacing: 8
    Repeater {
        model: SystemTray.items.values
        delegate: Item {
            id: entry
            required property var modelData
            width: 16; height: 16
            anchors.verticalCenter: parent.verticalCenter
            IconImage { anchors.fill: parent; source: entry.modelData.icon }
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
