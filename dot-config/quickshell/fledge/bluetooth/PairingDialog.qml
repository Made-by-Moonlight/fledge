import QtQuick
import Quickshell
import Quickshell.Wayland
import "../services"
import "../theme"
import "../components"

Scope {
    id: root
    readonly property var request: Bt.prompt
    readonly property bool blocked: ShellState.locked || ShellState.polkitOpen || ShellState.shareOpen || ShellState.recoveryOpen
    readonly property bool shown: request !== null && !blocked
    readonly property bool inputNeeded: request?.kind === "pin" || request?.kind === "passkey"
    readonly property bool valid: request?.kind === "passkey" ? /^[0-9]{1,6}$/.test(input.text) : input.text.length > 0 && input.text.length <= 16
    Binding { target: ShellState; property: "bluetoothOpen"; value: root.shown }
    onBlockedChanged: if (blocked && (Bt.pairingAddress || Bt.prompt)) Bt.cancelPairing()
    onRequestChanged: {
        input.text = "";
        if (!request) return;
        if (blocked) { Bt.cancelPairing(); return; }
        ShellState.closePopups();
        win.openScreen = ShellState.focusedScreen();
        Qt.callLater(() => { if (root.inputNeeded) input.forceActiveFocus(); else keys.forceActiveFocus(); });
    }
    onShownChanged: if (!shown) Qt.callLater(() => {
        if (!root.blocked && !root.request) ShellState.openQuickSettings("bluetooth");
    })
    function accept() { if (!inputNeeded || valid) Bt.respond(true, input.text); }

    PanelWindow {
        id: win
        property var openScreen: ShellState.focusedScreen()
        visible: root.shown
        screen: openScreen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fledge-bluetooth-pairing"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.6)

        Pill {
            anchors.centerIn: parent
            width: 420; height: body.implicitHeight + 40
            color: Theme.panelSolid; radius: Theme.radiusLarge
            Column {
                id: body
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                spacing: 12
                Glyph { text: "Bluetooth pairing"; font.bold: true; font.pixelSize: Theme.fontLarge; color: Theme.accent }
                Glyph { width: parent.width; text: root.request?.name || root.request?.address || ""; textFormat: Text.PlainText; wrapMode: Text.Wrap }
                Glyph { text: root.request?.address || ""; font.pixelSize: Theme.fontSmall; color: Theme.muted }
                Glyph {
                    width: parent.width; wrapMode: Text.Wrap
                    text: root.request?.kind === "confirm" ? "Does this code match the code on your device?"
                        : root.request?.kind === "display" ? "Enter this code on your device, then press Enter there."
                        : root.request?.kind === "pin" ? "Enter the PIN for this device."
                        : root.request?.kind === "passkey" ? "Enter the six-digit passkey shown on your device."
                        : "Allow this device to connect?"
                }
                Glyph { visible: text !== ""; text: root.request?.code || ""; font.pixelSize: 30; font.bold: true; color: Theme.accent }
                Glyph { visible: (root.request?.entered ?? 0) > 0; text: (root.request?.entered ?? 0) + " digits entered"; color: Theme.muted }
                Glyph { visible: text !== ""; width: parent.width; text: root.request?.service || ""; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Theme.muted; font.pixelSize: Theme.fontSmall }
                Rectangle {
                    visible: root.inputNeeded
                    width: parent.width; height: 42; radius: Theme.radius; color: Theme.bgRaised
                    border.color: Theme.accent
                    TextInput {
                        id: input
                        anchors { fill: parent; margins: 10 }
                        color: Theme.fg; font.pixelSize: Theme.fontSize
                        maximumLength: root.request?.kind === "passkey" ? 6 : 16
                        selectByMouse: true
                        onAccepted: root.accept()
                        Keys.onEscapePressed: Bt.cancelPairing()
                    }
                }
                Row {
                    anchors.right: parent.right; spacing: Theme.gap
                    Pill {
                        width: 96; height: 34; color: Theme.surface
                        Glyph { anchors.centerIn: parent; text: "Cancel" }
                        MouseArea { anchors.fill: parent; onClicked: Bt.cancelPairing() }
                    }
                    Pill {
                        visible: root.request?.kind !== "display"
                        width: 110; height: 34; color: Theme.accent
                        opacity: !root.inputNeeded || root.valid ? 1 : 0.5
                        Glyph { anchors.centerIn: parent; text: root.inputNeeded ? "Pair" : "Confirm"; color: Theme.bg }
                        MouseArea { anchors.fill: parent; onClicked: root.accept() }
                    }
                }
            }
        }
        Item {
            id: keys
            anchors.fill: parent
            focus: !root.inputNeeded
            Keys.onEscapePressed: Bt.cancelPairing()
        }
    }
}
