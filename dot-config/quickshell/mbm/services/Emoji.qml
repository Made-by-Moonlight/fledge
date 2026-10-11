pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// unicode-emoji's emoji-test.txt, fully-qualified entries only, loaded on first use.
Singleton {
    id: root
    property var all: []
    signal changed()
    // Setting the path starts the load (reload() alone never fires loaded on an unloaded preload:false view).
    property bool wanted: false
    function load() { wanted = true; }
    FileView {
        id: file
        path: root.wanted ? "/usr/share/unicode/emoji/emoji-test.txt" : ""
        preload: true
        onLoaded: {
            const out = [];
            for (const line of text().split("\n")) {
                // 1F600 ; fully-qualified # 😀 E1.0 grinning face
                const m = line.match(/;\s*fully-qualified\s*#\s*(\S+)\s+E[\d.]+\s+(.+)$/);
                if (m) out.push({ char: m[1], name: m[2] });
            }
            root.all = out;
            root.changed();
        }
    }
}
