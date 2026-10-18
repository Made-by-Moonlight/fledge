import QtQuick
import "../theme"

// The keyboard-focus ring: a 2 px outline just inside its parent's box (outside, it would
// be clipped by the Flickables the settings pages and quick settings scroll in). Accent,
// or the foreground on a box filled with the accent (a primary button, a toggle that's
// on, an "on" tile), where an accent ring wouldn't show.
Rectangle {
    property bool shown
    property bool onAccent: false
    visible: shown
    anchors.fill: parent
    radius: parent.radius ?? 0
    color: "transparent"; border.width: 2; border.color: onAccent ? Theme.fg : Theme.accent
}
