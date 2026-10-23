import Quickshell
import Quickshell.Wayland
import QtQuick
import "../theme"
import "../services"
import "../components"

// "Running a snapshot": shown when the machine booted a snapper snapshot (Recovery.qml). Restore
// opens `fledge update recover` in a terminal; Not now (or Escape) closes it until the next boot,
// and the bar's updates module brings it back. Hidden under the lock, like the polkit dialog.
Scope {
    id: root
    readonly property bool shown: Recovery.open && !ShellState.locked

    Binding { target: ShellState; property: "recoveryOpen"; value: root.shown }
    onShownChanged: {
        if (!shown) return;
        ShellState.closePopups();
        win.openScreen = ShellState.focusedScreen();
    }

    PanelWindow {
        id: win
        // Fixed when the dialog opens: a live binding would recreate the surface.
        property var openScreen: ShellState.focusedScreen()
        visible: root.shown
        screen: openScreen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fledge-recovery"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.6)

        Pill {
            anchors.centerIn: parent
            width: 500; height: col.implicitHeight + 40
            radius: Theme.radiusLarge
            color: Theme.panelSolid

            Column {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                spacing: 12

                Glyph { text: "󰁯  Running a snapshot"; font.bold: true; font.pixelSize: Theme.fontLarge; color: Theme.accent }
                Glyph {
                    objectName: "recovery text"
                    width: parent.width; wrapMode: Text.Wrap
                    text: "This is snapshot " + Recovery.snapshot
                        + (Recovery.run ? ", taken before the update on " + Recovery.when : "") + "."
                        + (Recovery.run && Recovery.run.result !== "ok" ? " That update " + Recovery.how + "." : "")
                }
                Glyph {
                    width: parent.width; wrapMode: Text.Wrap; color: Theme.fgDim
                    text: "Changes to the system aren't kept until it's restored. Your files are your current ones. Restoring makes this your system again and keeps the one you booted away from as a backup."
                }
                Row {
                    anchors.right: parent.right
                    spacing: Theme.gap
                    Pill {
                        width: 96; height: 32; color: Theme.surface
                        Glyph { anchors.centerIn: parent; text: "Not now" }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Recovery.dismiss() }
                    }
                    Pill {
                        width: 128; height: 32; color: Theme.accent
                        Glyph { anchors.centerIn: parent; text: "Restore it…"; color: Theme.bg; font.bold: true }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Recovery.restore() }
                    }
                }
            }
        }

        Item {
            anchors.fill: parent
            focus: true
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Escape) Recovery.dismiss();
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) Recovery.restore();
                e.accepted = true;
            }
        }
    }
}
