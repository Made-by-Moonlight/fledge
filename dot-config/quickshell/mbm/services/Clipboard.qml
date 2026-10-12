pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// History via cliphist; the shell owns the `wl-paste --watch` store process.
Singleton {
    id: root
    property var entries: []          // raw `cliphist list` lines: "<id>\t<preview>"
    signal changed()

    Process {
        id: store
        command: ["wl-paste", "--watch", "cliphist", "store"]
        running: true
        onExited: restart.start()     // e.g. compositor restart; try again shortly
    }
    Timer { id: restart; interval: 2000; onTriggered: store.running = true }

    Process {
        id: lister
        command: ["cliphist", "list"]
        stdout: StdioCollector { onStreamFinished: { root.entries = text.split("\n").filter(l => l.length); root.changed(); } }
    }
    function refresh() { lister.running = true; }
    // wl-copy stays running to serve the selection: as its own uwsm app unit, so a
    // shell restart doesn't take the clipboard with it (EmojiMode does the same).
    function copy(line) { Quickshell.execDetached(["uwsm", "app", "--", "sh", "-c", 'printf "%s" "$1" | cliphist decode | wl-copy', "sh", line]); }
    function remove(line) {
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | cliphist delete', "sh", line]);
        entries = entries.filter(e => e !== line);
        changed();
    }
}
