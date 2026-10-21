import QtQuick
import QtTest
import "../services/Main.js" as M

TestCase {
    name: "main"
    // The user's desk: two portrait BenQs either side of the Acer, set 560 px higher.
    readonly property var desk: [
        { key: "desc:BenqL", x: -1440, y: -560 },
        { key: "desc:Acer", x: 0, y: 0 },
        { key: "desc:BenqR", x: 3440, y: -560 }
    ]

    function test_mainNamed() { compare(M.pick(desk, "desc:Acer"), "desc:Acer"); }
    function test_mainUnset() { compare(M.pick(desk, ""), "desc:BenqL"); }
    function test_mainAbsent() { compare(M.pick(desk, "desc:Gone"), "desc:BenqL"); }
    function test_mainBack() {
        const without = desk.filter(m => m.key !== "desc:Acer");
        compare(M.pick(without, "desc:Acer"), "desc:BenqL");
        compare(M.pick(desk, "desc:Acer"), "desc:Acer");
    }
    // Higher up wins over further left.
    function test_topThenLeft() {
        compare(M.pick([{ key: "a", x: 0, y: 100 }, { key: "b", x: 2000, y: 0 }], ""), "b");
        compare(M.pick([{ key: "a", x: 2000, y: 0 }, { key: "b", x: 0, y: 0 }], ""), "b");
    }
    function test_noMonitors() { compare(M.pick([], "desc:Acer"), ""); }

    function test_mainBeatsHidden() { verify(M.showsBar("desc:Acer", desk, "desc:Acer", ["desc:Acer"])); }
    function test_fallbackMainBeatsHidden() { verify(M.showsBar("desc:BenqL", desk, "", ["desc:BenqL"])); }
    function test_hiddenOthers() {
        verify(!M.showsBar("desc:BenqL", desk, "desc:Acer", ["desc:BenqL"]));
        verify(M.showsBar("desc:BenqR", desk, "desc:Acer", ["desc:BenqL"]));
    }
    function test_noHiddenList() { verify(M.showsBar("desc:BenqR", desk, "desc:Acer", undefined)); }
}
