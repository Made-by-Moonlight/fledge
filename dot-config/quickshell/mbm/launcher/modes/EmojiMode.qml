import Quickshell
import QtQuick
import "../Fuzzy.js" as Fuzzy
import "../../services"

// Not frecency-bumped per item (unbounded growth of launcher.json).
Item {
    readonly property string name: "emoji"
    readonly property string label: "Emoji"
    readonly property string placeholder: "Search emoji…"
    signal changed()
    Connections { target: Emoji; function onChanged() { changed(); } }
    function activated() { Emoji.load(); }
    function results(query) {
        const out = [];
        for (const e of Emoji.all) {
            const s = Fuzzy.score(query, e.name);
            if (s > 0) out.push({ key: e.char, text: e.name, glyph: e.char, score: s,
                                  run: () => Quickshell.execDetached(["wl-copy", e.char]) });
        }
        return out.sort((a, b) => b.score - a.score).slice(0, 80);
    }
}
