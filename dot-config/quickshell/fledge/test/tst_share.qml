import QtQuick
import QtTest
import "../share/Share.js" as S

TestCase {
    name: "share"

    function test_parseTwo() {
        const w = S.parse("94[HC>]kitty[HT>]~ fish[HE>]5612a0[HA>]95[HC>]zen[HT>]YouTube — Zen[HE>]5612b0[HA>]");
        compare(w.length, 2);
        compare(w[0].handle, "94"); compare(w[0].cls, "kitty"); compare(w[0].title, "~ fish"); compare(w[0].address, "5612a0");
        compare(w[1].cls, "zen"); compare(w[1].title, "YouTube — Zen");
    }
    function test_parseEmpty() { compare(S.parse("").length, 0); compare(S.parse(undefined).length, 0); }
    // An empty title or class is still a window.
    function test_parseBlankFields() {
        const w = S.parse("7[HC>][HT>][HE>]ff[HA>]");
        compare(w.length, 1); compare(w[0].cls, ""); compare(w[0].title, "");
    }
    // A title may hold brackets and newlines.
    function test_parseOddTitle() { compare(S.parse("7[HC>]c[HT>]a [b]\nc[HE>]1[HA>]")[0].title, "a [b]\nc"); }
    function test_parseSkipsJunk() { compare(S.parse("junk[HA>]7[HC>]c[HT>]t[HE>]1[HA>]").length, 1); }

    // Seen in the VM: xdph listed 94252854480848 for the kitty window Hyprland calls 55b8f3e90fd0.
    function test_sameWindow() {
        verify(S.sameWindow("55b8f3e90fd0", "94252854480848"));
        verify(S.sameWindow("0x55b8f3e90fd0", "94252854480848"));
        verify(!S.sameWindow("55b8f3e90fd1", "94252854480848"));
        verify(!S.sameWindow("", ""));
        verify(!S.sameWindow("zz", "1"));
        verify(!S.sameWindow("55b8f3e90fd0", "0x55b8f3e90fd0"));
    }

    function test_answer() {
        compare(S.answer("window", "94", true), "r/window:94");
        compare(S.answer("screen", "DP-1", false), "/screen:DP-1");
    }
}
