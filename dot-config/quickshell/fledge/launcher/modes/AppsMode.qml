import Quickshell
import QtQuick
import "../Fuzzy.js" as Fuzzy
import "../../services"

Item {
    readonly property string name: "apps"
    readonly property string label: "Apps"
    readonly property string placeholder: "Search apps…"
    readonly property bool keepOpen: false

    // DesktopEntries fills in asynchronously; reading .values here inside the
    // caller's binding/refresh means a late fill is picked up via this signal.
    signal changed()
    Connections { target: DesktopEntries.applications; function onValuesChanged() { changed(); } }

    function results(query) {
        const out = [];
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay) continue;
            const kw = (e.keywords ?? []).join(" ");
            const s = Math.max(Fuzzy.score(query, e.name), Fuzzy.score(query, e.genericName) * 0.7, Fuzzy.score(query, kw) * 0.5);
            if (s <= 0) continue;
            // uwsm app puts it in its own scope, outside the shell's cgroup.
            out.push({ key: "app:" + e.id, text: e.name, sub: e.genericName || e.comment, icon: e.icon,
                       score: s + Frecency.boost("app:" + e.id),
                       run: () => { Frecency.bump("app:" + e.id); Quickshell.execDetached(["uwsm", "app", "--", e.id + ".desktop"]); } });
        }
        return out.sort((a, b) => b.score - a.score || a.text.localeCompare(b.text)).slice(0, 50);
    }
}
