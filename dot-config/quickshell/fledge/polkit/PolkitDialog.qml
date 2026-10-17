import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import QtQuick
import "../theme"
import "../services"
import "../components"

// The session's polkit authentication agent (replaces polkit-gnome), styled like the lock prompt.
// polkit allows one agent per session: if another one (polkit-gnome) already holds it, polkit keeps
// sending requests there and this dialog never shows. Quickshell 0.3.2 can't tell: isRegistered
// reads true either way. So nothing else may start an agent (vm.sh shell stops polkit-gnome).
// Requests are handled one at a time; one arriving while another is open is refused (adopt()).
// Under the session lock nothing shows: the request waits (the caller keeps blocking) and the
// dialog appears after unlock. Locking while it is open hides it and wipes what was typed.
Scope {
    id: root

    // The typed response lives only in `secret.text`, a field of a plain JS object: writing it
    // emits no change signal, so nothing can bind to it; the field shows `typed`, its length.
    // It is handed to polkit once and wiped straight after, and on every failure, cancel, new
    // request, hide and lock. Never log it. `echoed` mirrors it only for a prompt polkit marks
    // as visible (responseVisible: a user name, never a password).
    readonly property var secret: ({ text: "" })
    property int typed: 0
    property string echoed: ""
    property int failures: 0
    // The request on screen (see adopt()).
    property var current: null
    readonly property var flow: current && !current.isCompleted ? current : null
    readonly property bool shown: flow !== null && !ShellState.locked
    // A response is with polkit; typing waits for its next prompt.
    readonly property bool checking: flow !== null && !flow.isResponseRequired && !flow.isCompleted

    function wipe() { secret.text = ""; typed = 0; echoed = ""; }
    function type(ch) {
        if (!flow?.isResponseRequired) return;
        secret.text += ch;
        typed = secret.text.length;
        if (flow.responseVisible) echoed = secret.text;
    }
    function backspace() {
        secret.text = secret.text.slice(0, -1);
        typed = secret.text.length;
        echoed = flow?.responseVisible ? secret.text : "";
    }
    function submit() {
        const f = flow;
        // An empty response is a wrong password to PAM: a stray or double Enter would cost a
        // faillock strike (three lock the account, lock screen included, for 10 minutes).
        if (!f || !f.isResponseRequired || ShellState.locked || secret.text === "") return;
        const v = secret.text;
        wipe();
        f.submit(v);
    }
    // Cancels the polkit request itself: the caller (pkexec, …) gets "not authorized".
    function cancel() {
        wipe();
        if (flow && !flow.isCompleted) flow.cancelAuthenticationRequest();
    }

    onFlowChanged: { wipe(); failures = 0; }
    // Popups stay shut while the dialog is up: they would take the keyboard (ShellState).
    Binding { target: ShellState; property: "polkitOpen"; value: root.shown }
    onShownChanged: {
        wipe();
        if (!shown) return;
        // Only one surface holds the keyboard: popups close (a waiting dmenu gets "cancel").
        ShellState.closePopups();
        win.openScreen = ShellState.focusedScreen();
    }
    Connections {
        target: root.flow
        function onAuthenticationFailed() { root.wipe(); root.failures++; }
        function onIsCompletedChanged() { root.current = null; root.adopt(); }
    }

    // One request at a time; one that arrives while another is open is refused (cancelled, so
    // its caller gets "not authorized" at once and can simply retry). Quickshell 0.3.2 can't
    // queue them: its agent activates every incoming request at once (agentimpl.cpp pops its
    // queue on activation, so the size check never sees one waiting), the newcomer replaces the
    // open one as `flow`, and when the open one finishes it deletes the newcomer's flow while
    // polkit still waits on it. That caller then hangs, and when it gives up, Quickshell crashes
    // (use after free in the cancel). Cancelling the newcomer straight away is the one order that
    // keeps it consistent: its own completion clears it, and the open request carries on. It also
    // means a request arriving while the user types can never swap the action the password is for.
    // Left over: if the open request's own caller gives up after that, Quickshell no longer
    // tracks it and never completes the flow, so the dialog stays until Cancel.
    function adopt() {
        const f = agent.flow;
        if (!f || f.isCompleted || f === current) return;
        if (!current || current.isCompleted) { current = f; return; }
        console.warn("fledge polkit: refused a second authentication request while one is open: " + f.actionId);
        // The refusal is a cancel, which faillock counts as a failure: say so every time.
        Quickshell.execDetached(["notify-send", "-u", "normal", "-a", "fledge", "--", "Authentication request cancelled",
            "Another app asked for admin access while a prompt was open: " + f.actionId]);
        // Not from inside the agent's own flow change.
        Qt.callLater(() => { if (f && !f.isCompleted) f.cancelAuthenticationRequest(); });
    }
    PolkitAgent {
        id: agent
        onFlowChanged: root.adopt()
    }

    PanelWindow {
        id: win
        // Fixed when the dialog opens, like the launcher: a live binding would recreate the surface.
        property var openScreen: ShellState.focusedScreen()
        visible: root.shown
        screen: openScreen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fledge-polkit"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.6)

        Pill {
            id: card
            anchors.centerIn: parent
            width: 460; height: col.implicitHeight + 40
            radius: Theme.radiusLarge
            color: Theme.panelSolid

            Column {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                spacing: 12

                Glyph { text: "󰌾  Authentication required"; font.bold: true; font.pixelSize: Theme.fontLarge; color: Theme.accent }
                // polkit's text is plain text: a caller-supplied message can't inject markup.
                Glyph {
                    width: parent.width
                    text: root.flow?.message ?? ""
                    textFormat: Text.PlainText; wrapMode: Text.Wrap
                }
                Glyph {
                    width: parent.width
                    readonly property var who: root.flow?.selectedIdentity ?? null
                    text: who ? "Authenticating as " + (who.isGroup ? "a member of " : "") + who.displayName : ""
                    visible: text !== ""
                    textFormat: Text.PlainText; elide: Text.ElideRight
                    color: Theme.fgDim
                }
                Glyph {
                    width: parent.width
                    text: root.flow?.actionId ?? ""
                    visible: text !== ""
                    textFormat: Text.PlainText; elide: Text.ElideMiddle
                    color: Theme.muted; font.pixelSize: Theme.fontSmall
                }

                Rectangle {
                    id: field
                    width: parent.width; height: 44
                    radius: Theme.radius
                    color: Theme.bgRaised
                    border.color: root.failures > 0 && root.typed === 0 ? Theme.error : (root.checking ? Theme.surface : Theme.accent)
                    border.width: 2
                    clip: true
                    Row {
                        visible: root.echoed === ""
                        anchors.centerIn: parent; spacing: 4
                        Repeater { model: root.typed; delegate: Rectangle { width: 8; height: 8; radius: 4; color: Theme.accent } }
                    }
                    Glyph {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                        visible: root.echoed !== ""
                        text: root.echoed
                        textFormat: Text.PlainText; elide: Text.ElideLeft
                    }
                    Glyph {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                        horizontalAlignment: Text.AlignHCenter
                        visible: root.typed === 0
                        text: root.checking ? "…"
                            : root.failures > 0 ? "wrong password (" + root.failures + ")"
                            : ((root.flow?.inputPrompt ?? "").replace(/:\s*$/, "") || "Password")
                        textFormat: Text.PlainText; elide: Text.ElideRight
                        color: root.failures > 0 ? Theme.error : Theme.muted
                        font.italic: true
                    }
                }
                // polkit/PAM info or error text (faillock's lockout notice, …).
                Glyph {
                    width: parent.width
                    text: root.flow?.supplementaryMessage ?? ""
                    visible: text !== ""
                    textFormat: Text.PlainText; wrapMode: Text.Wrap
                    maximumLineCount: 4; elide: Text.ElideRight
                    color: root.flow?.supplementaryIsError ? Theme.error : Theme.muted
                }

                Row {
                    anchors.right: parent.right
                    spacing: Theme.gap
                    Pill {
                        width: 96; height: 32; color: Theme.surface
                        Glyph { anchors.centerIn: parent; text: "Cancel" }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.cancel() }
                    }
                    Pill {
                        width: 128; height: 32; color: Theme.accent
                        opacity: root.flow?.isResponseRequired ? 1 : 0.5
                        Glyph { anchors.centerIn: parent; text: "Authenticate"; color: Theme.bg; font.bold: true }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.submit() }
                    }
                }
            }
        }

        // Keystrokes go straight to the dialog's secret; no TextInput holds a copy.
        Item {
            anchors.fill: parent
            focus: true
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.submit();
                else if (e.key === Qt.Key_Escape) root.cancel();
                else if (e.key === Qt.Key_Backspace) root.backspace();
                else if (e.key === Qt.Key_U && e.modifiers & Qt.ControlModifier) root.wipe();
                else if (e.text.length > 0 && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier)) && !/[\x00-\x1f\x7f]/.test(e.text)) root.type(e.text);
                e.accepted = true;
            }
        }
    }
}
