pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// How often/recently each launcher entry was used; ~/.local/state/fledge/launcher.json.
Singleton {
    id: root
    property var data: ({})
    property bool loaded: false
    property var pending: []     // keys bumped before the saved history finished loading

    // A fresh account has no state dir yet; make it before the first write.
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/fledge"])

    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.local/state/fledge/launcher.json"
        atomicWrites: true
        printErrors: false   // missing on a fresh account; that is fine
        onLoaded: { try { root.data = JSON.parse(text()) ?? {}; } catch (e) { root.data = {}; } root.finishLoad(); }
        onLoadFailed: { root.data = {}; root.finishLoad(); }
    }

    // Replay bumps made while loading, on top of what was saved, so history is never clobbered.
    function finishLoad() {
        loaded = true;
        const q = pending;
        pending = [];
        for (const k of q) bump(k);
    }
    function bump(key) {
        if (!loaded) { pending = pending.concat([key]); return; }
        const d = Object.assign({}, data);
        d[key] = { count: (Number(d[key]?.count) || 0) + 1, last: Date.now() };
        data = d;
        file.setText(JSON.stringify(d));
    }
    function boost(key) {
        const e = data[key];
        if (!e) return 0;
        const days = (Date.now() - (Number(e.last) || 0)) / 86400000;
        return Math.min(40, (Number(e.count) || 0) * 4) * (days < 1 ? 1 : days < 7 ? 0.6 : 0.3);
    }
}
