import Quickshell
import QtQuick
import "../../theme"
import "../../components"

Row {
    spacing: 8
    SystemClock { id: clock; precision: SystemClock.Minutes }
    Glyph { text: Qt.formatDateTime(clock.date, "HH:mm"); font.bold: true }
    Glyph { text: Qt.formatDateTime(clock.date, "ddd d MMM").toLowerCase(); color: Theme.muted }
}
