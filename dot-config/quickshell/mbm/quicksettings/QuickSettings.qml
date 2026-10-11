import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../theme"
import "../services"
import "../components"
import "../notifications"
import "pickers"

PanelWindow {
    id: win
    property bool nightLight: false
    readonly property bool barTop: Settings.barPosition !== "bottom"

    // The screen is fixed when the panel opens: a live binding to the focused monitor would
    // recreate the surface (moving it, dropping the grab) whenever the pointer crosses monitors.
    property var openScreen: ShellState.focusedScreen()
    property bool opened: false
    Connections {
        target: ShellState
        function onQsOpenChanged() {
            if (ShellState.qsOpen) win.openScreen = ShellState.focusedScreen();
            win.opened = ShellState.qsOpen;
        }
    }
    visible: opened
    screen: openScreen
    anchors { top: win.barTop; bottom: !win.barTop; right: true }
    margins { top: Theme.popupTop; bottom: Theme.popupTop; right: Theme.popupSide }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "mbm-quicksettings"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    color: "transparent"
    implicitWidth: 340
    implicitHeight: Math.min(body.implicitHeight + 24, (screen?.height ?? 1080) - Theme.popupTop * 2)

    HyprlandFocusGrab { active: win.visible; windows: [win]; onCleared: ShellState.qsOpen = false }
    onVisibleChanged: if (visible) { Brightness.refresh(); nlQuery.running = true; }

    // Night light state is hyprsunset's temperature (4000 K = on, the vendored toggle's ON_TEMP).
    Process {
        id: nlQuery
        command: ["hyprctl", "hyprsunset", "temperature"]
        stdout: StdioCollector { onStreamFinished: win.nightLight = text.trim() === "4000" }
    }
    Timer { id: nlRecheck; interval: 1500; onTriggered: nlQuery.running = true }

    function picker(name) { ShellState.qsPicker = ShellState.qsPicker === name ? "" : name; }

    Pill {
        anchors.fill: parent
        radius: Theme.radiusLarge
        color: Theme.panelSolid
        focus: true
        Keys.onEscapePressed: ShellState.qsOpen = false

        Flickable {
            anchors.fill: parent; anchors.margins: 12
            contentHeight: body.implicitHeight; clip: true
            ColumnLayout {
                id: body
                width: parent.width
                spacing: 10

                GridLayout {
                    columns: 2; columnSpacing: 6; rowSpacing: 6; Layout.fillWidth: true
                    Tile { Layout.fillWidth: true; glyph: Net.glyph; title: "Wi-Fi"; sub: Net.summary; on: Net.wifi !== null && Net.wifiEnabled
                           expandable: Net.wifi !== null; onClicked: Net.setWifiEnabled(!Net.wifiEnabled); onExpand: win.picker("wifi") }
                    Tile { Layout.fillWidth: true; glyph: Bt.glyph || "󰂲"; title: "Bluetooth"; sub: Bt.summary; on: Bt.enabled
                           expandable: Bt.available; onClicked: Bt.setEnabled(!Bt.enabled); onExpand: win.picker("bluetooth") }
                    Tile { Layout.fillWidth: true; glyph: Notifs.dnd ? "󰂛" : "󰂚"; title: "Do not disturb"; sub: Notifs.dnd ? "on" : "off"; on: Notifs.dnd
                           onClicked: Notifs.toggleDnd() }
                    Tile { Layout.fillWidth: true; glyph: "󰖔"; title: "Night light"; sub: win.nightLight ? "on" : "off"; on: win.nightLight
                           onClicked: { Quickshell.execDetached(["slievr-toggle-nightlight"]); nlRecheck.restart(); } }
                }

                Loader { Layout.fillWidth: true; active: ShellState.qsPicker === "wifi"; visible: active; sourceComponent: WifiPicker { width: body.width } }
                Loader { Layout.fillWidth: true; active: ShellState.qsPicker === "bluetooth"; visible: active; sourceComponent: BluetoothPicker { width: body.width } }

                RowLayout {
                    Layout.fillWidth: true; spacing: 8; visible: Audio.ready
                    Glyph { text: Audio.muted ? "󰝟" : "󰕾"; MouseArea { anchors.fill: parent; onClicked: Audio.toggleMute() } }
                    Slider { Layout.fillWidth: true; value: Audio.volume; onMoved: v => Audio.setVolume(v) }
                    Glyph { text: Math.round(Audio.volume * 100); color: Theme.muted; Layout.preferredWidth: 28 }
                    Glyph { text: "›"; color: Theme.muted; MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: win.picker("audio") } }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 8; visible: Audio.source !== null
                    Glyph { text: Audio.micMuted ? "󰍭" : "󰍬"; MouseArea { anchors.fill: parent; onClicked: Audio.toggleMicMute() } }
                    Slider { Layout.fillWidth: true; value: Audio.micVolume; onMoved: v => Audio.setMicVolume(v) }
                    Glyph { text: Math.round(Audio.micVolume * 100); color: Theme.muted; Layout.preferredWidth: 28 }
                    Glyph { text: "›"; color: Theme.muted; MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: win.picker("audio") } }
                }
                Loader { Layout.fillWidth: true; active: ShellState.qsPicker === "audio"; visible: active; sourceComponent: AudioPicker { width: body.width } }
                RowLayout {
                    Layout.fillWidth: true; spacing: 8; visible: Brightness.available
                    Glyph { text: "󰃠" }
                    Slider { Layout.fillWidth: true; value: Brightness.value; onMoved: v => Brightness.set(v * 100) }
                    Glyph { text: Math.round(Brightness.value * 100); color: Theme.muted; Layout.preferredWidth: 28 }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 30; radius: 8; color: Theme.surface
                    Row {
                        anchors.fill: parent; anchors.margins: 2
                        Repeater {
                            model: [["Saver", PowerProfile.PowerSaver], ["Balanced", PowerProfile.Balanced], ["Performance", PowerProfile.Performance]]
                            delegate: Rectangle {
                                id: seg
                                required property var modelData
                                visible: modelData[1] !== PowerProfile.Performance || Power.hasPerformance
                                width: (parent.width) / (Power.hasPerformance ? 3 : 2); height: parent.height; radius: 6
                                color: Power.profile === modelData[1] ? Theme.bg : "transparent"
                                Glyph { anchors.centerIn: parent; text: seg.modelData[0]; font.pixelSize: Theme.fontSmall; color: Power.profile === seg.modelData[1] ? Theme.accent : Theme.fgDim }
                                MouseArea { anchors.fill: parent; onClicked: Power.setProfile(seg.modelData[1]) }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 6; visible: Notifs.history.length > 0
                    RowLayout {
                        Layout.fillWidth: true
                        Glyph { text: "Notifications"; color: Theme.muted; font.pixelSize: Theme.fontSmall; Layout.fillWidth: true }
                        Glyph { text: "Clear"; color: Theme.accent; font.pixelSize: Theme.fontSmall; MouseArea { anchors.fill: parent; onClicked: Notifs.dismissAll() } }
                    }
                    Repeater {
                        model: [...Notifs.history].reverse().slice(0, 20)
                        delegate: NotificationCard { required property var modelData; notification: modelData; width: body.width }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true; spacing: 6
                    Rectangle { Layout.fillWidth: true; height: 30; radius: 7; color: Theme.surface
                        Glyph { anchors.centerIn: parent; text: "󰒓  Settings" }
                        MouseArea { anchors.fill: parent; onClicked: ShellState.openSettings("") } }
                    Rectangle { Layout.fillWidth: true; height: 30; radius: 7; color: Theme.surface
                        Glyph { anchors.centerIn: parent; text: "󰐥  Power" }
                        MouseArea { anchors.fill: parent; onClicked: ShellState.openLauncher("system") } }
                }
            }
        }
    }
}
