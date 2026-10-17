import QtQuick
import QtQml.Models
import "modules"

// One section of the bar strip: a row of modules, no background of its own (the frame draws it).
// Sized to the visible modules, so a section whose modules all hide themselves is 0 wide.
Item {
    id: section
    property var modules: []
    property var screen
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    width: implicitWidth

    // Modules are the Row's own children (not wrapped in Loaders), so one that hides itself
    // (NowPlaying with no player, Title with no window) takes no space or spacing.
    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12
        Repeater {
            model: section.modules
            delegate: DelegateChooser {
                role: "modelData"
                DelegateChoice { roleValue: "workspaces"; Workspaces { anchors.verticalCenter: row.verticalCenter; screen: section.screen } }
                DelegateChoice { roleValue: "title"; Title { anchors.verticalCenter: row.verticalCenter } }
                DelegateChoice { roleValue: "clock"; Clock { anchors.verticalCenter: row.verticalCenter } }
                DelegateChoice { roleValue: "tray"; Tray { anchors.verticalCenter: row.verticalCenter; screen: section.screen } }
                DelegateChoice { roleValue: "glyphs"; Glyphs { anchors.verticalCenter: row.verticalCenter } }
                DelegateChoice { roleValue: "cog"; Cog { anchors.verticalCenter: row.verticalCenter } }
                DelegateChoice { roleValue: "media"; NowPlaying { anchors.verticalCenter: row.verticalCenter } }
            }
        }
    }
}
