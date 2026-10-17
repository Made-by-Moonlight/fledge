pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// The shell's one way to change Hyprland, which runs a Lua config: legacy dispatch strings and
// `hyprctl keyword` are refused there. The QML twin of `fledge hypr` (same three calls, same
// failure rules), so the installer can share this file.
//   Hypr.dispatch('hl.dsp.submap("reset")')   an hl.dsp expression
//   Hypr.set('input = { kb_layout = "gb" }')   the body of an hl.config({ … }) table
//   Hypr.evalLua('hl.env("X", "1")')          any Lua, in the config's Lua state (`eval` is
//                                              not a legal QML method name)
// hyprctl, not Hyprland.dispatch: that one reports nothing back to QML (a refused dispatch is only
// Quickshell's own "Dispatch request … failed" log line). hyprctl exits 0 on many refusals, so its
// output is checked too. Calls run one at a time, in order (a submap reset can't overtake an enter).
Singleton {
    id: root

    // Output that means hyprctl refused, rc 0 or not (see dot-local/share/fledge/bin/fledge).
    readonly property var refusals: ["error:", "only supported with the lua config manager", "Invalid dispatcher", "non-legacy parsers"]
    property var queue: []
    property var current: null
    // Our own flag: Process.running turns true only once hyprctl has started, so a second call
    // in the same tick would otherwise replace the first one's command.
    property bool busy: false

    function dispatch(expr) { run(["dispatch", expr]); }
    function set(body) { run(["eval", "hl.config({ " + body + " })"]); }
    function evalLua(code) { run(["eval", code]); }

    function failed(code, out) { return code !== 0 || refusals.some(r => out.includes(r)); }
    function run(args) {
        queue = [...queue, ["hyprctl", ...args]];
        next();
    }
    function next() {
        if (busy || queue.length === 0) return;
        busy = true;
        current = queue[0];
        queue = queue.slice(1);
        proc.exited = false;
        proc.command = current;
        proc.running = true;
    }

    Process {
        id: proc
        property bool exited: false
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            exited = true;
            const text = (out.text + err.text).trim();
            if (root.failed(code, text)) console.warn("Hypr: " + root.current.slice(1).join(" ") + ": " + (text || "exit " + code));
        }
        // A binary that can't start never emits exited, it just drops `running`.
        onRunningChanged: if (!running) Qt.callLater(() => {
            if (proc.running || !root.busy) return;
            if (!proc.exited) console.warn("Hypr: could not run hyprctl for " + root.current.slice(1).join(" "));
            root.busy = false;
            root.next();
        })
    }
}
