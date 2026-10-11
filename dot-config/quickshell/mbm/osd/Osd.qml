import Quickshell
import Quickshell.Wayland
import QtQuick
import "../theme"
import "../services"
import "../components"

// Bottom-centre overlay for volume, brightness, mic and script messages.
PanelWindow {
    id: osd
    property string icon: ""
    property string text: ""
    property real value: -1          // 0–1, or < 0 for a message without a bar

    // swayosd-shim icon names are freedesktop names; Glyph renders text, so map the common ones.
    readonly property var iconMap: ({
        "display-brightness-symbolic": "󰃠", "keyboard-brightness-symbolic": "󰌌",
        "input-touchpad-symbolic": "󰟸", "touchpad-disabled-symbolic": "󰤳",
        "audio-input-microphone-symbolic": "󰍬", "microphone-sensitivity-muted-symbolic": "󰍭"
    })

    function show(icon, text, value) {
        osd.icon = iconMap[icon] ?? icon; osd.text = text; osd.value = value;
        screen = ShellState.focusedScreen();
        visible = true;
        hide.restart();
    }

    visible: false
    anchors.bottom: true
    margins.bottom: 80
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "mbm-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    implicitWidth: 320
    implicitHeight: 52

    Timer { id: hide; interval: 1500; onTriggered: osd.visible = false }

    Pill {
        anchors.fill: parent
        radius: Theme.radiusLarge
        Row {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12
            Glyph { id: ic; text: osd.icon; font.pixelSize: Theme.fontLarge; anchors.verticalCenter: parent.verticalCenter }
            Rectangle {
                visible: osd.value >= 0
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - ic.width - num.width - 24
                height: 6; radius: 3; color: Theme.surface
                Rectangle { width: parent.width * Math.min(1, Math.max(0, osd.value)); height: parent.height; radius: 3; color: Theme.accent
                    Behavior on width { NumberAnimation { duration: 80 } } }
            }
            Glyph { id: num; text: osd.value >= 0 ? Math.round(osd.value * 100) : osd.text; color: osd.value >= 0 ? Theme.fgDim : Theme.fg; anchors.verticalCenter: parent.verticalCenter }
        }
    }
}
