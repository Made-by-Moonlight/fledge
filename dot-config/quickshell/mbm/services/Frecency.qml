pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// How often/recently each launcher entry was used; ~/.local/state/mbm/launcher.json.
Singleton {
    id: root
    property var data: ({})

    // A fresh account has no state dir yet; make it before the first write.
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/mbm"])

    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.local/state/mbm/launcher.json"
        atomicWrites: true
        printErrors: false   // missing on a fresh account; that is fine
        onLoaded: { try { root.data = JSON.parse(text()) ?? {}; } catch (e) { root.data = {}; } }
        onLoadFailed: root.data = {}
    }

    function bump(key) {
        const d = Object.assign({}, data);
        d[key] = { count: (d[key]?.count ?? 0) + 1, last: Date.now() };
        data = d;
        file.setText(JSON.stringify(d));
    }
    function boost(key) {
        const e = data[key];
        if (!e) return 0;
        const days = (Date.now() - e.last) / 86400000;
        return Math.min(40, e.count * 4) * (days < 1 ? 1 : days < 7 ? 0.6 : 0.3);
    }
}
