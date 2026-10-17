pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// fledge-probe's facts, and whether the internet is reachable (rechecked every
// 3 s until it is, so the Network step unlocks by itself).
Singleton {
    id: p
    property var facts: null
    property bool online: false
    function refresh() { factsProc.running = true; }

    Process {
        id: factsProc
        running: true
        command: Installer.dev ? ["cat", Installer.repo + "/cachyos/iso/installer/dev/facts.json"]
                               : ["sudo", "-n", "/usr/local/bin/fledge-probe", "facts"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const f = JSON.parse(text); p.facts = f; p.online = f.online; }
                catch (e) { console.warn("fledge-probe facts: " + e); }
            }
        }
    }
    Process {
        id: onlineProc
        command: Installer.dev ? ["true"] : ["sudo", "-n", "/usr/local/bin/fledge-probe", "online"]
        onExited: code => p.online = code === 0
    }
    Timer { interval: 3000; repeat: true; running: !p.online; onTriggered: onlineProc.running = true }
}
