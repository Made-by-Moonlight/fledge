import Quickshell
import Quickshell.Io
import QtQuick
import "../Fuzzy.js" as Fuzzy
import "../../services"

Item {
    id: root
    readonly property string name: "dmenu"
    readonly property string label: ""
    readonly property string placeholder: ShellState.dmenu?.inputOnly ? "Type and press Enter" : "Filter…"
    readonly property bool keepOpen: true
    property var options: []
    readonly property int initialIndex: Math.max(0, (ShellState.dmenu?.select ?? 0) - 1)
    signal changed()

    FileView {
        path: ShellState.dmenu?.optionsFile ?? ""
        blockLoading: true
        onLoaded: { root.options = text().split("\n").filter(l => l.length); root.changed(); }
    }
    function results(query) {
        if (ShellState.dmenu?.inputOnly) return [];
        return options.map((o, i) => ({ key: i + ":" + o, text: o, score: Fuzzy.score(query, o), i }))
                      .filter(o => o.score > 0)
                      .sort((a, b) => query ? b.score - a.score : a.i - b.i);
    }
    // Enter: the highlighted option, or the typed text when nothing matches (dmenu behaviour).
    function submit(item, typed) { ShellState.dmenuFinish(true, item ? item.text : typed); }
}
