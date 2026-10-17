import Quickshell
import QtQuick
import QtQuick.Layouts
import "../theme"
import "../services"
import "../components"

FloatingWindow {
    id: win
    visible: ShellState.settingsOpen
    title: "fledge · settings"
    implicitWidth: 920
    implicitHeight: 640
    color: Theme.bg
    onVisibleChanged: if (!visible) ShellState.settingsOpen = false

    // Escape closes, same as the settings.close IPC. Not mid-recording: there Escape cancels the
    // recording (Hyprland's fledge-record submap takes the key), and a stray one must not also close.
    // DisplayConfirm outlives this window, so closing never cancels its revert countdown.
    Shortcut {
        sequence: "Escape"
        enabled: win.visible && !ShellState.recording
        onActivated: ShellState.settingsOpen = false
    }

    // [id, glyph, label, page file]. Task 17's pages slot in by file name.
    readonly property var pages: [
        ["keybinds", "⌨", "Keybinds", "Keybinds"], ["displays", "󰍹", "Displays", "Displays"], ["bar", "󰕮", "Bar", "Bar"],
        ["idle", "󰒲", "Idle & lock", "Idle"], ["input", "󰌌", "Input", "Input"]
    ]
    readonly property var current: pages.find(p => p[0] === ShellState.settingsPage) ?? pages[0]

    RowLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.fillHeight: true; Layout.preferredWidth: 170; color: Qt.darker(Theme.bg, 1.25)
            Column {
                anchors.fill: parent; anchors.margins: 10; spacing: 2
                Item {
                    width: parent.width; height: 34
                    Glyph { anchors.verticalCenter: parent.verticalCenter; x: 8; text: "◐ settings"; color: Theme.accent }
                    Rectangle {
                        id: closeBtn
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: 26; height: 26; radius: 7
                        color: closeArea.containsMouse ? Theme.surface : "transparent"
                        Accessible.role: Accessible.Button
                        Accessible.name: "Close settings"
                        Glyph { anchors.centerIn: parent; text: "×"; font.pixelSize: Theme.fontLarge; color: closeArea.containsMouse ? Theme.error : Theme.fgDim }
                        MouseArea { id: closeArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: ShellState.settingsOpen = false }
                    }
                }
                Repeater {
                    model: win.pages
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool on: win.current[0] === modelData[0]
                        width: parent.width; height: 32; radius: 7; color: on ? Theme.surface : "transparent"
                        Glyph { anchors.verticalCenter: parent.verticalCenter; x: 10; text: parent.modelData[1] + "  " + parent.modelData[2]; color: parent.on ? Theme.accent : Theme.fgDim }
                        MouseArea { anchors.fill: parent; onClicked: ShellState.settingsPage = parent.modelData[0] }
                    }
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 16
            spacing: 10
            Rectangle {
                Layout.fillWidth: true; visible: Settings.lastError !== ""; implicitHeight: err.implicitHeight + 16; radius: 7
                color: Qt.alpha(Theme.error, 0.15); border.color: Theme.error
                Glyph { id: err; anchors.fill: parent; anchors.margins: 8; text: Settings.lastError; color: Theme.error; wrapMode: Text.Wrap }
            }
            // Shown on every page: the change stays until it is kept, and reverts on its own even
            // with this window closed (DisplayConfirm).
            Rectangle {
                Layout.fillWidth: true; visible: DisplayConfirm.active && !DisplayConfirm.awaiting; implicitHeight: 50; radius: 7
                color: Theme.accentSoft; border.color: Theme.accent
                RowLayout {
                    anchors.fill: parent; anchors.margins: 10
                    Glyph { Layout.fillWidth: true; text: "Keep these display settings? Reverting in " + DisplayConfirm.countdown + " s" }
                    Button { text: "Keep"; primary: true; onClicked: DisplayConfirm.keep() }
                    Button { text: "Revert"; onClicked: DisplayConfirm.revert() }
                }
            }
            // Only the open window builds a page, and leaving a page drops it (and any recording in it).
            Loader {
                Layout.fillWidth: true; Layout.fillHeight: true
                active: win.visible
                source: "pages/" + win.current[3] + ".qml"
            }
        }
    }
}
