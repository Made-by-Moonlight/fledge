import Quickshell
import QtQuick
import "../../theme"
import "../../services"
import "../../components"

// Click cycles the format; the choice is bar.clockFormat (read live, no apply).
//   0: 12:52  sun 11 oct    1: 12:52    2: 12:52:07  sunday 11 october 2026    3: 12:52 pm  sun 11 oct
// Seconds precision only while format 2 shows them. The font is monospaced, so digits don't
// change the tab's width from second to second (the bar frame reshapes whenever a tab resizes).
Item {
    id: root
    implicitWidth: row.implicitWidth; implicitHeight: row.implicitHeight
    // The value just asked for, until the setting file catches up: the next click must count from it,
    // not from the not-yet-reloaded setting, or a fast second click repeats the first step.
    property int pending: -1
    readonly property int fmt: pending >= 0 ? pending : Settings.clockFormat
    Timer { id: settle; interval: 2000; onTriggered: root.pending = -1 }   // never stuck if the write was lost
    Connections {
        target: Settings
        function onClockFormatChanged() { if (Settings.clockFormat === root.pending) root.pending = -1; }
        function onWriteFinished(ok) { if (!ok) root.pending = -1; }
    }
    SystemClock { id: clock; precision: root.fmt === 2 ? SystemClock.Seconds : SystemClock.Minutes }
    Row {
        id: row
        spacing: 8
        Glyph {
            text: Qt.formatDateTime(clock.date, root.fmt === 2 ? "HH:mm:ss" : root.fmt === 3 ? "hh:mm ap" : "HH:mm")
            font.bold: true
        }
        Glyph {
            visible: root.fmt !== 1
            text: Qt.formatDateTime(clock.date, root.fmt === 2 ? "dddd d MMMM yyyy" : "ddd d MMM").toLowerCase()
            color: Theme.muted
        }
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: { root.pending = (root.fmt + 1) % 4; settle.restart(); Settings.set([[".bar.clockFormat", root.pending]], false); }
    }
}
