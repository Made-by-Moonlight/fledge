pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// The shell's one way to change Hyprland, which runs a Lua config: legacy dispatch strings and
// `hyprctl keyword` are refused there. The QML twin of `fledge hypr` (same three calls, same
// failure rules), so the installer can share this file (self-contained for that reason).
//   Hypr.dispatch('hl.dsp.submap("reset")')   an hl.dsp expression
//   Hypr.set('input = { kb_layout = "gb" }')   the body of an hl.config({ … }) table
//   Hypr.evalLua('hl.env("X", "1")')          any Lua, in the config's Lua state (`eval` is
//                                              not a legal QML method name)
//   Hypr.lit(v)                                v as a Lua literal, for building the above from
//                                              values: Hypr.set("input = { kb_layout = " + Hypr.lit(l) + " }")
// hyprctl, not Hyprland.dispatch: that one reports nothing back to QML (a refused dispatch is only
// Quickshell's own "Dispatch request … failed" log line). hyprctl exits 0 on many refusals, so its
// output is checked too. Calls run one at a time, in order (a submap reset can't overtake an enter).
Singleton {
    id: root

    // Output that means hyprctl refused, rc 0 or not (see dot-local/share/fledge/bin/fledge).
    readonly property var refusals: ["error:", "only supported with the lua config manager", "Invalid dispatcher", "non-legacy parsers"]
    property var queue: []
    property var current: null   // the running call's command
    property var proc: null      // its Process: one per call, so its output is only its own
    // Our own flag: Process.running turns true only once hyprctl has started, so a second call
    // in the same tick would otherwise replace the first one's command.
    property bool busy: false

    function dispatch(expr) { run(["dispatch", expr]); }
    function set(body) { run(["eval", "hl.config({ " + body + " })"]); }
    function evalLua(code) { run(["eval", code]); }

    // A Lua string, number or boolean literal, escaped like mbm's lib/lua.jq (and `fledge hypr
    // quote`): \ " and newline escaped, other control characters as \ddd (three digits, so a
    // following digit can't join the escape). Anything else is a caller's bug: thrown.
    function lit(v) {
        if (typeof v === "boolean") return v ? "true" : "false";
        if (typeof v === "number") {
            if (!isFinite(v)) throw new Error("Hypr.lit: not a finite number: " + v);
            return String(v);
        }
        if (typeof v !== "string") throw new Error("Hypr.lit: needs text, a number or true/false, not " + typeof v);
        let s = '"';
        for (const ch of v) {
            const c = ch.codePointAt(0);
            if (ch === "\\") s += "\\\\";
            else if (ch === '"') s += '\\"';
            else if (c === 10) s += "\\n";
            else if (c < 32 || c === 127) s += "\\" + String(c).padStart(3, "0");
            else s += ch;
        }
        return s + '"';
    }

    function failed(code, out) { return code !== 0 || refusals.some(r => out.includes(r)); }
    function label() { return current ? current.slice(1).join(" ") : ""; }
    function run(args) {
        queue = [...queue, ["hyprctl", ...args]];
        next();
    }
    function next() {
        if (busy || queue.length === 0) return;
        busy = true;
        current = queue[0];
        queue = queue.slice(1);
        proc = runner.createObject(root, { command: current });
        proc.running = true;
        watchdog.restart();
    }
    // The call `p` is over (or given up on): move to the next one. A late signal from a call the
    // watchdog already gave up on is ignored.
    function finish(p, why) {
        if (p !== proc) return;
        watchdog.stop();
        if (why) console.warn("Hypr: " + why + " " + label());
        proc = null;
        busy = false;
        Qt.callLater(() => p.destroy());
        next();
    }

    Component {
        id: runner
        Process {
            id: p
            property bool exited: false
            stdout: StdioCollector { id: out }
            stderr: StdioCollector { id: err }
            onExited: code => {
                exited = true;
                const text = (out.text + err.text).trim();
                if (p === root.proc && root.failed(code, text)) console.warn("Hypr: " + root.label() + ": " + (text || "exit " + code));
            }
            // A binary that can't start never emits exited, it just drops `running`.
            onRunningChanged: if (!running) Qt.callLater(() => root.finish(p, p.exited ? "" : "could not run hyprctl for"))
        }
    }

    // A call that never starts or ends (running never toggles) must not stall every later one.
    Timer {
        id: watchdog
        interval: 5000
        onTriggered: {
            const p = root.proc;
            root.finish(p, "hyprctl gave no result within 5 s for");
            if (p) p.running = false;
        }
    }
}
