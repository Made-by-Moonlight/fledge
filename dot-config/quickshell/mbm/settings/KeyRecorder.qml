import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "../services"

// Captures one key combo. While recording, Hyprland sits in the empty
// `mbm-record` submap (generated with binds.lua), so its binds don't fire and
// every key reaches this window. A 10 s guard and SUPER+CTRL+ALT+Escape (in the
// submap) make sure nobody is left stuck there.
FocusScope {
    id: rec
    property bool active: false
    signal recorded(string mods, string key)
    signal cancelled()
    // The submap isn't loaded (e.g. binds.lua not loaded): dispatching to a missing submap
    // would leave every key dead, so nothing is dispatched and recording never starts.
    signal unavailable()
    // A combo that would bind a printable key system-wide (no modifier, or only Shift).
    signal refused(string reason)
    property bool entered: false     // Hyprland has confirmed the submap
    property bool aborted: false     // a deliberate stop while the probe ran

    function start() {
        if (active || probe.running) return;
        aborted = false;
        probe.running = true;
    }
    function stop() {
        if (probe.running) { aborted = true; probe.running = false; }
        if (!active) return;
        active = false;
        entered = false;
        guard.stop();
        Hypr.dispatch('hl.dsp.submap("reset")');
    }
    Component.onDestruction: stop()

    // Only enter the submap once it is known to exist (it has a bind: SUPER CTRL ALT, Escape).
    Process {
        id: probe
        command: ["sh", "-c", "hyprctl -j binds | grep -q '\"submap\": \"mbm-record\"'"]
        onExited: code => {
            if (rec.aborted) { rec.aborted = false; return; }
            if (code !== 0) { rec.unavailable(); return; }
            rec.entered = false;
            rec.active = true;
            Hypr.dispatch('hl.dsp.submap("mbm-record")');
            catcher.forceActiveFocus();
            guard.restart();
        }
    }
    // The submap was left under us (SUPER+CTRL+ALT+Escape, a reload): stop at once, or the next
    // key would both fire its bind and be recorded. `entered` ignores a stale event from before.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "submap" || !rec.active) return;
            if (event.data === "mbm-record") rec.entered = true;
            else if (rec.entered) { rec.stop(); rec.cancelled(); }
        }
    }
    Timer { id: guard; interval: 10000; onTriggered: { rec.stop(); rec.cancelled(); } }

    // Qt key -> Hyprland (xkb) key name. Letters, digits and anything unlisted fall through below.
    readonly property var names: ({
        [Qt.Key_Return]: "RETURN", [Qt.Key_Enter]: "KP_Enter", [Qt.Key_Space]: "SPACE", [Qt.Key_Tab]: "TAB",
        [Qt.Key_Backtab]: "TAB", [Qt.Key_Backspace]: "BACKSPACE", [Qt.Key_Delete]: "DELETE", [Qt.Key_Escape]: "ESCAPE",
        [Qt.Key_Left]: "LEFT", [Qt.Key_Right]: "RIGHT", [Qt.Key_Up]: "UP", [Qt.Key_Down]: "DOWN",
        [Qt.Key_Home]: "HOME", [Qt.Key_End]: "END", [Qt.Key_PageUp]: "Page_Up", [Qt.Key_PageDown]: "Page_Down",
        [Qt.Key_Insert]: "INSERT", [Qt.Key_Print]: "PRINT", [Qt.Key_Comma]: "COMMA", [Qt.Key_Period]: "PERIOD",
        [Qt.Key_Slash]: "slash",
        [Qt.Key_VolumeUp]: "XF86AudioRaiseVolume", [Qt.Key_VolumeDown]: "XF86AudioLowerVolume",
        [Qt.Key_VolumeMute]: "XF86AudioMute", [Qt.Key_MicMute]: "XF86AudioMicMute",
        [Qt.Key_MediaPlay]: "XF86AudioPlay", [Qt.Key_MediaPause]: "XF86AudioPause", [Qt.Key_MediaTogglePlayPause]: "XF86AudioPlay",
        [Qt.Key_MediaStop]: "XF86AudioStop", [Qt.Key_MediaNext]: "XF86AudioNext", [Qt.Key_MediaPrevious]: "XF86AudioPrev",
        [Qt.Key_MonBrightnessUp]: "XF86MonBrightnessUp", [Qt.Key_MonBrightnessDown]: "XF86MonBrightnessDown",
        [Qt.Key_KeyboardBrightnessUp]: "XF86KbdBrightnessUp", [Qt.Key_KeyboardBrightnessDown]: "XF86KbdBrightnessDown",
        [Qt.Key_PowerOff]: "XF86PowerOff", [Qt.Key_Sleep]: "XF86Sleep", [Qt.Key_Eject]: "XF86Eject",
        [Qt.Key_Calculator]: "XF86Calculator", [Qt.Key_HomePage]: "XF86HomePage", [Qt.Key_Mail]: "XF86Mail",
        [Qt.Key_Search]: "XF86Search", [Qt.Key_WLAN]: "XF86WLAN", [Qt.Key_Bluetooth]: "XF86Bluetooth",
        [Qt.Key_TouchpadToggle]: "XF86TouchpadToggle", [Qt.Key_Launch0]: "XF86Launch0", [Qt.Key_Launch1]: "XF86Launch1"
    })
    readonly property var modifierKeys: [Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_AltGr, Qt.Key_CapsLock, Qt.Key_NumLock, Qt.Key_ScrollLock]

    // Pure: (Qt key, Qt modifiers, xkb keycode) -> { mods, key }, or null for a bare modifier.
    // Mods come out in one order (SUPER SHIFT CTRL ALT) whatever order they were pressed in.
    function describe(qtKey, qtMods, scanCode) {
        if (modifierKeys.includes(qtKey)) return null;
        const mods = [];
        if (qtMods & Qt.MetaModifier) mods.push("SUPER");
        if (qtMods & Qt.ShiftModifier) mods.push("SHIFT");
        if (qtMods & Qt.ControlModifier) mods.push("CTRL");
        if (qtMods & Qt.AltModifier) mods.push("ALT");
        let key = names[qtKey];
        if (!key && qtKey >= Qt.Key_A && qtKey <= Qt.Key_Z) key = String.fromCharCode(qtKey);
        if (!key && qtKey >= Qt.Key_F1 && qtKey <= Qt.Key_F24) key = "F" + (qtKey - Qt.Key_F1 + 1);
        // Digits, punctuation, anything else: the xkb keycode, the form today's binds use (code:10 = "1").
        if (!key) key = "code:" + scanCode;
        return { mods: mods.join(" "), key };
    }
    // Letters, digits, punctuation, Space and raw keycodes type text: bound bare (or with only
    // Shift) they would hijack typing everywhere. F-keys, XF86 keys, Return, arrows etc. are fine.
    function isPrintable(key) { return /^([A-Z]|code:\d+|COMMA|PERIOD|slash|SPACE)$/.test(key); }

    Item {
        id: catcher
        focus: rec.active
        Keys.onPressed: e => {
            e.accepted = true;
            if (!rec.active) return;
            const d = rec.describe(e.key, e.modifiers, e.nativeScanCode);
            if (!d) return;                                                // wait for the real key
            if (e.key === Qt.Key_Escape && d.mods === "") { rec.stop(); rec.cancelled(); return; }
            rec.stop();
            if (rec.isPrintable(d.key) && !/SUPER|CTRL|ALT/.test(d.mods)) { rec.refused("Add a modifier (Super, Ctrl or Alt): " + (d.mods ? d.mods + " + " : "") + d.key + " alone would stop that key typing."); return; }
            rec.recorded(d.mods, d.key);
        }
    }
}
