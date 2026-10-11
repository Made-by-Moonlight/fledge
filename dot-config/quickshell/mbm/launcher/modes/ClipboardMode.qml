import QtQuick
import "../Fuzzy.js" as Fuzzy
import "../../services"

// Not frecency-bumped per item: every copy is a new key and launcher.json would grow without bound.
Item {
    readonly property string name: "clipboard"
    readonly property string label: "Clipboard"
    readonly property string placeholder: "Search clipboard… (Shift+Del removes)"
    signal changed()
    Connections { target: Clipboard; function onChanged() { changed(); } }
    function activated() { Clipboard.refresh(); }
    function results(query) {
        return Clipboard.entries
            .map(l => ({ line: l, text: l.replace(/^\d+\t/, "") }))
            .filter(e => Fuzzy.score(query, e.text) > 0)
            .slice(0, 100)
            .map(e => ({ key: e.line, text: e.text, glyph: "󰅌", line: e.line, run: () => Clipboard.copy(e.line) }));
    }
    function remove(item) { if (item) Clipboard.remove(item.line); }
}
