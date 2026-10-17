pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// xkb layouts and variants from xkeyboard-config's rules, and live switching
// (Hypr, the Lua config's hl.config) so the chosen layout is what the password
// fields type.
Singleton {
    id: k
    property var layouts: []        // [{ value, label }]
    property var variants: ({})     // layout -> [{ value, label }]
    // When apply() last switched: the shell tells the "activelayout" events this
    // causes apart from the ones a VT switch back to the installer causes.
    property real appliedAt: 0
    FileView {
        path: "/usr/share/X11/xkb/rules/base.lst"
        onLoaded: k.parse(text())
    }
    function parse(t) {
        const L = [], V = {};
        let sec = "";
        for (const line of t.split("\n")) {
            if (line.startsWith("! ")) { sec = line.slice(2).trim(); continue; }
            const m = /^\s+(\S+)\s+(.*)$/.exec(line);
            if (!m) continue;
            if (sec === "layout") L.push({ value: m[1], label: m[1] + "  ·  " + m[2] });
            else if (sec === "variant") {
                const v = /^(\S+):\s*(.*)$/.exec(m[2]);
                if (v) (V[v[1]] = V[v[1]] || []).push({ value: m[1], label: v[2] });
            }
        }
        layouts = L; variants = V;
    }
    function apply(layout, variant) {
        if (Installer.dev) return;      // don't rewire the dev VM's desktop keyboard
        appliedAt = Date.now();
        // Layout and variant change together, in one config call.
        Hypr.set("input = { kb_layout = " + Hypr.lit(layout) + ", kb_variant = " + Hypr.lit(variant) + " }");
    }
}
