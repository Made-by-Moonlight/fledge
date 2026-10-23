pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// What `fledge update check --json` says is pending, for the bar's updates module. First
// checked 2 minutes after the shell starts (the network may not be up at login), then every
// 6 hours; `fledge update` asks for a recheck (IPC shell.recheck) when it finishes. One
// check at a time. A failed check keeps the last answer.
Singleton {
    id: root

    property var result: null
    readonly property bool checking: checker.running
    readonly property int count: result ? result.packages + result.aur + result.firmware + (result.fledge || result.bootstrap ? 1 : 0) : 0
    readonly property string summary: {
        if (!result) return "";
        const parts = [];
        if (result.fledge) parts.push("fledge " + result.fledge.to);
        else if (result.bootstrap) parts.push("fledge's setup to finish");
        if (result.packages) parts.push(result.packages + (result.packages === 1 ? " package" : " packages"));
        if (result.aur) parts.push(result.aur + " AUR");
        if (result.firmware) parts.push(result.firmware + " firmware");
        return parts.join(" · ");
    }

    function recheck() { if (!checker.running) checker.running = true; }
    function update() { Quickshell.execDetached(["fledge", "launch", "floating", "terminal", "with", "presentation", "fledge update"]); }

    Timer { interval: 2 * 60 * 1000; running: true; onTriggered: root.recheck() }
    Timer { interval: 6 * 60 * 60 * 1000; running: true; repeat: true; onTriggered: root.recheck() }

    Process {
        id: checker
        command: ["fledge", "update", "check", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    if (typeof r.packages === "number") root.result = r;
                } catch (e) { console.warn("fledge updates: unreadable check output"); }
            }
        }
    }
}
