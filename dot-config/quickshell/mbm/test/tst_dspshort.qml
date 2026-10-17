import QtQuick
import QtTest
import "../settings/DspShort.js" as D

TestCase {
    name: "dspshort"
    readonly property var names: ["window.move", "window.close", "layout", "focus", "send_shortcut", "window.cycle_next", "window.bring_to_top", "workspace.toggle_special"]

    function test_parse_keys() {
        compare(D.parse("window.move workspace=3 follow=false"), { dsp: "window.move", args: { workspace: 3, follow: false } });
        compare(D.parse("  focus   workspace=e+1 "), { dsp: "focus", args: { workspace: "e+1" } });
        compare(D.parse("window.resize x=-100 y=0 relative=true"), { dsp: "window.resize", args: { x: -100, y: 0, relative: true } });
        compare(D.parse("send_shortcut mods=\"SUPER SHIFT\" key=Insert"), { dsp: "send_shortcut", args: { mods: "SUPER SHIFT", key: "Insert" } });
        // Quoted: stays text even when it looks like a number or a boolean.
        compare(D.parse("focus workspace=\"3\" x=\"true\""), { dsp: "focus", args: { workspace: "3", x: "true" } });
        compare(D.parse("x.y a=1.5"), { dsp: "x.y", args: { a: 1.5 } });
    }
    function test_parse_bare() {
        compare(D.parse("window.close"), { dsp: "window.close" });
        compare(D.parse("layout togglesplit"), { dsp: "layout", args: "togglesplit" });
        compare(D.parse("workspace.toggle_special scratchpad"), { dsp: "workspace.toggle_special", args: "scratchpad" });
        compare(D.parse("window.cycle_next false"), { dsp: "window.cycle_next", args: false });
        compare(D.parse("layout \"move +1\""), { dsp: "layout", args: "move +1" });
        compare(D.parse("layout \"a=b\""), { dsp: "layout", args: "a=b" });
        compare(D.parse("layout \"\""), { dsp: "layout", args: "" });
        compare(D.parse("layout \"say \\\"hi\\\" \\\\ there\""), { dsp: "layout", args: "say \"hi\" \\ there" });
    }
    function test_parse_list() {
        compare(D.parse("window.cycle_next; window.bring_to_top"), [{ dsp: "window.cycle_next" }, { dsp: "window.bring_to_top" }]);
        // A ; inside quotes is text.
        compare(D.parse("layout \"a;b\""), { dsp: "layout", args: "a;b" });
    }
    function test_parse_errors() {
        verify(D.parse("").error);
        verify(D.parse("   ").error);
        verify(D.parse("Window.Move").error);           // not a dispatcher name
        verify(D.parse("window.move 3 follow=false").error); // positional and key=value mixed
        verify(D.parse("layout a b").error);              // two bare words: quote text with spaces
        verify(D.parse("focus workspace=").error);        // no value
        verify(D.parse("focus workspace=1 workspace=2").error);
        verify(D.parse("layout \"open").error);           // unterminated quote
        verify(D.parse("window.close;").error);           // empty list entry
        verify(D.parse("focus 1x=2").error);              // bad key
    }
    function test_format() {
        compare(D.format({ dsp: "window.close" }), "window.close");
        compare(D.format({ dsp: "window.move", args: { workspace: 3, follow: false } }), "window.move workspace=3 follow=false");
        compare(D.format({ dsp: "layout", args: "togglesplit" }), "layout togglesplit");
        compare(D.format({ dsp: "focus", args: { workspace: "3" } }), "focus workspace=\"3\"");
        compare(D.format({ dsp: "send_shortcut", args: { mods: "SUPER SHIFT", key: "Insert" } }), "send_shortcut mods=\"SUPER SHIFT\" key=Insert");
        compare(D.format([{ dsp: "window.cycle_next", args: false }, { dsp: "window.bring_to_top" }]), "window.cycle_next false; window.bring_to_top");
        // Not a dispatcher action: nothing to show in short form.
        compare(D.format({ exec: "kitty" }), "");
        compare(D.format([{ exec: "kitty" }, { dsp: "window.close" }]), "");
        compare(D.format(null), "");
    }
    function test_roundtrip_data() {
        return [
            { tag: "bare", a: { dsp: "window.close" } },
            { tag: "keys", a: { dsp: "window.move", args: { workspace: 9, follow: false } } },
            { tag: "text", a: { dsp: "focus", args: { workspace: "special:scratchpad" } } },
            { tag: "numtext", a: { dsp: "focus", args: { workspace: "10" } } },
            { tag: "booltext", a: { dsp: "layout", args: "false" } },
            { tag: "neg", a: { dsp: "window.resize", args: { x: -100, y: 0, relative: true } } },
            { tag: "spaces", a: { dsp: "send_shortcut", args: { mods: "CTRL", key: "Insert", window: "activewindow" } } },
            { tag: "quotes", a: { dsp: "layout", args: "a \"b\" \\ c; d=e" } },
            { tag: "empty", a: { dsp: "layout", args: "" } },
            { tag: "posbool", a: { dsp: "window.cycle_next", args: false } },
            { tag: "posnum", a: { dsp: "group.active", args: 2 } },
            { tag: "list", a: [{ dsp: "window.cycle_next", args: false }, { dsp: "window.bring_to_top" }] },
        ];
    }
    function test_roundtrip(row) { compare(D.parse(D.format(row.a)), row.a); }
    // Every shipped dispatcher bind shows in short form and saves back unchanged.
    function test_defaults_roundtrip() {
        const xhr = new XMLHttpRequest();   // file:// reads need QML_XHR_ALLOW_FILE_READ=1 (the runner sets it)
        xhr.open("GET", Qt.resolvedUrl("../../../../dot-local/share/mbm/defaults/settings.json"), false);
        xhr.send();
        const binds = JSON.parse(xhr.responseText).binds;
        let n = 0;
        for (const id of Object.keys(binds)) {
            const a = binds[id].action, s = D.format(a);
            const acts = Array.isArray(a) ? a : [a];
            // exec/shell binds (and lists mixing them in) have no short form, by design.
            if (!acts.every(x => "dsp" in x)) continue;
            n++;
            verify(s !== "", id + ": a dispatcher action with no short form");
            compare(D.parse(s), a, id + ": " + s);
        }
        verify(n > 50, n + " dispatcher binds");
    }
    function test_valid() {
        verify(D.valid("window.move", names));
        verify(D.valid("layout", names));
        verify(!D.valid("window.nope", names));
        verify(!D.valid("", names));
        verify(!D.valid("window.move", []));
    }
    // What the editor checks before saving: parsed, and every name known.
    function test_check() {
        compare(D.check("window.move workspace=3", names), "");
        compare(D.check("window.close; window.bring_to_top", names), "");
        compare(D.check("window.nope", names), "unknown dispatcher \"window.nope\"");
        compare(D.check("window.close; nope", names), "unknown dispatcher \"nope\"");
        verify(D.check("layout a b", names) !== "");
    }
}
