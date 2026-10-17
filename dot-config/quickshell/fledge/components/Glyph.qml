import QtQuick
import "../theme"

// PlainText: most of what this shows is untrusted (window/media titles, notification
// app names and summaries, SSIDs, clipboard entries, dmenu options). The default
// AutoText would render markup such as <img src=…> from any of them. A caller that
// needs markup sets textFormat itself on input it has sanitised (notification body).
Text {
    textFormat: Text.PlainText
    color: Theme.fg
    font.family: Theme.font
    font.pixelSize: Theme.fontSize
    verticalAlignment: Text.AlignVCenter
}
