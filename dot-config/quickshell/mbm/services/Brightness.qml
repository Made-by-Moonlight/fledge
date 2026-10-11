pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Display backlight through brightnessctl (no Quickshell service for it).
Singleton {
    id: root
    property bool available: false
    property real value: 0

    function refresh() { reader.running = true; }
    function set(percent) {
        const p = Math.max(1, Math.min(100, Math.round(percent)));
        Quickshell.execDetached(["brightnessctl", "-q", "-c", "backlight", "set", p + "%"]);
        value = p / 100;
    }
    // ±5 steps by 1 at or below 5% (same feel as slievr-brightness-display); other deltas are exact.
    function step(delta) {
        const cur = Math.round(value * 100);
        if (Math.abs(delta) === 5) set(delta > 0 ? (cur < 5 ? cur + 1 : cur + 5) : (cur <= 5 ? cur - 1 : cur - 5));
        else set(cur + delta);
    }

    Process {
        id: reader
        command: ["brightnessctl", "-m", "-c", "backlight"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split(",");   // device,class,current,percent,max
                root.available = f.length >= 5;
                if (root.available) root.value = parseInt(f[3]) / 100;
            }
        }
    }
}
